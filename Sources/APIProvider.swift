import Foundation

/// A hosted API whose key is saved once and shared by every feature that
/// uses it, for example Groq for both cleanup and transcription.
enum APIProvider: String, CaseIterable, Identifiable {
    case groq
    case openAI = "openai"
    case anthropic
    case gemini
    case xAI = "xai"
    case cerebras
    case deepgram

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .groq: return "Groq"
        case .openAI: return "OpenAI"
        case .anthropic: return "Anthropic"
        case .gemini: return "Gemini"
        case .xAI: return "xAI"
        case .cerebras: return "Cerebras"
        case .deepgram: return "Deepgram"
        }
    }

    /// Groq, OpenAI, and Gemini keep the accounts they were saved under
    /// before keys were shared across features.
    var apiKeyStorageAccount: String { "\(rawValue)_api_key" }

    /// Nil for Deepgram, which only offers speech-to-text.
    var openAICompatibleBaseURL: String? {
        switch self {
        case .groq: return "https://api.groq.com/openai/v1"
        case .openAI: return "https://api.openai.com/v1"
        case .anthropic: return "https://api.anthropic.com/v1"
        case .gemini: return "https://generativelanguage.googleapis.com/v1beta/openai"
        case .xAI: return "https://api.x.ai/v1"
        case .cerebras: return "https://api.cerebras.ai/v1"
        case .deepgram: return nil
        }
    }

    func keyValidationRequest(apiKey: String) -> URLRequest {
        let url: URL
        let headers: [String: String]
        switch self {
        case .groq, .openAI, .xAI, .cerebras:
            url = URL(string: "\(openAICompatibleBaseURL!)/models")!
            headers = ["Authorization": "Bearer \(apiKey)"]
        case .anthropic:
            url = URL(string: "https://api.anthropic.com/v1/models")!
            headers = ["x-api-key": apiKey, "anthropic-version": "2023-06-01"]
        case .gemini:
            url = GeminiTranscriptionService.apiBaseURL.appendingPathComponent("models")
            headers = ["x-goog-api-key": apiKey]
        case .deepgram:
            url = URL(string: "https://api.deepgram.com/v1/projects")!
            headers = ["Authorization": "Token \(apiKey)"]
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        for (field, value) in headers {
            request.setValue(value, forHTTPHeaderField: field)
        }
        return request
    }
}

enum APIKeyValidator {
    /// Lists models (or projects) with the key: free, and rejected for a bad key.
    static func validate(
        _ key: String,
        for provider: APIProvider,
        transport: @Sendable (URLRequest) async throws -> (Data, URLResponse) = { request in
            try await LLMAPITransport.data(for: request)
        }
    ) async -> Result<Void, Error> {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .failure(APIKeyValidationError.rejected(provider.displayName))
        }
        do {
            let (_, response) = try await transport(provider.keyValidationRequest(apiKey: trimmed))
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                return .failure(APIKeyValidationError.rejected(provider.displayName))
            }
            return .success(())
        } catch {
            return .failure(APIKeyValidationError.unreachable(provider.displayName))
        }
    }
}

enum APIKeyValidationError: LocalizedError {
    case rejected(String)
    case unreachable(String)

    var errorDescription: String? {
        switch self {
        case .rejected(let provider): return "\(provider) rejected this API key."
        case .unreachable(let provider): return "Couldn't reach \(provider). Check your connection and try again."
        }
    }
}
