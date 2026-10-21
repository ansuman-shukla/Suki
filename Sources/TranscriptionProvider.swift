import Foundation

/// Where recorded audio is uploaded for transcription when live
/// transcription is off or fails.
enum TranscriptionProvider: String, CaseIterable, Identifiable {
    case groq
    case openAI = "openai"
    case gemini
    case xAI = "xai"
    case deepgram
    /// Any OpenAI-compatible /audio/transcriptions endpoint.
    case custom

    /// Stored by installs from before providers were listed by name. It
    /// meant "the API key settings endpoint", Groq unless changed.
    static let legacyDefaultRawValue = "default"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .groq: return "Groq"
        case .openAI: return "OpenAI"
        case .gemini: return "Gemini"
        case .xAI: return "xAI"
        case .deepgram: return "Deepgram"
        case .custom: return "Custom"
        }
    }

    var credential: APIProvider? {
        self == .custom ? nil : APIProvider(rawValue: rawValue)
    }

    /// Empty for custom endpoints, which have no known model IDs.
    var defaultModel: String { suggestedModels.first ?? "" }

    var suggestedModels: [String] {
        switch self {
        case .groq: return ModelConfiguration.transcriptionModels
        case .openAI: return ["gpt-transcribe", "gpt-4o-transcribe", "gpt-4o-mini-transcribe", "whisper-1"]
        case .gemini: return ["gemini-3.5-transcribe"]
        case .xAI: return ["grok-voice-transcribe-2.0"]
        case .deepgram: return ["nova-3", "nova-2"]
        case .custom: return []
        }
    }

    /// Picks up the old "Default" provider, which sent audio to the
    /// transcription URL override or else the LLM base URL, with the
    /// transcription key override or else the single legacy key.
    static func migrateLegacySelection(
        storedValue: String?,
        legacyBaseURL: String,
        legacyAPIKey: String,
        transcriptionURL: String,
        transcriptionAPIKey: String,
        providerAPIKeys: [APIProvider: String]
    ) -> MigratedTranscriptionSettings {
        if let storedValue, let provider = TranscriptionProvider(rawValue: storedValue) {
            return MigratedTranscriptionSettings(provider: provider, providerAPIKeys: providerAPIKeys, customEndpoint: nil)
        }
        let overrideURL = LLMProvider.normalizedBaseURL(transcriptionURL)
        let url = overrideURL.isEmpty ? LLMProvider.normalizedBaseURL(legacyBaseURL) : overrideURL
        let key = transcriptionAPIKey.isEmpty ? legacyAPIKey : transcriptionAPIKey
        let preset: TranscriptionProvider? = url.isEmpty
            ? .groq
            : [TranscriptionProvider.groq, .openAI].first { $0.credential?.openAICompatibleBaseURL == url }
        var keys = providerAPIKeys
        guard let preset, let credential = preset.credential else {
            return MigratedTranscriptionSettings(
                provider: .custom,
                providerAPIKeys: keys,
                customEndpoint: CustomEndpoint(baseURL: url, apiKey: key)
            )
        }
        if keys[credential]?.isEmpty ?? true {
            keys[credential] = key
        }
        return MigratedTranscriptionSettings(provider: preset, providerAPIKeys: keys, customEndpoint: nil)
    }
}

struct CustomEndpoint: Equatable {
    let baseURL: String
    let apiKey: String
}

struct MigratedTranscriptionSettings: Equatable {
    let provider: TranscriptionProvider
    let providerAPIKeys: [APIProvider: String]
    /// Set only when the old endpoint becomes the custom endpoint.
    let customEndpoint: CustomEndpoint?
}

struct TranscriptionConfiguration: Equatable {
    let provider: TranscriptionProvider
    let baseURL: String
    let apiKey: String
    let model: String
    let language: String?

    static func resolve(
        provider: TranscriptionProvider,
        providerAPIKey: String,
        customEndpoint: CustomEndpoint,
        model: String,
        language: String?
    ) -> TranscriptionConfiguration {
        let trimmedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseURL: String
        let apiKey: String
        if let credential = provider.credential {
            baseURL = credential.openAICompatibleBaseURL ?? ""
            apiKey = providerAPIKey
        } else {
            baseURL = LLMProvider.normalizedBaseURL(customEndpoint.baseURL)
            apiKey = customEndpoint.apiKey
        }
        return TranscriptionConfiguration(
            provider: provider,
            baseURL: baseURL,
            apiKey: apiKey.trimmingCharacters(in: .whitespacesAndNewlines),
            model: trimmedModel.isEmpty ? provider.defaultModel : trimmedModel,
            language: language
        )
    }
}

enum TranscriptionModelTest {
    /// Transcribes a second of generated silence, so a model ID and key can
    /// be checked without recording anything. An empty transcript passes.
    static func run(
        _ configuration: TranscriptionConfiguration,
        makeService: (TranscriptionConfiguration) throws -> SpeechToTextService = SpeechToTextServiceFactory.make
    ) async -> Result<Void, Error> {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("suki-model-test-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        do {
            try silentWAV().write(to: fileURL)
            _ = try await makeService(configuration).transcribe(fileURL: fileURL)
            return .success(())
        } catch {
            return .failure(error)
        }
    }

    /// Mono 16-bit PCM WAV filled with zeros.
    static func silentWAV(seconds: Double = 1, sampleRate: Int = 16_000) -> Data {
        let dataSize = Int(Double(sampleRate) * seconds) * 2
        var wav = Data()
        func append<T: FixedWidthInteger>(_ value: T) {
            withUnsafeBytes(of: value.littleEndian) { wav.append(contentsOf: $0) }
        }
        wav.append(Data("RIFF".utf8))
        append(UInt32(36 + dataSize))
        wav.append(Data("WAVEfmt ".utf8))
        append(UInt32(16))
        append(UInt16(1))
        append(UInt16(1))
        append(UInt32(sampleRate))
        append(UInt32(sampleRate * 2))
        append(UInt16(2))
        append(UInt16(16))
        wav.append(Data("data".utf8))
        append(UInt32(dataSize))
        wav.append(Data(count: dataSize))
        return wav
    }
}
