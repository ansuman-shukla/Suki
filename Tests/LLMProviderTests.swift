import Foundation

enum LLMProviderTests {
    static func run() {
        testPresets()
        testMigration()
        testResolve()
    }

    private static func testPresets() {
        let expectedURLs: [LLMProvider: String] = [
            .groq: "https://api.groq.com/openai/v1",
            .openAI: "https://api.openai.com/v1",
            .anthropic: "https://api.anthropic.com/v1",
            .gemini: "https://generativelanguage.googleapis.com/v1beta/openai",
            .xAI: "https://api.x.ai/v1",
            .cerebras: "https://api.cerebras.ai/v1",
        ]
        for provider in LLMProvider.allCases where provider != .custom {
            TestSupport.expectEqual(provider.presetBaseURL, expectedURLs[provider])
            TestSupport.expectEqual(provider.credential?.rawValue, provider.rawValue)
            guard let defaults = provider.defaultModels else {
                return TestSupport.expect(false, "\(provider) has default models")
            }
            TestSupport.expectEqual(provider.models.first, defaults.postProcessing)
            TestSupport.expect(provider.models.contains(defaults.postProcessingFallback), "\(provider) lists its fallback model")
            TestSupport.expect(defaults.postProcessingFallback != defaults.postProcessing, "\(provider) falls back to a different model")
            TestSupport.expect(provider.visionModels.contains(defaults.context), "\(provider) context default accepts images")
        }
        TestSupport.expect(LLMProvider.custom.credential == nil, "Custom has its own key")
        TestSupport.expect(LLMProvider.custom.presetBaseURL == nil, "Custom has its own URL")
        TestSupport.expect(LLMProvider.custom.defaultModels == nil, "Custom keeps the models the user typed")
        TestSupport.expectEqual(LLMProvider.groq.defaultModels?.postProcessing, "openai/gpt-oss-20b")
        TestSupport.expect(!LLMProvider.cerebras.visionModels.contains("gpt-oss-120b"), "gpt-oss is text only")
    }

    private static func testMigration() {
        TestSupport.expectEqual(LLMProvider.migratedSelection(storedBaseURL: ""), .groq)
        TestSupport.expectEqual(LLMProvider.migratedSelection(storedBaseURL: "https://api.groq.com/openai/v1"), .groq)
        TestSupport.expectEqual(LLMProvider.migratedSelection(storedBaseURL: " https://api.openai.com/v1/ "), .openAI)
        TestSupport.expectEqual(LLMProvider.migratedSelection(storedBaseURL: "https://api.anthropic.com/v1/"), .anthropic)
        TestSupport.expectEqual(LLMProvider.migratedSelection(storedBaseURL: "https://api.cerebras.ai/v1"), .cerebras)
        TestSupport.expectEqual(LLMProvider.migratedSelection(storedBaseURL: "https://router.example.invalid/api/v1"), .custom)
    }

    private static func testResolve() {
        let gemini = LLMConfiguration.resolve(
            provider: .gemini,
            providerAPIKey: " gemini-key ",
            customBaseURL: "https://custom.invalid/v1",
            customAPIKey: "custom-key"
        )
        TestSupport.expectEqual(gemini, LLMConfiguration(
            provider: .gemini,
            baseURL: "https://generativelanguage.googleapis.com/v1beta/openai",
            apiKey: "gemini-key"
        ))
        let custom = LLMConfiguration.resolve(
            provider: .custom,
            providerAPIKey: "unused",
            customBaseURL: " https://custom.invalid/v1/ ",
            customAPIKey: " custom-key "
        )
        TestSupport.expectEqual(custom, LLMConfiguration(provider: .custom, baseURL: "https://custom.invalid/v1", apiKey: "custom-key"))
    }
}
