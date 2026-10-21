import Foundation

enum LiveTranscriptionProviderTests {
    static func run() {
        testInitialSelectionMigration()
        testResolveOwnKeyProviders()
        testResolveCustomProvider()
        testProviderMetadata()
    }

    private static func testInitialSelectionMigration() {
        TestSupport.expectEqual(
            LiveTranscriptionProvider.initialSelection(storedValue: "gemini", realtimeStreamingWasEnabled: true),
            .gemini
        )
        TestSupport.expectEqual(
            LiveTranscriptionProvider.initialSelection(storedValue: nil, realtimeStreamingWasEnabled: true),
            .custom
        )
        TestSupport.expectEqual(
            LiveTranscriptionProvider.initialSelection(storedValue: nil, realtimeStreamingWasEnabled: false),
            .openAI
        )
        TestSupport.expectEqual(
            LiveTranscriptionProvider.initialSelection(storedValue: "retired", realtimeStreamingWasEnabled: true),
            .custom
        )
    }

    private static func testResolveOwnKeyProviders() {
        let openAI = LiveTranscriptionConfiguration.resolve(
            provider: .openAI,
            providerAPIKey: "  sk-synthetic  ",
            transcriptionBaseURL: "https://transcription.invalid/v1",
            transcriptionAPIKey: "transcription-key",
            model: "  ",
            language: "en"
        )
        TestSupport.expectEqual(openAI, LiveTranscriptionConfiguration(
            provider: .openAI,
            baseURL: "https://api.openai.com/v1",
            apiKey: "sk-synthetic",
            model: "gpt-live-transcribe",
            language: "en"
        ))

        let gemini = LiveTranscriptionConfiguration.resolve(
            provider: .gemini,
            providerAPIKey: "gemini-synthetic",
            transcriptionBaseURL: "https://transcription.invalid/v1",
            transcriptionAPIKey: "transcription-key",
            model: "custom-live-model",
            language: nil
        )
        TestSupport.expectEqual(gemini?.apiKey, "gemini-synthetic")
        TestSupport.expectEqual(gemini?.model, "custom-live-model")
        TestSupport.expectEqual(gemini?.baseURL, "")

        TestSupport.expect(
            LiveTranscriptionConfiguration.resolve(
                provider: .openAI,
                providerAPIKey: " ",
                transcriptionBaseURL: "https://transcription.invalid/v1",
                transcriptionAPIKey: "transcription-key",
                model: "",
                language: nil
            ) == nil,
            "Own-key providers never borrow the transcription key"
        )
    }

    private static func testResolveCustomProvider() {
        let custom = LiveTranscriptionConfiguration.resolve(
            provider: .custom,
            providerAPIKey: "ignored",
            transcriptionBaseURL: " https://transcription.invalid/v1 ",
            transcriptionAPIKey: "",
            model: "",
            language: "fr"
        )
        TestSupport.expectEqual(custom, LiveTranscriptionConfiguration(
            provider: .custom,
            baseURL: "https://transcription.invalid/v1",
            apiKey: "",
            model: "",
            language: "fr"
        ))
        TestSupport.expect(
            LiveTranscriptionConfiguration.resolve(
                provider: .custom,
                providerAPIKey: "ignored",
                transcriptionBaseURL: "  ",
                transcriptionAPIKey: "key",
                model: "",
                language: nil
            ) == nil,
            "Custom requires a transcription endpoint"
        )
    }

    private static func testProviderMetadata() {
        for provider in LiveTranscriptionProvider.allCases where provider != .custom {
            TestSupport.expect(
                provider.suggestedModels.first == provider.defaultModel,
                "\(provider) lists its default model first"
            )
            TestSupport.expectEqual(provider.credential?.rawValue, provider.rawValue)
        }
        TestSupport.expect(LiveTranscriptionProvider.custom.credential == nil, "Custom reuses transcription key")
    }
}
