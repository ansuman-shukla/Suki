import Foundation

@main
struct SukiTests {
    static func main() async {
        AppContextServiceTests.run()
        await LLMAPITransportTests.run()
        TemperatureCapabilityCacheTests.run()
        ModelConfigurationTests.run()
        RecordingCaptureTimingTests.run()
        RecordingTimerPreferenceTests.run()
        DictationStatsTests.run()
        ShortcutCoreTests.run()
        SemanticVersionTests.run()
        LLMCooldownManagerTests.run()
        PostProcessingServiceTests.run()
        TranscriptionErrorPresentationCoreTests.run()
        TranscriptTextCoreTests.run()
        LiveTranscriptionProviderTests.run()
        await TranscriptionProviderTests.run()
        RealtimeTranscriptionServiceTests.run()
        GeminiLiveTranscriptionServiceTests.run()
        LiveTypingCoreTests.run()
        MeetingTranscriptCoreTests.run()
        MeetingStoreTests.run()
        SyntheticKeystrokeTyperTests.run()
        await TranscriptionServiceTests.run()
        await APIConfigurationDraftTests.run()
        print("SukiTests passed")
    }
}
