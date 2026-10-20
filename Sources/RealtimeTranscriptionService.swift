import Foundation
import os.log

private let realtimeLog = OSLog(subsystem: "com.ansumanshukla.suki", category: "RealtimeTranscription")

enum RealtimeTranscriptionError: LocalizedError {
    case invalidBaseURL(String)
    case notConnected
    case serverError(code: String, message: String)
    case closedBeforeFinal
    case connectionFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidBaseURL(let url): return "Cannot derive a WebSocket URL from \(url)"
        case .notConnected: return "Realtime transcription socket is not connected"
        case .serverError(let code, let message): return "Realtime server error [\(code)]: \(message)"
        case .closedBeforeFinal: return "Realtime socket closed before emitting the final transcript"
        case .connectionFailed(let message): return message
        }
    }

    /// Describe why a socket closed before the session became usable,
    /// preferring the HTTP handshake status and the server's close reason.
    static func connectionFailure(for task: URLSessionWebSocketTask, host: String?) -> RealtimeTranscriptionError {
        if let status = (task.response as? HTTPURLResponse)?.statusCode, status != 101 {
            return .connectionFailed(TranscriptionService.friendlyHTTPMessage(status: status, host: host))
        }
        if let reasonData = task.closeReason,
           let reason = String(data: reasonData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !reason.isEmpty {
            return .connectionFailed("Live transcription closed by \(host ?? "the provider"): \(reason)")
        }
        return .connectionFailed("Could not connect to live transcription at \(host ?? "the provider").")
    }
}

final class RealtimeTranscriptionService: LiveTranscriptionSession {
    struct Configuration {
        let baseURL: String
        let apiKey: String
        let model: String
        let language: String?
    }

    private let config: Configuration
    private let session: URLSession
    private var task: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?

    private let stateQueue = DispatchQueue(label: "com.ansumanshukla.suki.realtime.state")
    private var finalText: String = ""
    private var partialText: String = ""
    private var finalContinuation: CheckedContinuation<String, Error>?
    private var commitSent: Bool = false
    private var closed: Bool = false
    private var terminalError: Error?
    private var serverEventCount: Int = 0
    private var commitEventCount: Int?
    private var postCommitCompleted: Bool = false
    private var currentItemID: String?
    private var isReady = false
    private var readyContinuation: CheckedContinuation<Void, Error>?

    /// Concatenates all `completed` events and currently-streaming `delta`
    /// events. Deltas are append-only, so the snapshot is also stable text.
    var onUpdate: ((LiveTranscriptUpdate) -> Void)?

    init(config: Configuration, session: URLSession = .shared) {
        self.config = config
        self.session = session
    }

    // MARK: Lifecycle

    func start() throws {
        guard let wsURL = Self.deriveWebSocketURL(
            baseURL: config.baseURL,
            model: config.model,
            language: config.language
        ) else {
            throw RealtimeTranscriptionError.invalidBaseURL(config.baseURL)
        }

        var request = URLRequest(url: wsURL)
        if !config.apiKey.isEmpty {
            request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        }

        let task = session.webSocketTask(with: request)
        stateQueue.sync {
            self.task = task
        }
        task.resume()

        receiveTask = Task { [weak self] in
            await self?.receiveLoop()
        }

        sendSessionUpdate()
    }

    /// Cancel the socket and any in-flight receive. Safe to call multiple times.
    func cancel() {
        let currentTask: URLSessionWebSocketTask? = stateQueue.sync {
            let currentTask = task
            task = nil
            return currentTask
        }
        stateQueue.sync {
            guard !closed else { return }
            closed = true
            if let cont = finalContinuation {
                finalContinuation = nil
                cont.resume(throwing: CancellationError())
            }
            if let ready = readyContinuation {
                readyContinuation = nil
                ready.resume(throwing: CancellationError())
            }
        }
        receiveTask?.cancel()
        currentTask?.cancel(with: .normalClosure, reason: nil)
    }

