import Foundation

enum LiveTranscriptionProvider: String, CaseIterable, Identifiable {
    case openAI = "openai"
    case gemini = "gemini"
    case custom = "custom"

    static let openAIBaseURL = "https://api.openai.com/v1"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .openAI: return "OpenAI"
        case .gemini: return "Gemini"
        case .custom: return "Custom"
        }
    }

    /// Empty for custom endpoints, which may supply a server-side default.
    var defaultModel: String {
        switch self {
        case .openAI: return "gpt-live-transcribe"
        case .gemini: return "gemini-3.5-transcribe-live"
        case .custom: return ""
        }
    }

    var suggestedModels: [String] {
        switch self {
        case .openAI: return ["gpt-live-transcribe", "gpt-transcribe", "gpt-4o-transcribe", "gpt-4o-mini-transcribe"]
        case .gemini: return ["gemini-3.5-transcribe-live"]
        case .custom: return []
        }
    }

    /// Custom reuses the API Key settings endpoint instead of a provider key.
    var credential: APIProvider? {
        switch self {
        case .openAI: return .openAI
        case .gemini: return .gemini
        case .custom: return nil
        }
    }

    /// Users who enabled realtime streaming before providers existed keep the
    /// OpenAI-compatible endpoint they already configured.
    static func initialSelection(storedValue: String?, realtimeStreamingWasEnabled: Bool) -> LiveTranscriptionProvider {
        if let storedValue, let provider = LiveTranscriptionProvider(rawValue: storedValue) {
            return provider
        }
        return realtimeStreamingWasEnabled ? .custom : .openAI
    }
}

struct LiveTranscriptionConfiguration: Equatable {
    let provider: LiveTranscriptionProvider
    let baseURL: String
    let apiKey: String
    let model: String
    let language: String?

    /// Returns nil when the selected provider lacks the credentials or
    /// endpoint it needs, so recording silently falls back to file upload.
    static func resolve(
        provider: LiveTranscriptionProvider,
        providerAPIKey: String,
        transcriptionBaseURL: String,
        transcriptionAPIKey: String,
        model: String,
        language: String?
    ) -> LiveTranscriptionConfiguration? {
        let trimmedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedModel = trimmedModel.isEmpty ? provider.defaultModel : trimmedModel
        let baseURL: String
        let apiKey: String
        switch provider {
        case .openAI, .gemini:
            apiKey = providerAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !apiKey.isEmpty else { return nil }
            baseURL = provider == .openAI ? LiveTranscriptionProvider.openAIBaseURL : ""
        case .custom:
            baseURL = transcriptionBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !baseURL.isEmpty else { return nil }
            apiKey = transcriptionAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return LiveTranscriptionConfiguration(
            provider: provider,
            baseURL: baseURL,
            apiKey: apiKey,
            model: resolvedModel,
            language: language
        )
    }
}
