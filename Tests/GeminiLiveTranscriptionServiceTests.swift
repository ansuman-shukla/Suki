import Foundation

enum GeminiLiveTranscriptionServiceTests {
    static func run() {
        testSetupAndTranscriptAccumulation()
        testFinalReadinessAfterCommit()
        testTurnCompleteFinalizes()
        testFinalsBeforeCommitDoNotFinalize()
        testBestEffortIncludesInterimTail()
        testJoin()
        testClientMessages()
        testFactoryRoutesProviders()
        testUnsupportedModelMessage()
    }

    private static func testUnsupportedModelMessage() {
        let reason = "The requested combination of response modalities (TEXT) is not supported by the model. models/internal_rev"
        TestSupport.expectEqual(
            GeminiLiveTranscriptState.unsupportedModelMessage(closeReason: reason, model: "gemini-3.8-live"),
            "gemini-3.8-live can't do live transcription. Use gemini-3.5-transcribe-live."
        )
        TestSupport.expect(
            GeminiLiveTranscriptState.unsupportedModelMessage(closeReason: "API key not valid.", model: "m") == nil,
            "Other close reasons keep the provider's message"
        )
    }

    private static func content(_ fields: [String: Any]) -> [String: Any] {
        ["serverContent": fields]
    }

    private static func final(_ text: String) -> [String: Any] {
        content(["inputTranscription": ["text": text]])
    }

    private static func interim(_ text: String) -> [String: Any] {
        content(["interimInputTranscription": ["text": text]])
    }

    private static func testSetupAndTranscriptAccumulation() {
        var state = GeminiLiveTranscriptState()
        TestSupport.expect(!state.isSetupComplete, "Setup starts incomplete")
        TestSupport.expectEqual(state.apply(["setupComplete": [:]]), .setupComplete)
        TestSupport.expect(state.isSetupComplete, "setupComplete marks the session ready")

        TestSupport.expectEqual(state.apply(interim(" Hello wor")), .transcriptChanged)
        TestSupport.expectEqual(state.update, LiveTranscriptUpdate(stableText: "", previewText: "Hello wor"))

        _ = state.apply(interim("Hello world"))
        TestSupport.expectEqual(state.update.previewText, "Hello world")

        _ = state.apply(final("Hello world."))
        TestSupport.expectEqual(state.update, LiveTranscriptUpdate(stableText: "Hello world.", previewText: "Hello world."))

        _ = state.apply(interim("Second"))
        TestSupport.expectEqual(state.update, LiveTranscriptUpdate(stableText: "Hello world.", previewText: "Hello world. Second"))

        TestSupport.expectEqual(state.apply(["usageMetadata": [:]]), .other)
        TestSupport.expectEqual(state.apply(["goAway": ["timeLeft": "1s"]]), .goAway)
    }

    private static func testFinalReadinessAfterCommit() {
        var state = GeminiLiveTranscriptState()
        _ = state.apply(["setupComplete": [:]])
        _ = state.apply(interim("still talking"))
        state.markCommitted()
        TestSupport.expect(!state.isFinalReady, "Pending interim text is not final yet")
        _ = state.apply(final("still talking"))
        TestSupport.expect(state.isFinalReady, "Final after commit with no interim tail is ready")
        _ = state.apply(interim("late hypothesis"))
        TestSupport.expect(!state.isFinalReady, "A new interim tail reopens the wait")
    }

    private static func testTurnCompleteFinalizes() {
        var state = GeminiLiveTranscriptState()
        _ = state.apply(["setupComplete": [:]])
        _ = state.apply(final("done"))
        _ = state.apply(content(["turnComplete": true]))
        TestSupport.expect(!state.isFinalReady, "turnComplete before commit does not end the session")
        state.markCommitted()
        TestSupport.expectEqual(state.apply(content(["turnComplete": true])), .turnComplete)
        TestSupport.expect(state.isFinalReady, "turnComplete after commit ends the session")
    }

    private static func testFinalsBeforeCommitDoNotFinalize() {
        var state = GeminiLiveTranscriptState()
        _ = state.apply(["setupComplete": [:]])
        _ = state.apply(final("earlier segment"))
        state.markCommitted()
        TestSupport.expect(!state.isFinalReady, "Finals received before commit do not count as the closing final")
    }

    private static func testBestEffortIncludesInterimTail() {
        var state = GeminiLiveTranscriptState()
        _ = state.apply(final("Finished part."))
        _ = state.apply(interim("unfinished tail"))
        TestSupport.expectEqual(state.bestEffortTranscript, "Finished part. unfinished tail")
    }

    private static func testJoin() {
        TestSupport.expectEqual(GeminiLiveTranscriptState.join("", "  First"), "First")
        TestSupport.expectEqual(GeminiLiveTranscriptState.join("One.", "Two"), "One. Two")
        TestSupport.expectEqual(GeminiLiveTranscriptState.join("One.", " Two"), "One. Two")
        TestSupport.expectEqual(GeminiLiveTranscriptState.join("One. ", "Two"), "One. Two")
        TestSupport.expectEqual(GeminiLiveTranscriptState.join("One.", "  \n"), "One.")
    }

    private static func testClientMessages() {
        let setup = GeminiLiveTranscriptState.setupMessage(model: "gemini-3.5-transcribe-live", language: "en")["setup"] as! [String: Any]
        TestSupport.expectEqual(setup["model"] as? String, "models/gemini-3.5-transcribe-live")
        let generation = setup["generationConfig"] as! [String: Any]
        TestSupport.expectEqual(generation["responseModalities"] as? [String], ["TEXT"])
        let transcription = setup["inputAudioTranscription"] as! [String: Any]
        TestSupport.expectEqual(transcription["languageCodes"] as? [String], ["en"])

        let autoSetup = GeminiLiveTranscriptState.setupMessage(model: "m", language: nil)["setup"] as! [String: Any]
        TestSupport.expect((autoSetup["inputAudioTranscription"] as! [String: Any]).isEmpty, "Auto-detect sends no language codes")

        let audio = GeminiLiveTranscriptState.audioMessage(Data([1, 2, 3]), sampleRate: 24_000)
        let blob = (audio["realtimeInput"] as! [String: Any])["audio"] as! [String: Any]
        TestSupport.expectEqual(blob["mimeType"] as? String, "audio/pcm;rate=24000")
        TestSupport.expectEqual(blob["data"] as? String, "AQID")

        let end = GeminiLiveTranscriptState.audioStreamEndMessage["realtimeInput"] as! [String: Any]
        TestSupport.expectEqual(end["audioStreamEnd"] as? Bool, true)
    }

    private static func testFactoryRoutesProviders() {
        func make(_ provider: LiveTranscriptionProvider) -> LiveTranscriptionSession {
            LiveTranscriptionSessionFactory.make(LiveTranscriptionConfiguration(
                provider: provider,
                baseURL: "https://provider.invalid/v1",
                apiKey: "synthetic",
                model: "m",
                language: nil
            ))
        }
        TestSupport.expect(make(.gemini) is GeminiLiveTranscriptionService, "Gemini uses the Live API session")
        TestSupport.expect(make(.openAI) is RealtimeTranscriptionService, "OpenAI uses the realtime session")
        TestSupport.expect(make(.custom) is RealtimeTranscriptionService, "Custom uses the OpenAI-compatible session")
    }
}
