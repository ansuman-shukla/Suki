import Foundation

enum StreamingSTTSessionTests {
    static func run() {
        testXAIRequest()
        testDeepgramRequest()
        testXAIParsing()
        testDeepgramParsing()
        testXAICumulativeUtterances()
        testDeepgramPieces()
        testFactoryAndResolve()
    }

    private static func query(_ request: URLRequest) -> [String: String] {
        let items = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
        return Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
    }

    private static func testXAIRequest() {
        let dialect = StreamingSTTDialect.xAI(apiKey: "k", model: "grok-voice-transcribe-2.0", language: "fr", sampleRate: 24_000)
        TestSupport.expectEqual(dialect.request.url?.scheme, "wss")
        TestSupport.expectEqual(dialect.request.url?.host, "api.x.ai")
        TestSupport.expectEqual(dialect.request.url?.path, "/v1/stt")
        TestSupport.expectEqual(dialect.request.value(forHTTPHeaderField: "Authorization"), "Bearer k")
        TestSupport.expectEqual(query(dialect.request), [
            "model": "grok-voice-transcribe-2.0",
            "sample_rate": "24000",
            "encoding": "pcm",
            "interim_results": "true",
            "language": "fr",
        ])
        TestSupport.expect(dialect.announcesReady, "xAI waits for transcript.created")
        TestSupport.expectEqual(dialect.endOfAudioMessage, #"{"type":"audio.done"}"#)
        let auto = StreamingSTTDialect.xAI(apiKey: "k", model: "m", language: nil, sampleRate: 24_000)
        TestSupport.expect(query(auto.request)["language"] == nil, "Auto-detect sends no language to xAI")
    }

    private static func testDeepgramRequest() {
        let dialect = StreamingSTTDialect.deepgram(apiKey: "k", model: "nova-3", language: "de", sampleRate: 24_000)
        TestSupport.expectEqual(dialect.request.url?.host, "api.deepgram.com")
        TestSupport.expectEqual(dialect.request.url?.path, "/v1/listen")
        TestSupport.expectEqual(dialect.request.value(forHTTPHeaderField: "Authorization"), "Token k")
        TestSupport.expectEqual(query(dialect.request), [
            "model": "nova-3",
            "encoding": "linear16",
            "sample_rate": "24000",
            "channels": "1",
            "interim_results": "true",
            "smart_format": "true",
            "language": "de",
        ])
        TestSupport.expect(!dialect.announcesReady, "Deepgram is ready once the socket opens")
        TestSupport.expectEqual(dialect.endOfAudioMessage, #"{"type":"CloseStream"}"#)
        let auto = StreamingSTTDialect.deepgram(apiKey: "k", model: "nova-3", language: "", sampleRate: 24_000)
        TestSupport.expectEqual(query(auto.request)["language"], "multi")
    }

    private static let xAI = StreamingSTTDialect.xAI(apiKey: "k", model: "m", language: nil, sampleRate: 24_000)
    private static let deepgram = StreamingSTTDialect.deepgram(apiKey: "k", model: "m", language: nil, sampleRate: 24_000)

    private static func json(_ text: String) -> [String: Any] {
        try! JSONSerialization.jsonObject(with: Data(text.utf8)) as! [String: Any]
    }

    private static func testXAIParsing() {
        TestSupport.expectEqual(xAI.parse(json(#"{"type":"transcript.created"}"#)), .ready)
        TestSupport.expectEqual(
            xAI.parse(json(#"{"type":"transcript.partial","text":"Synthetic","is_final":true,"speech_final":false}"#)),
            .transcript(text: "Synthetic", isFinal: true, endsUtterance: false)
        )
        TestSupport.expectEqual(xAI.parse(json(#"{"type":"transcript.done","text":""}"#)), .done)
        TestSupport.expectEqual(xAI.parse(json(#"{"type":"error","message":"Invalid message"}"#)), .error("Invalid message"))
        TestSupport.expectEqual(xAI.parse(json(#"{"type":"Results"}"#)), .other)
    }

    private static func testDeepgramParsing() {
        let result = #"{"type":"Results","is_final":true,"speech_final":true,"channel":{"alternatives":[{"transcript":"Synthetic piece."}]}}"#
        TestSupport.expectEqual(deepgram.parse(json(result)), .transcript(text: "Synthetic piece.", isFinal: true, endsUtterance: true))
        TestSupport.expectEqual(deepgram.parse(json(#"{"type":"Metadata","request_id":"x"}"#)), .done)
        TestSupport.expectEqual(deepgram.parse(json(#"{"type":"Error","description":"Bad audio"}"#)), .error("Bad audio"))
        TestSupport.expectEqual(deepgram.parse(json(#"{"type":"transcript.created"}"#)), .other)
    }

    /// Mirrors a live xAI session: partials repeat the whole utterance, and
    /// the next utterance starts from an empty partial.
    private static func testXAICumulativeUtterances() {
        var state = StreamingTranscriptState(kind: .xAI)
        TestSupport.expect(state.apply(text: "Alpha", isFinal: false, endsUtterance: false), "Partial changes the preview")
        _ = state.apply(text: "Alpha beta.", isFinal: false, endsUtterance: false)
        TestSupport.expectEqual(state.update, LiveTranscriptUpdate(stableText: "", previewText: "Alpha beta."))
        _ = state.apply(text: "Alpha beta gamma.", isFinal: true, endsUtterance: false)
        TestSupport.expectEqual(state.update, LiveTranscriptUpdate(stableText: "", previewText: "Alpha beta gamma."))
        _ = state.apply(text: "Alpha beta gamma.", isFinal: true, endsUtterance: true)
        TestSupport.expectEqual(state.update, LiveTranscriptUpdate(stableText: "Alpha beta gamma.", previewText: "Alpha beta gamma."))
        _ = state.apply(text: "", isFinal: false, endsUtterance: false)
        _ = state.apply(text: "Delta", isFinal: false, endsUtterance: false)
        TestSupport.expectEqual(state.update, LiveTranscriptUpdate(stableText: "Alpha beta gamma.", previewText: "Alpha beta gamma. Delta"))
        _ = state.apply(text: "Delta epsilon.", isFinal: true, endsUtterance: true)
        TestSupport.expectEqual(state.transcript, "Alpha beta gamma. Delta epsilon.")
        TestSupport.expect(!state.apply(text: "", isFinal: false, endsUtterance: false), "Empty partial after an utterance changes nothing")
        _ = state.apply(text: "Zeta", isFinal: false, endsUtterance: false)
        TestSupport.expectEqual(state.transcript, "Alpha beta gamma. Delta epsilon. Zeta")
    }

    /// Mirrors a live Deepgram session: each final result is a new piece.
    private static func testDeepgramPieces() {
        var state = StreamingTranscriptState(kind: .deepgram)
        _ = state.apply(text: "Alpha", isFinal: false, endsUtterance: false)
        _ = state.apply(text: "Alpha beta.", isFinal: true, endsUtterance: true)
        _ = state.apply(text: "Gamma", isFinal: false, endsUtterance: false)
        TestSupport.expectEqual(state.update, LiveTranscriptUpdate(stableText: "Alpha beta.", previewText: "Alpha beta. Gamma"))
        _ = state.apply(text: "Gamma delta.", isFinal: true, endsUtterance: false)
        TestSupport.expect(!state.apply(text: "", isFinal: true, endsUtterance: true), "Empty final after CloseStream changes nothing")
        TestSupport.expectEqual(state.update, LiveTranscriptUpdate(stableText: "Alpha beta. Gamma delta.", previewText: "Alpha beta. Gamma delta."))
    }

    private static func testFactoryAndResolve() {
        for provider in [LiveTranscriptionProvider.xAI, .deepgram] {
            guard let configuration = LiveTranscriptionConfiguration.resolve(
                provider: provider,
                providerAPIKey: " k ",
                transcriptionBaseURL: "",
                transcriptionAPIKey: "",
                model: "",
                language: nil
            ) else {
                return TestSupport.expect(false, "\(provider) resolves with a key")
            }
            TestSupport.expectEqual(configuration.apiKey, "k")
            TestSupport.expectEqual(configuration.model, provider.defaultModel)
            TestSupport.expect(LiveTranscriptionSessionFactory.make(configuration) is StreamingSTTSession, "\(provider) streams raw PCM")
            TestSupport.expect(
                LiveTranscriptionConfiguration.resolve(
                    provider: provider,
                    providerAPIKey: " ",
                    transcriptionBaseURL: "https://custom.invalid/v1",
                    transcriptionAPIKey: "custom",
                    model: "",
                    language: nil
                ) == nil,
                "\(provider) needs its own key"
            )
        }
    }
}
