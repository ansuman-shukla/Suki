import Foundation

struct LiveTranscriptUpdate: Equatable {
    /// Text the provider does not retract later, so it is safe to type into
    /// another app while the user is still speaking.
    let stableText: String
    /// Stable text plus any speculative tail, for on-screen preview only.
    let previewText: String
}

/// A WebSocket transcription session fed with 24 kHz mono PCM16 audio while
/// the user records.
protocol LiveTranscriptionSession: AnyObject {
    /// Delivered on the main queue.
    var onUpdate: ((LiveTranscriptUpdate) -> Void)? { get set }
    func start() throws
    /// Resolves once the provider accepted the session configuration.
    func awaitReady() async throws
    func appendPCM16(_ data: Data)
    /// Signals end of input and returns the complete transcript.
    func commitAndAwaitFinal() async throws -> String
    /// Safe to call multiple times.
    func cancel()
}

enum LiveTranscriptionSessionFactory {
    static func make(_ configuration: LiveTranscriptionConfiguration) -> LiveTranscriptionSession {
        switch configuration.provider {
        case .gemini:
            return GeminiLiveTranscriptionService(
                apiKey: configuration.apiKey,
                model: configuration.model,
                language: configuration.language
            )
        case .xAI:
            return StreamingSTTSession(dialect: .xAI(
                apiKey: configuration.apiKey,
                model: configuration.model,
                language: configuration.language,
                sampleRate: StreamingSTTSession.inputSampleRate
            ))
        case .deepgram:
            return StreamingSTTSession(dialect: .deepgram(
                apiKey: configuration.apiKey,
                model: configuration.model,
                language: configuration.language,
                sampleRate: StreamingSTTSession.inputSampleRate
            ))
        case .openAI, .custom:
            return RealtimeTranscriptionService(config: .init(
                baseURL: configuration.baseURL,
                apiKey: configuration.apiKey,
                model: configuration.model,
                language: configuration.language
            ))
        }
    }
}

enum LiveTranscriptionConnectionTest {
    /// Some models accept the session configuration and only reject it once
    /// audio arrives, so the check sends this much silence before deciding.
    private static let probeSilence = Data(count: 24_000 * 2 / 5)
    private static let probeWaitNanoseconds: UInt64 = 1_500_000_000

    /// Opens a session, waits for the provider to accept its configuration,
    /// then sends 0.2 s of silence and confirms the session stays open.
    static func run(_ configuration: LiveTranscriptionConfiguration, timeout: TimeInterval = 10) async -> Result<Void, Error> {
        let session = LiveTranscriptionSessionFactory.make(configuration)
        defer { session.cancel() }
        do {
            try session.start()
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask { try await session.awaitReady() }
                group.addTask {
                    try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                    throw RealtimeTranscriptionError.connectionFailed("Timed out waiting for \(configuration.provider.displayName) to respond.")
                }
                defer { group.cancelAll() }
                try await group.next()
            }
            session.appendPCM16(probeSilence)
            try await Task.sleep(nanoseconds: probeWaitNanoseconds)
            try await session.awaitReady()
            return .success(())
        } catch {
            return .failure(error)
        }
    }
}

enum LiveTranscriptText {
    /// Providers prefix the first word with a space; previews and typed text
    /// should not start with one.
    static func trimmingLeadingWhitespace(_ text: String) -> String {
        String(text.drop(while: { $0.isWhitespace }))
    }

    /// Appends a transcript segment, adding a space only when neither side has one.
    static func join(_ head: String, _ tail: String) -> String {
        let tail = tail.trimmingCharacters(in: .newlines)
        guard !tail.trimmingCharacters(in: .whitespaces).isEmpty else { return head }
        guard !head.isEmpty else { return trimmingLeadingWhitespace(tail) }
        if head.last?.isWhitespace == true || tail.first?.isWhitespace == true {
            return head + tail
        }
        return head + " " + tail
    }
}
