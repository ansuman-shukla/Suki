import Foundation
import os.log

private let geminiLiveLog = OSLog(subsystem: "com.ansumanshukla.suki", category: "GeminiLiveTranscription")

/// Transcript bookkeeping for a Gemini Live transcription session, kept free
/// of socket I/O so the protocol handling can be tested deterministically.
struct GeminiLiveTranscriptState {
    enum Event: Equatable {
        case setupComplete
        case transcriptChanged
        case turnComplete
        case goAway
        case other
    }

    private(set) var finalText = ""
    private(set) var interimText = ""
    private(set) var isSetupComplete = false
    private(set) var isCommitted = false
    private var receivedFinalSinceCommit = false
    private var receivedTurnCompleteSinceCommit = false

    var update: LiveTranscriptUpdate {
        LiveTranscriptUpdate(stableText: finalText, previewText: LiveTranscriptText.join(finalText, interimText))
    }

    /// The final transcript once the server has finalized everything spoken
    /// before the end of the audio stream.
    var isFinalReady: Bool {
        isCommitted && (receivedTurnCompleteSinceCommit || (receivedFinalSinceCommit && interimText.isEmpty))
    }

    /// Finalized text plus any unfinalized interim tail, used when the server
    /// goes quiet without finalizing the last words.
    var bestEffortTranscript: String {
        LiveTranscriptText.join(finalText, interimText)
    }

    mutating func markCommitted() {
        isCommitted = true
        receivedFinalSinceCommit = false
        receivedTurnCompleteSinceCommit = false
    }

    mutating func apply(_ message: [String: Any]) -> Event {
        if message["setupComplete"] != nil {
            isSetupComplete = true
            return .setupComplete
        }
        if message["goAway"] != nil {
            return .goAway
        }
        guard let content = message["serverContent"] as? [String: Any] else {
            return .other
        }

        var transcriptChanged = false
        if let final = (content["inputTranscription"] as? [String: Any])?["text"] as? String {
            finalText = LiveTranscriptText.join(finalText, final)
            interimText = ""
            receivedFinalSinceCommit = isCommitted
            transcriptChanged = true
        }
        if let interim = (content["interimInputTranscription"] as? [String: Any])?["text"] as? String {
            interimText = LiveTranscriptText.trimmingLeadingWhitespace(interim)
            transcriptChanged = true
        }
        if content["turnComplete"] as? Bool == true {
            receivedTurnCompleteSinceCommit = isCommitted
            return .turnComplete
        }
        return transcriptChanged ? .transcriptChanged : .other
    }

    // MARK: Client messages

    static func setupMessage(model: String, language: String?) -> [String: Any] {
        var transcription: [String: Any] = [:]
        if let language, !language.isEmpty {
            transcription["languageCodes"] = [language]
        }
        return [
            "setup": [
                "model": "models/\(model)",
                "generationConfig": ["responseModalities": ["TEXT"]],
                "inputAudioTranscription": transcription,
            ],
        ]
    }

    static func audioMessage(_ pcm16: Data, sampleRate: Int) -> [String: Any] {
        [
            "realtimeInput": [
                "audio": [
                    "data": pcm16.base64EncodedString(),
                    "mimeType": "audio/pcm;rate=\(sampleRate)",
                ],
            ],
        ]
    }

    static let audioStreamEndMessage: [String: Any] = ["realtimeInput": ["audioStreamEnd": true]]

    /// Assistant models such as gemini-3.8-live only answer in audio and close
    /// the socket at setup with an internal model name in the reason.
    static func unsupportedModelMessage(closeReason: String, model: String) -> String? {
        guard closeReason.localizedCaseInsensitiveContains("response modalities") else { return nil }
        return "\(model) can't do live transcription. Use \(LiveTranscriptionProvider.gemini.defaultModel)."
    }
}

