import Foundation

/// Cloud speech providers whose API key is shared by upload and live
/// transcription.
enum CloudSpeechProvider: String, CaseIterable {
    case openAI = "openai"
    case gemini

    var displayName: String {
        switch self {
        case .openAI: return "OpenAI"
        case .gemini: return "Gemini"
        }
    }

    var apiKeyStorageAccount: String {
        switch self {
        case .openAI: return "openai_api_key"
        case .gemini: return "gemini_api_key"
        }
    }
}

/// Where recorded audio is uploaded for transcription when live
/// transcription is off or fails.
enum TranscriptionProvider: String, CaseIterable, Identifiable {
    /// The OpenAI-compatible endpoint from API Key settings (Groq by default).
    case standard = "default"
    case openAI = "openai"
    case gemini

    static let openAIBaseURL = "https://api.openai.com/v1"
    static let standardDefaultModel = "whisper-large-v3"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .standard: return "Default"
        case .openAI: return "OpenAI"
        case .gemini: return "Gemini"
        }
    }

    var credential: CloudSpeechProvider? {
        switch self {
        case .standard: return nil
        case .openAI: return .openAI
        case .gemini: return .gemini
        }
    }

    var defaultModel: String {
        switch self {
        case .standard: return Self.standardDefaultModel
        case .openAI: return "gpt-transcribe"
        case .gemini: return "gemini-3.5-transcribe"
        }
    }

    var suggestedModels: [String] {
        switch self {
        case .standard: return ModelConfiguration.transcriptionModels
        case .openAI: return ["gpt-transcribe", "gpt-4o-transcribe", "gpt-4o-mini-transcribe", "whisper-1"]
        case .gemini: return ["gemini-3.5-transcribe"]
        }
    }

    static func initialSelection(storedValue: String?) -> TranscriptionProvider {
        storedValue.flatMap(TranscriptionProvider.init(rawValue:)) ?? .standard
    }
}

struct TranscriptionConfiguration: Equatable {
    let provider: TranscriptionProvider
    let baseURL: String
    let apiKey: String
    let model: String
    let language: String?

    /// `standardBaseURL` and `standardAPIKey` are the already-resolved
    /// transcription endpoint from API Key settings.
    static func resolve(
        provider: TranscriptionProvider,
        providerAPIKey: String,
        standardBaseURL: String,
        standardAPIKey: String,
        model: String,
        language: String?
    ) -> TranscriptionConfiguration {
        let trimmedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedModel = trimmedModel.isEmpty ? provider.defaultModel : trimmedModel
        let baseURL: String
        let apiKey: String
        switch provider {
        case .standard:
            baseURL = standardBaseURL
            apiKey = standardAPIKey
        case .openAI:
            baseURL = TranscriptionProvider.openAIBaseURL
            apiKey = providerAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        case .gemini:
            baseURL = ""
            apiKey = providerAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return TranscriptionConfiguration(
            provider: provider,
            baseURL: baseURL,
            apiKey: apiKey,
            model: resolvedModel,
            language: language
        )
    }
}