    func awaitReady() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let immediate: Result<Void, Error>? = stateQueue.sync {
                if let terminalError { return .failure(terminalError) }
                if isReady { return .success(()) }
                if closed { return .failure(RealtimeTranscriptionError.notConnected) }
                readyContinuation = continuation
                return nil
            }
            if let immediate {
                continuation.resume(with: immediate)
            }
        }
    }

    // MARK: Producer

    /// Append 16-bit little-endian PCM samples. The caller owns rate matching
    /// (the service declares 24 kHz mono in `session.update`, matching the
    /// OpenAI Realtime default).
    func appendPCM16(_ data: Data) {
        let currentTask: URLSessionWebSocketTask? = stateQueue.sync {
            task
        }
        guard let currentTask, !data.isEmpty else { return }
        let audioB64 = data.base64EncodedString()
        let message: [String: Any] = [
            "type": "input_audio_buffer.append",
            "audio": audioB64,
        ]
        send(message, over: currentTask)
    }

    /// Signal end-of-input, wait for the final transcript, return it.
    func commitAndAwaitFinal() async throws -> String {
        let currentTask: URLSessionWebSocketTask? = stateQueue.sync {
            task
        }
        guard let currentTask else {
            throw RealtimeTranscriptionError.notConnected
        }
        let alreadyCommitted: Bool = stateQueue.sync {
            if commitSent { return true }
            commitSent = true
            commitEventCount = serverEventCount
            postCommitCompleted = false
            return false
        }
        if !alreadyCommitted {
            send(["type": "input_audio_buffer.commit"], over: currentTask)
        }

        return try await withCheckedThrowingContinuation { continuation in
            var immediateResult: Result<String, Error>?
            stateQueue.sync {
                if let terminalError {
                    immediateResult = .failure(terminalError)
                    return
                }
                if closed {
                    immediateResult = .failure(RealtimeTranscriptionError.closedBeforeFinal)
                    return
                }
                if let finalText = readyCommittedTranscriptLocked() {
                    closed = true
                    immediateResult = .success(finalText)
                    return
                }
                finalContinuation = continuation
            }
            if let immediateResult {
                currentTask.cancel(with: .normalClosure, reason: nil)
                continuation.resume(with: immediateResult)
            }
        }
    }

    // MARK: Receive loop

    private func receiveLoop() async {
        while !Task.isCancelled {
            let currentTask: URLSessionWebSocketTask? = stateQueue.sync {
                task
            }
            guard let currentTask else { break }
            do {
                let message = try await currentTask.receive()
                switch message {
                case .string(let text):
                    handleServerEvent(text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        handleServerEvent(text)
                    }
                @unknown default:
                    break
                }
            } catch {
                finishWithClose(task: currentTask)
                return
            }
        }
        finishWithClose(task: nil)
    }

    private func finishWithClose(task: URLSessionWebSocketTask?) {
        stateQueue.sync {
            closed = true
            if let ready = readyContinuation {
                readyContinuation = nil
                let error = task.map {
                    RealtimeTranscriptionError.connectionFailure(for: $0, host: URL(string: config.baseURL)?.host)
                } ?? RealtimeTranscriptionError.notConnected
                ready.resume(throwing: error)
            }
            if let cont = finalContinuation {
                finalContinuation = nil
                if postCommitCompleted {
                    cont.resume(returning: finalText)
                } else {
                    cont.resume(throwing: RealtimeTranscriptionError.closedBeforeFinal)
                }
            }
        }
    }

    private func handleServerEvent(_ text: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let eventType = json["type"] as? String else {
            return
        }

        stateQueue.sync {
            serverEventCount += 1
        }

        switch eventType {
        case "session.updated":
            stateQueue.sync {
                isReady = true
                if let ready = readyContinuation {
                    readyContinuation = nil
                    ready.resume()
                }
            }
        case "conversation.item.input_audio_transcription.delta":
            if let itemID = json["item_id"] as? String {
                stateQueue.sync {
                    currentItemID = itemID
                }
            }
            if let delta = json["delta"] as? String, !delta.isEmpty {
                appendDelta(delta)
            }
            resumeIfReadyAfterCommit()
        case "conversation.item.input_audio_transcription.completed":
            stateQueue.sync {
                if let commitEventCount, serverEventCount > commitEventCount {
                    postCommitCompleted = true
                }
            }
            if let itemID = json["item_id"] as? String {
                stateQueue.sync {
                    currentItemID = itemID
                }
            }
            if let transcript = json["transcript"] as? String {
                commitSegment(transcript)
            } else {
                resumeIfReadyAfterCommit()
            }
        case "input_audio_buffer.committed":
            if let itemID = json["item_id"] as? String {
                stateQueue.sync {
                    currentItemID = itemID
                }
            }
            resumeIfReadyAfterCommit()
        case "error":
            let errObj = json["error"] as? [String: Any]
            let code = errObj?["code"] as? String ?? "unknown"
            let message = errObj?["message"] as? String ?? "unknown realtime error"
            os_log(.error, log: realtimeLog, "server error [%{public}@]: %{public}@", code, message)
            let error = RealtimeTranscriptionError.serverError(code: code, message: message)
            stateQueue.sync {
                terminalError = error
                closed = true
                if let cont = finalContinuation {
                    finalContinuation = nil
                    cont.resume(throwing: error)
                }
                if let ready = readyContinuation {
                    readyContinuation = nil
                    ready.resume(throwing: error)
                }
            }
        default:
            resumeIfReadyAfterCommit()
            break
        }
    }

    private func appendDelta(_ delta: String) {
        let snapshot: String = stateQueue.sync {
            partialText += delta
            return finalText + partialText
        }
        reportPartial(snapshot)
    }

    private func commitSegment(_ transcript: String) {
        let snapshot: String = stateQueue.sync {
            let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                if !finalText.isEmpty { finalText += " " }
                finalText += trimmed
            }
            partialText = ""
            return finalText
        }
        reportPartial(snapshot)
        resumeIfReadyAfterCommit()
    }

    private func reportPartial(_ text: String) {
        guard let handler = onUpdate else { return }
        let snapshot = LiveTranscriptText.trimmingLeadingWhitespace(text)
        let update = LiveTranscriptUpdate(stableText: snapshot, previewText: snapshot)
        DispatchQueue.main.async {
            handler(update)
        }
    }

    // MARK: Send helpers

    private func send(_ payload: [String: Any], over task: URLSessionWebSocketTask) {
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let text = String(data: data, encoding: .utf8) else {
            return
        }
        task.send(.string(text)) { error in
            if let error {
                os_log(.error, log: realtimeLog, "send failed: %{public}@", error.localizedDescription)
            }
        }
    }

    private func sendSessionUpdate() {
        let currentTask: URLSessionWebSocketTask? = stateQueue.sync {
            task
        }
        guard let currentTask else { return }
        send(Self.sessionUpdatePayload(model: config.model, language: config.language), over: currentTask)
    }

    static func sessionUpdatePayload(model: String, language: String?) -> [String: Any] {
        var transcription: [String: Any] = [:]
        let model = model.trimmingCharacters(in: .whitespacesAndNewlines)
        if !model.isEmpty {
            transcription["model"] = model
        }
        if let language, !language.isEmpty {
            // gpt-live-transcribe rejects the singular field and takes a list.
            if model.lowercased().hasPrefix("gpt-live-transcribe") {
                transcription["languages"] = [language]
            } else {
                transcription["language"] = language
            }
        }
        let session: [String: Any] = [
            "type": "transcription",
            "audio": [
                "input": [
                    "format": [
                        "type": "audio/pcm",
                        "rate": 24_000,
                    ],
                    "transcription": transcription,
                    "turn_detection": NSNull(),
                ],
            ],
        ]
        return ["type": "session.update", "session": session]
    }

    // MARK: URL derivation

    /// Turn `https://host[/prefix]` or `http://host[/prefix]` into
    /// `wss://host[/prefix]/realtime`, reusing a trailing `/v1` prefix when
    /// the configured base URL already includes it.
    static func deriveWebSocketURL(
        baseURL: String,
        model: String,
        language: String?
    ) -> URL? {
        let trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: trimmed) else { return nil }

        switch components.scheme?.lowercased() {
        case "http": components.scheme = "ws"
        case "https": components.scheme = "wss"
        case "ws", "wss": break
        default: return nil
        }

        var path = components.path
        if path.hasSuffix("/") { path.removeLast() }
        if path.hasSuffix("/v1") {
            path += "/realtime"
        } else {
            path += "/v1/realtime"
        }
        components.path = path

        var queryItems = components.queryItems ?? []
        if !queryItems.contains(where: { $0.name == "intent" }) {
            queryItems.append(URLQueryItem(name: "intent", value: "transcription"))
        }
        components.queryItems = queryItems.isEmpty ? nil : queryItems
        return components.url
    }

    private func resumeIfReadyAfterCommit() {
        var pendingResume: (CheckedContinuation<String, Error>, String)?
        stateQueue.sync {
            guard let cont = finalContinuation,
                  let finalText = readyCommittedTranscriptLocked() else {
                return
            }
            finalContinuation = nil
            closed = true
            pendingResume = (cont, finalText)
        }
        if let (cont, text) = pendingResume {
            let currentTask: URLSessionWebSocketTask? = stateQueue.sync {
                task
            }
            currentTask?.cancel(with: .normalClosure, reason: nil)
            cont.resume(returning: text)
        }
    }

    private func readyCommittedTranscriptLocked() -> String? {
        guard commitSent,
              partialText.isEmpty,
              postCommitCompleted else {
            return nil
        }
        return finalText
    }
}