final class GeminiLiveTranscriptionService: LiveTranscriptionSession {
    static let webSocketURL = URL(
        string: "wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContent"
    )!
    private static let inputSampleRate = 24_000
    /// How long the server may stay silent after the end of the audio stream
    /// before the transcript received so far is treated as final.
    private static let quietPeriodAfterCommit: TimeInterval = 1.2
    private static let maxWaitAfterCommit: TimeInterval = 8

    private let apiKey: String
    private let model: String
    private let language: String?
    private let session: URLSession

    private let stateQueue = DispatchQueue(label: "com.ansumanshukla.suki.gemini-live.state")
    private var task: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?
    private var watchdogTask: Task<Void, Never>?
    private var state = GeminiLiveTranscriptState()
    private var pendingAudio: [Data] = []
    private var closed = false
    private var terminalError: Error?
    private var lastServerMessageAt = Date()
    private var commitAt: Date?
    private var readyContinuation: CheckedContinuation<Void, Error>?
    private var finalContinuation: CheckedContinuation<String, Error>?

    var onUpdate: ((LiveTranscriptUpdate) -> Void)?

    init(apiKey: String, model: String, language: String?, session: URLSession = .shared) {
        self.apiKey = apiKey
        self.model = model
        self.language = language
        self.session = session
    }

    func start() throws {
        var request = URLRequest(url: Self.webSocketURL)
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        let task = session.webSocketTask(with: request)
        stateQueue.sync { self.task = task }
        task.resume()
        receiveTask = Task { [weak self] in
            await self?.receiveLoop(task: task)
        }
        send(GeminiLiveTranscriptState.setupMessage(model: model, language: language), over: task)
    }

