import Foundation

/// Where cleanup, Edit Mode, and context inference send chat completions.
/// Every preset speaks the OpenAI-compatible chat completions API.
enum LLMProvider: String, CaseIterable, Identifiable {
    case groq
    case openAI = "openai"
    case anthropic
    case gemini
    case xAI = "xai"
    case cerebras
    /// Any other OpenAI-compatible endpoint, with its own URL and key.
    case custom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .groq: return "Groq"
        case .openAI: return "OpenAI"
        case .anthropic: return "Anthropic"
        case .gemini: return "Google Gemini"
        case .xAI: return "xAI Grok"
        case .cerebras: return "Cerebras"
        case .custom: return "Custom (OpenAI-compatible)"
        }
    }

    var credential: APIProvider? {
        self == .custom ? nil : APIProvider(rawValue: rawValue)
    }

    var presetBaseURL: String? { credential?.openAICompatibleBaseURL }

    /// Suggested model IDs, fastest first. Custom endpoints have no list.
    var models: [String] {
        switch self {
        case .groq: return ModelConfiguration.llmModels
        case .openAI: return ["gpt-6-luna", "gpt-6.1-sol", "gpt-6-astra", "gpt-5.4-mini", "gpt-5.4-nano"]
        case .anthropic: return ["claude-haiku-5-5", "claude-sonnet-5-5", "claude-opus-5-5", "claude-haiku-4-5-20251001"]
        case .gemini: return ["gemini-3.5-flash-lite", "gemini-3.8-flash", "gemini-4-argon"]
        case .xAI: return ["grok-4.20-0309-non-reasoning", "grok-4.7", "grok-4.20-0309-reasoning"]
        case .cerebras: return ["gpt-oss-120b", "qwen-3.8-27b"]
        case .custom: return []
        }
    }

    /// Models that accept image input, for screenshot context.
    var visionModels: [String] {
        switch self {
        case .groq: return ModelConfiguration.visionModels
        case .cerebras: return ["qwen-3.8-27b"]
        case .openAI, .anthropic, .gemini, .xAI, .custom: return models
        }
    }

    /// Nil for custom endpoints, whose model IDs are unknown.
    var defaultModels: LLMModelSelection? {
        switch self {
        case .groq:
            return LLMModelSelection(
                postProcessing: "openai/gpt-oss-20b",
                postProcessingFallback: "qwen/qwen3.8-27b",
                context: "qwen/qwen3.8-27b"
            )
        case .openAI:
            return LLMModelSelection(postProcessing: "gpt-6-luna", postProcessingFallback: "gpt-5.4-mini", context: "gpt-6-luna")
        case .anthropic:
            return LLMModelSelection(
                postProcessing: "claude-haiku-5-5",
                postProcessingFallback: "claude-haiku-4-5-20251001",
                context: "claude-haiku-5-5"
            )
        case .gemini:
            return LLMModelSelection(
                postProcessing: "gemini-3.5-flash-lite",
                postProcessingFallback: "gemini-3.8-flash",
                context: "gemini-3.5-flash-lite"
            )
        case .xAI:
            return LLMModelSelection(
                postProcessing: "grok-4.20-0309-non-reasoning",
                postProcessingFallback: "grok-4.7",
                context: "grok-4.20-0309-non-reasoning"
            )
        case .cerebras:
            return LLMModelSelection(postProcessing: "gpt-oss-120b", postProcessingFallback: "qwen-3.8-27b", context: "qwen-3.8-27b")
        case .custom:
            return nil
        }
    }

    /// Picks the provider for installs that only stored an API base URL.
    static func migratedSelection(storedBaseURL: String) -> LLMProvider {
        let normalized = normalizedBaseURL(storedBaseURL)
        guard !normalized.isEmpty else { return .groq }
        return allCases.first { $0.presetBaseURL == normalized } ?? .custom
    }

    /// Before providers existed, one key was saved under Groq's account
    /// whatever the base URL was. Moves it to the provider it belongs to.
    static func migrateLegacySettings(
        legacyBaseURL: String,
        providerAPIKeys: [APIProvider: String]
    ) -> MigratedLLMSettings {
        let provider = migratedSelection(storedBaseURL: legacyBaseURL)
        var keys = providerAPIKeys
        let legacyKey = keys[.groq] ?? ""
        var customEndpoint: (baseURL: String, apiKey: String)?
        guard provider != .groq else {
            return MigratedLLMSettings(provider: provider, providerAPIKeys: keys, customBaseURL: nil, customAPIKey: nil)
        }
        if let credential = provider.credential {
            if keys[credential]?.isEmpty ?? true {
                keys[credential] = legacyKey
            }
        } else {
            customEndpoint = (normalizedBaseURL(legacyBaseURL), legacyKey)
        }
        keys[.groq] = ""
        return MigratedLLMSettings(
            provider: provider,
            providerAPIKeys: keys,
            customBaseURL: customEndpoint?.baseURL,
            customAPIKey: customEndpoint?.apiKey
        )
    }

    static func normalizedBaseURL(_ url: String) -> String {
        var trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        while trimmed.hasSuffix("/") { trimmed.removeLast() }
        return trimmed
    }
}

