import Foundation
import os.log

private let streamingSTTLog = OSLog(subsystem: "com.ansumanshukla.suki", category: "StreamingTranscription")

/// One server message from a raw-PCM streaming speech-to-text socket.
enum StreamingSTTEvent: Equatable {
    case ready
    case transcript(text: String, isFinal: Bool, endsUtterance: Bool)
    /// The server flushed everything after the end-of-audio message.
    case done
    case error(String)
    case other
}

/// The wire format of xAI's and Deepgram's streaming endpoints: query
/// parameters for setup, binary PCM16 frames in, JSON transcript events out.
struct StreamingSTTDialect {
    enum Kind {
        /// Partials repeat the whole current utterance; a new one starts
        /// empty after `speech_final`.
        case xAI
        /// Each final result is a new piece of the transcript.
        case deepgram
    }

    let kind: Kind
    let request: URLRequest
    let sampleRate: Int

    var host: String? { request.url?.host }

    /// xAI announces readiness; Deepgram is ready once the socket opens.
    var announcesReady: Bool { kind == .xAI }

    var endOfAudioMessage: String {
        switch kind {
        case .xAI: return #"{"type":"audio.done"}"#
        case .deepgram: return #"{"type":"CloseStream"}"#
        }
    }

    static func xAI(apiKey: String, model: String, language: String?, sampleRate: Int) -> StreamingSTTDialect {
        var query = [
            URLQueryItem(name: "model", value: model),
            URLQueryItem(name: "sample_rate", value: String(sampleRate)),
            URLQueryItem(name: "encoding", value: "pcm"),
            URLQueryItem(name: "interim_results", value: "true"),
        ]
        if let language, !language.isEmpty {
            query.append(URLQueryItem(name: "language", value: language))
        }
        return StreamingSTTDialect(
            kind: .xAI,
            request: request(host: "api.x.ai", path: "/v1/stt", query: query, authorization: "Bearer \(apiKey)"),
            sampleRate: sampleRate
        )
    }

    static func deepgram(apiKey: String, model: String, language: String?, sampleRate: Int) -> StreamingSTTDialect {
        let query = [
            URLQueryItem(name: "model", value: model),
            URLQueryItem(name: "encoding", value: "linear16"),
            URLQueryItem(name: "sample_rate", value: String(sampleRate)),
            URLQueryItem(name: "channels", value: "1"),
            URLQueryItem(name: "interim_results", value: "true"),
            URLQueryItem(name: "smart_format", value: "true"),
            // nova-3 detects and switches between languages with "multi".
            URLQueryItem(name: "language", value: (language?.isEmpty ?? true) ? "multi" : language),
        ]
        return StreamingSTTDialect(
            kind: .deepgram,
            request: request(host: "api.deepgram.com", path: "/v1/listen", query: query, authorization: "Token \(apiKey)"),
            sampleRate: sampleRate
        )
    }

    private static func request(host: String, path: String, query: [URLQueryItem], authorization: String) -> URLRequest {
        var components = URLComponents()
        components.scheme = "wss"
        components.host = host
        components.path = path
        components.queryItems = query
        var request = URLRequest(url: components.url!)
        request.setValue(authorization, forHTTPHeaderField: "Authorization")
        return request
    }

    func parse(_ message: [String: Any]) -> StreamingSTTEvent {
        let type = message["type"] as? String
        switch (kind, type) {
        case (.xAI, "transcript.created"):
            return .ready
        case (.xAI, "transcript.partial"):
            return .transcript(
                text: message["text"] as? String ?? "",
                isFinal: message["is_final"] as? Bool ?? false,
                endsUtterance: message["speech_final"] as? Bool ?? false
            )
        // xAI's done event repeats nothing useful: its text was empty in testing.
        case (.xAI, "transcript.done"), (.deepgram, "Metadata"):
            return .done
        case (.xAI, "error"):
            return .error(message["message"] as? String ?? "Unknown error")
        case (.deepgram, "Results"):
            let alternatives = (message["channel"] as? [String: Any])?["alternatives"] as? [[String: Any]]
            return .transcript(
                text: alternatives?.first?["transcript"] as? String ?? "",
                isFinal: message["is_final"] as? Bool ?? false,
                endsUtterance: message["speech_final"] as? Bool ?? false
            )
        case (.deepgram, "Error"):
            return .error(message["description"] as? String ?? message["message"] as? String ?? "Unknown error")
        default:
            return .other
        }
    }
}

/// Transcript bookkeeping, kept free of socket I/O so it can be tested.
struct StreamingTranscriptState {
    let kind: StreamingSTTDialect.Kind
    /// Finished utterances (xAI) or final pieces (Deepgram). Never revised,
    /// so it is the only text safe to type live.
    private(set) var committedText = ""
    /// xAI: the current utterance's locked text before it ends.
    private(set) var lockedUtteranceText = ""
    private(set) var interimText = ""

    init(kind: StreamingSTTDialect.Kind) {
        self.kind = kind
    }

    var update: LiveTranscriptUpdate {
        LiveTranscriptUpdate(stableText: committedText, previewText: transcript)
    }

    /// Everything heard so far, including words the server may still revise.
    var transcript: String {
        LiveTranscriptText.join(committedText, interimText.isEmpty ? lockedUtteranceText : interimText)
    }

    /// Returns true when the transcript changed.
    mutating func apply(text: String, isFinal: Bool, endsUtterance: Bool) -> Bool {
        let before = (committedText, lockedUtteranceText, interimText)
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        switch (kind, isFinal) {
        case (.xAI, true) where endsUtterance:
            committedText = LiveTranscriptText.join(committedText, text)
            lockedUtteranceText = ""
            interimText = ""
        case (.xAI, true):
            lockedUtteranceText = text
            interimText = ""
        case (.deepgram, true):
            committedText = LiveTranscriptText.join(committedText, text)
            interimText = ""
        case (_, false):
            interimText = text
        }
        return before != (committedText, lockedUtteranceText, interimText)
    }
}

