import Foundation
import os.log

private let geminiTranscriptionLog = OSLog(subsystem: "com.ansumanshukla.suki", category: "GeminiTranscription")

/// Uploads a finished recording to a Gemini speech-to-text model with
/// generateContent. Audio is sent inline, which keeps dictation to a single
/// request but caps the recording length.
final class GeminiTranscriptionService: SpeechToTextService {
    static let apiBaseURL = URL(string: "https://generativelanguage.googleapis.com/v1beta")!
    /// Inline requests are limited to 20 MB; base64 adds a third on top.
    static let maxInlineAudioBytes = 14 * 1024 * 1024

    private let apiKey: String
    private let model: String
    private let language: String?

    init(apiKey: String, model: String, language: String?) {
        self.apiKey = apiKey
        self.model = model
        self.language = language
    }

    func transcribe(fileURL: URL) async throws -> String {
        let audio = try Data(contentsOf: fileURL)
        guard audio.count <= Self.maxInlineAudioBytes else {
            throw TranscriptionError.submissionFailed("Recording is too long to send to Gemini. Use another transcription provider for long recordings.")
        }
        var request = URLRequest(url: Self.apiBaseURL.appendingPathComponent("models/\(model):generateContent"))
        request.httpMethod = "POST"
        request.timeoutInterval = TranscriptionService.configuredTimeoutSeconds
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body = try Self.requestBody(
            audio: audio,
            mimeType: TranscriptionService.audioContentType(for: fileURL.lastPathComponent),
            language: language
        )
        do {
            let (data, response) = try await LLMAPITransport.upload(for: request, from: body)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard status == 200 else {
                os_log(.error, log: geminiTranscriptionLog, "generateContent returned HTTP %ld", status)
                throw TranscriptionError.submissionFailed(
                    TranscriptionService.friendlyHTTPMessage(status: status, host: Self.apiBaseURL.host)
                )
            }
            return try Self.parseTranscript(data)
        } catch let error as URLError where error.code == .timedOut {
            throw TranscriptionError.transcriptionTimedOut(request.timeoutInterval)
        }
    }

    static func requestBody(audio: Data, mimeType: String, language: String?) throws -> Data {
        var transcription: [String: Any] = [:]
        if let language, !language.isEmpty {
            transcription["languageCodes"] = [language]
        }
        let payload: [String: Any] = [
            "contents": [
                ["parts": [["inlineData": ["mimeType": mimeType, "data": audio.base64EncodedString()]]]],
            ],
            "generationConfig": ["audioTranscriptionConfig": transcription],
        ]
        return try JSONSerialization.data(withJSONObject: payload)
    }

    static func parseTranscript(_ data: Data) throws -> String {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = json["candidates"] as? [[String: Any]] else {
            throw TranscriptionError.pollFailed("Invalid response")
        }
        let parts = (candidates.first?["content"] as? [String: Any])?["parts"] as? [[String: Any]] ?? []
        // Transcribe models return `audioTranscription.text`; general models
        // return plain `text` parts.
        return parts.compactMap { part in
            (part["audioTranscription"] as? [String: Any])?["text"] as? String ?? part["text"] as? String
        }
        .joined()
        .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum SpeechToTextServiceFactory {
    static func make(_ configuration: TranscriptionConfiguration) throws -> SpeechToTextService {
        if let credential = configuration.provider.credential, configuration.apiKey.isEmpty {
            throw TranscriptionError.submissionFailed(
                "Add your \(credential.displayName) API key in Settings > Transcription."
            )
        }
        if configuration.provider == .custom, configuration.baseURL.isEmpty {
            throw TranscriptionError.submissionFailed("Set a custom transcription endpoint in Settings > Transcription.")
        }
        switch configuration.provider {
        case .gemini:
            return GeminiTranscriptionService(
                apiKey: configuration.apiKey,
                model: configuration.model,
                language: configuration.language
            )
        case .xAI:
            return XAITranscriptionService(
                apiKey: configuration.apiKey,
                model: configuration.model,
                language: configuration.language
            )
        case .deepgram:
            return DeepgramTranscriptionService(
                apiKey: configuration.apiKey,
                model: configuration.model,
                language: configuration.language
            )
        case .groq, .openAI, .custom:
            return try TranscriptionService(
                apiKey: configuration.apiKey,
                baseURL: configuration.baseURL,
                transcriptionModel: configuration.model,
                language: configuration.language
            )
        }
    }
}