struct MigratedLLMSettings: Equatable {
    let provider: LLMProvider
    let providerAPIKeys: [APIProvider: String]
    /// Set only when the legacy base URL becomes the custom endpoint.
    let customBaseURL: String?
    let customAPIKey: String?
}

struct LLMModelSelection: Equatable {
    let postProcessing: String
    let postProcessingFallback: String
    let context: String
}

struct LLMConfiguration: Equatable {
    let provider: LLMProvider
    let baseURL: String
    let apiKey: String

    static func resolve(
        provider: LLMProvider,
        providerAPIKey: String,
        customBaseURL: String,
        customAPIKey: String
    ) -> LLMConfiguration {
        let baseURL = provider.presetBaseURL ?? LLMProvider.normalizedBaseURL(customBaseURL)
        let apiKey = provider == .custom ? customAPIKey : providerAPIKey
        return LLMConfiguration(
            provider: provider,
            baseURL: baseURL,
            apiKey: apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }
}

enum LLMModelTest {
    /// Sends a one-line chat completion so a model ID can be checked before
    /// dictation depends on it. The prompt is fixed and contains no user data.
    static func run(
        model: String,
        configuration: LLMConfiguration,
        transport: @Sendable (URLRequest) async throws -> (Data, URLResponse) = { request in
            try await LLMAPITransport.data(for: request)
        }
    ) async -> Result<Void, Error> {
        guard let request = request(model: model, configuration: configuration) else {
            return .failure(LLMModelTestError.notConfigured)
        }
        do {
            let (data, response) = try await transport(request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard status == 200 else {
                return .failure(LLMModelTestError.rejected(status: status, message: providerMessage(in: data)))
            }
            return .success(())
        } catch {
            return .failure(LLMModelTestError.unreachable)
        }
    }

    static func request(model: String, configuration: LLMConfiguration) -> URLRequest? {
        let trimmedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedModel.isEmpty, !configuration.apiKey.isEmpty,
              let url = URL(string: "\(configuration.baseURL)/chat/completions") else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("Bearer \(configuration.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var payload: [String: Any] = [
            "messages": [["role": "user", "content": "Reply with the word OK."]],
            "max_completion_tokens": 32,
        ]
        payload.merge(ModelConfiguration.nonContentRequestOptions(model: trimmedModel, temperature: 0)) { _, option in option }
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        return request
    }

    /// The provider's own error text (for example "model not found"),
    /// shortened because it is shown in Settings.
    static func providerMessage(in data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) else { return nil }
        let error = ((json as? [String: Any]) ?? (json as? [[String: Any]])?.first)?["error"]
        let message = (error as? [String: Any])?["message"] as? String ?? error as? String
        guard let message = message?.trimmingCharacters(in: .whitespacesAndNewlines), !message.isEmpty else { return nil }
        return message.count > 160 ? String(message.prefix(160)) + "…" : message
    }
}

enum LLMModelTestError: LocalizedError, Equatable {
    case notConfigured
    case rejected(status: Int, message: String?)
    case unreachable

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "Save an API key and pick a model first."
        case .rejected(let status, let message): return message.map { "HTTP \(status): \($0)" } ?? "HTTP \(status)"
        case .unreachable: return "Couldn't reach the provider. Check the URL and your connection."
        }
    }
}
