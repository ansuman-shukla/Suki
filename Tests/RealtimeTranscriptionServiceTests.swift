import Foundation

enum RealtimeTranscriptionServiceTests {
    static func run() {
        testWebSocketURLDerivation()
        testSessionUpdateLanguageField()
        testSessionUpdateShape()
        testLeadingWhitespaceTrim()
    }

    private static func url(_ baseURL: String) -> String? {
        RealtimeTranscriptionService.deriveWebSocketURL(baseURL: baseURL, model: "", language: nil)?.absoluteString
    }

    private static func testWebSocketURLDerivation() {
        TestSupport.expectEqual(
            url(LiveTranscriptionProvider.openAIBaseURL),
            "wss://api.openai.com/v1/realtime?intent=transcription"
        )
        TestSupport.expectEqual(url("http://localhost:8080/"), "ws://localhost:8080/v1/realtime?intent=transcription")
        TestSupport.expectEqual(
            url("https://provider.invalid/v1?intent=custom"),
            "wss://provider.invalid/v1/realtime?intent=custom"
        )
        TestSupport.expect(url("ftp://provider.invalid") == nil, "Non-HTTP schemes are rejected")
    }

    private static func transcription(_ payload: [String: Any]) -> [String: Any] {
        let session = payload["session"] as! [String: Any]
        let audio = session["audio"] as! [String: Any]
        let input = audio["input"] as! [String: Any]
        return input["transcription"] as! [String: Any]
    }

    private static func testSessionUpdateLanguageField() {
        let live = transcription(RealtimeTranscriptionService.sessionUpdatePayload(model: "gpt-live-transcribe", language: "en"))
        TestSupport.expectEqual(live["languages"] as? [String], ["en"])
        TestSupport.expect(live["language"] == nil, "gpt-live-transcribe must not receive the singular language field")

        let legacy = transcription(RealtimeTranscriptionService.sessionUpdatePayload(model: "gpt-4o-transcribe", language: "fr"))
        TestSupport.expectEqual(legacy["language"] as? String, "fr")
        TestSupport.expect(legacy["languages"] == nil, "Older models keep the singular language field")

        let auto = transcription(RealtimeTranscriptionService.sessionUpdatePayload(model: "gpt-live-transcribe", language: nil))
        TestSupport.expect(auto["languages"] == nil && auto["language"] == nil, "Auto-detect sends no language hint")
    }

    private static func testSessionUpdateShape() {
        let payload = RealtimeTranscriptionService.sessionUpdatePayload(model: "  ", language: "")
        TestSupport.expectEqual(payload["type"] as? String, "session.update")
        let session = payload["session"] as! [String: Any]
        TestSupport.expectEqual(session["type"] as? String, "transcription")
        let input = (session["audio"] as! [String: Any])["input"] as! [String: Any]
        TestSupport.expect(input["turn_detection"] is NSNull, "Turn detection stays disabled for push-to-talk")
        let format = input["format"] as! [String: Any]
        TestSupport.expectEqual(format["rate"] as? Int, 24_000)
        TestSupport.expect(transcription(payload).isEmpty, "Blank model and language are omitted")
    }

    private static func testLeadingWhitespaceTrim() {
        TestSupport.expectEqual(LiveTranscriptText.trimmingLeadingWhitespace("  Hello, world "), "Hello, world ")
        TestSupport.expectEqual(LiveTranscriptText.trimmingLeadingWhitespace(" \n"), "")
    }
}