final class StreamingSTTSession: LiveTranscriptionSession {
    static let inputSampleRate = 24_000
    /// How long the server may stay silent after the end of audio before
    /// the transcript received so far is treated as final.
    private static let quietPeriodAfterCommit: TimeInterval = 1.2
    private static let maxWaitAfterCommit: TimeInterval = 8

    private let dialect: StreamingSTTDialect
    private let session: URLSession
    private let stateQueue = DispatchQueue(label: "com.ansumanshukla.suki.streaming-stt.state")
    private var task: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?
    private var watchdogTask: Task<Void, Never>?
    private var state: StreamingTranscriptState
    private var isReady = false
    private var isCommitted = false
    private var pendingAudio: [Data] = []
    private var closed = false
    private var terminalError: Error?
    private var lastServerMessageAt = Date()
    private var commitAt: Date?
    private var readyContinuation: CheckedContinuation<Void, Error>?
    private var finalContinuation: CheckedContinuation<String, Error>?

    var onUpdate: ((LiveTranscriptUpdate) -> Void)?

    init(dialect: StreamingSTTDialect, session: URLSession = .shared) {
        self.dialect = dialect
        self.session = session
        self.state = StreamingTranscriptState(kind: dialect.kind)
    }

    func start() throws {
        let task = session.webSocketTask(with: dialect.request)
        stateQueue.sync { self.task = task }
        task.resume()
        receiveTask = Task { [weak self] in
            await self?.receiveLoop(task: task)
        }
        guard !dialect.announcesReady else { return }
        // A pong proves the handshake succeeded.
        task.sendPing { [weak self] error in
            guard error == nil else { return }
            self?.markReady(task: task)
        }
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
            if let immediate { continuation.resume(with: immediate) }
        }
    }

    /// Audio captured before the server is ready is buffered and sent in
    /// order once it is.
    func appendPCM16(_ data: Data) {
        guard !data.isEmpty else { return }
        stateQueue.sync {
            guard !closed, !isCommitted, let task else { return }
            guard isReady else {
                pendingAudio.append(data)
                return
            }
            send(.data(data), over: task)
        }
    }

    func commitAndAwaitFinal() async throws -> String {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
            let immediate: Result<String, Error>? = stateQueue.sync {
                if let terminalError { return .failure(terminalError) }
                guard !closed, let task else { return .failure(RealtimeTranscriptionError.notConnected) }
                guard isReady else { return .failure(RealtimeTranscriptionError.closedBeforeFinal) }
                isCommitted = true
                commitAt = Date()
                lastServerMessageAt = Date()
                finalContinuation = continuation
                send(.string(dialect.endOfAudioMessage), over: task)
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
        let event = dialect.parse(json)
        switch event {
        case .ready:
            markReady(task: task)
        case .transcript(let text, let isFinal, let endsUtterance):
            let update: LiveTranscriptUpdate? = stateQueue.sync {
                lastServerMessageAt = Date()
                return state.apply(text: text, isFinal: isFinal, endsUtterance: endsUtterance) ? state.update : nil
            }
            if let update, let handler = onUpdate {
                DispatchQueue.main.async { handler(update) }
            }
        case .done:
            if stateQueue.sync(execute: { isCommitted }) { finishWithTranscript() }
        case .error(let message):
            os_log(.error, log: streamingSTTLog, "server error event from %{public}@", dialect.host ?? "provider")
            let error = RealtimeTranscriptionError.connectionFailed("\(dialect.host ?? "Live transcription"): \(message)")
            let committed: Bool = stateQueue.sync {
                if terminalError == nil, !isCommitted { terminalError = error }
                return isCommitted
            }
            committed ? finishWithTranscript() : finish(with: .failure(error))
        case .other:
            stateQueue.sync { lastServerMessageAt = Date() }
        }
    }

    private func markReady(task: URLSessionWebSocketTask) {
        let ready: CheckedContinuation<Void, Error>? = stateQueue.sync {
            guard !isReady, !closed else { return nil }
            isReady = true
            for chunk in pendingAudio {
                send(.data(chunk), over: task)
            }
            pendingAudio = []
            defer { readyContinuation = nil }
            return readyContinuation
        }
        ready?.resume()
    }

    private func handleClose(task: URLSessionWebSocketTask) {
        let error = RealtimeTranscriptionError.connectionFailure(for: task, host: dialect.host)
        let committed: Bool = stateQueue.sync {
            if terminalError == nil, !isCommitted { terminalError = error }
            return isCommitted
        }
        if committed {
            finishWithTranscript()
        } else {
            os_log(.error, log: streamingSTTLog, "socket to %{public}@ closed before commit", dialect.host ?? "provider")
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
        let transcript = stateQueue.sync { state.transcript }
        finish(with: transcript.isEmpty ? .failure(RealtimeTranscriptionError.closedBeforeFinal) : .success(transcript))
    }

    private func finish(with result: Result<String, Error>) {
        let (final, ready, socket): (CheckedContinuation<String, Error>?, CheckedContinuation<Void, Error>?, URLSessionWebSocketTask?) = stateQueue.sync {
            let pending = (finalContinuation, readyContinuation, task)
            finalContinuation = nil
            readyContinuation = nil
            if case .failure = result { closed = true }
            if pending.0 != nil { closed = true }
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

    private func send(_ message: URLSessionWebSocketTask.Message, over task: URLSessionWebSocketTask) {
        task.send(message) { error in
            if let error {
                os_log(.error, log: streamingSTTLog, "send failed: %{public}@", error.localizedDescription)
            }
        }
    }
}