    func awaitReady() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let immediate: Result<Void, Error>? = stateQueue.sync {
                if let terminalError { return .failure(terminalError) }
                if state.isSetupComplete { return .success(()) }
                if closed { return .failure(RealtimeTranscriptionError.notConnected) }
                readyContinuation = continuation
                return nil
            }
            if let immediate { continuation.resume(with: immediate) }
        }
    }

    /// Audio captured before the server confirms setup is buffered, because
    /// the Live API rejects input sent ahead of `setupComplete`. Sends happen
    /// under the state lock so buffered and live chunks keep their order.
    func appendPCM16(_ data: Data) {
        guard !data.isEmpty else { return }
        stateQueue.sync {
            guard !closed, !state.isCommitted, let task else { return }
            guard state.isSetupComplete else {
                pendingAudio.append(data)
                return
            }
            send(GeminiLiveTranscriptState.audioMessage(data, sampleRate: Self.inputSampleRate), over: task)
        }
    }

    func commitAndAwaitFinal() async throws -> String {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
            let immediate: Result<String, Error>? = stateQueue.sync {
                if let terminalError { return .failure(terminalError) }
                guard !closed, let task else { return .failure(RealtimeTranscriptionError.notConnected) }
                guard state.isSetupComplete else { return .failure(RealtimeTranscriptionError.closedBeforeFinal) }
                state.markCommitted()
                commitAt = Date()
                lastServerMessageAt = Date()
                finalContinuation = continuation
                send(GeminiLiveTranscriptState.audioStreamEndMessage, over: task)
                return nil
            }
            if let immediate {
                continuation.resume(with: immediate)
            } else {
                startWatchdog()
            }
        }
    }

    func cancel() {
        let currentTask: URLSessionWebSocketTask? = stateQueue.sync {
            defer { task = nil }
            return task
        }
        finish(with: .failure(CancellationError()))
        receiveTask?.cancel()
        watchdogTask?.cancel()
        currentTask?.cancel(with: .normalClosure, reason: nil)
    }

    // MARK: Receive

    private func receiveLoop(task: URLSessionWebSocketTask) async {
        while !Task.isCancelled {
            do {
                let message = try await task.receive()
                let text: String?
                switch message {
                case .string(let string): text = string
                case .data(let data): text = String(data: data, encoding: .utf8)
                @unknown default: text = nil
                }
                if let text { handleServerMessage(text, task: task) }
            } catch {
                handleClose(task: task)
                return
            }
        }
    }

    private func handleServerMessage(_ text: String, task: URLSessionWebSocketTask) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }
        var ready: CheckedContinuation<Void, Error>?
        let (event, update, finalReady): (GeminiLiveTranscriptState.Event, LiveTranscriptUpdate, Bool) = stateQueue.sync {
            lastServerMessageAt = Date()
            let event = state.apply(json)
            if event == .setupComplete {
                for chunk in pendingAudio {
                    send(GeminiLiveTranscriptState.audioMessage(chunk, sampleRate: Self.inputSampleRate), over: task)
                }
                pendingAudio = []
                ready = readyContinuation
                readyContinuation = nil
            }
            return (event, state.update, state.isFinalReady)
        }
        ready?.resume()
        if event == .transcriptChanged, let handler = onUpdate {
            DispatchQueue.main.async { handler(update) }
        }
        if event == .goAway {
            os_log(.info, log: geminiLiveLog, "server announced disconnect")
        }
        if finalReady {
            finishWithTranscript()
        }
    }

    private func handleClose(task: URLSessionWebSocketTask) {
        let closeReason = task.closeReason.flatMap { String(data: $0, encoding: .utf8) } ?? ""
        let error = GeminiLiveTranscriptState.unsupportedModelMessage(closeReason: closeReason, model: model)
            .map { RealtimeTranscriptionError.connectionFailed($0) }
            ?? RealtimeTranscriptionError.connectionFailure(for: task, host: Self.webSocketURL.host)
        let committed: Bool = stateQueue.sync {
            // Keep the reason so a later commit or readiness check reports it.
            if terminalError == nil, !state.isCommitted { terminalError = error }
            return state.isCommitted
        }
        if committed {
            finishWithTranscript()
        } else {
            if let message = error.errorDescription {
                os_log(.error, log: geminiLiveLog, "socket closed: %{public}@", message)
            }
            finish(with: .failure(error))
        }
    }

    // MARK: Completion

    private func startWatchdog() {
        watchdogTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 100_000_000)
                guard let self else { return }
                let timedOut: Bool = self.stateQueue.sync {
                    let now = Date()
                    let quiet = now.timeIntervalSince(self.lastServerMessageAt) >= Self.quietPeriodAfterCommit
                    let expired = self.commitAt.map { now.timeIntervalSince($0) >= Self.maxWaitAfterCommit } ?? false
                    return quiet || expired
                }
                if timedOut {
                    self.finishWithTranscript()
                    return
                }
            }
        }
    }

    /// Resolves with the best transcript available. An empty result is
    /// reported as an error so the caller can fall back to file upload.
    private func finishWithTranscript() {
        let transcript = stateQueue.sync { state.bestEffortTranscript }
        finish(with: transcript.isEmpty
            ? .failure(RealtimeTranscriptionError.closedBeforeFinal)
            : .success(transcript))
    }

    private func finish(with result: Result<String, Error>) {
        let (final, ready, socket): (CheckedContinuation<String, Error>?, CheckedContinuation<Void, Error>?, URLSessionWebSocketTask?) = stateQueue.sync {
            let pending = (finalContinuation, readyContinuation, task)
            finalContinuation = nil
            readyContinuation = nil
            if pending.0 != nil || result.isFailure { closed = true }
            return pending
        }
        if case .failure(let error) = result {
            ready?.resume(throwing: error)
        }
        guard let final else { return }
        watchdogTask?.cancel()
        socket?.cancel(with: .normalClosure, reason: nil)
        final.resume(with: result)
    }

    private func send(_ payload: [String: Any], over task: URLSessionWebSocketTask) {
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let text = String(data: data, encoding: .utf8) else {
            return
        }
        task.send(.string(text)) { error in
            if let error {
                os_log(.error, log: geminiLiveLog, "send failed: %{public}@", error.localizedDescription)
            }
        }
    }
}

private extension Result {
    var isFailure: Bool {
        if case .failure = self { return true }
        return false
    }
}
