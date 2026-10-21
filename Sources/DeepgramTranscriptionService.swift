import Foundation
import os.log

private let deepgramTranscriptionLog = OSLog(subsystem: "com.ansumanshukla.suki", category: "DeepgramTranscription")

/// Uploads a finished recording to Deepgram's pre-recorded listen endpoint
/// as the raw request body.
final class DeepgramTranscriptionService: SpeechToTextService {
    static let host = "api.deepgram.com"

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
        let request = Self.request(
            apiKey: apiKey,
            model: model,
            language: language,
            contentType: TranscriptionService.audioContentType(for: fileURL.lastPathComponent)
        )
        do {
            let (data, response) = try await LLMAPITransport.upload(for: request, from: audio)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard status == 200 else {
                os_log(.error, log: deepgramTranscriptionLog, "listen returned HTTP %ld", status)
                throw TranscriptionError.submissionFailed(TranscriptionService.friendlyHTTPMessage(status: status, host: Self.host))
            }
            return try Self.parseTranscript(data)
        } catch let error as URLError where error.code == .timedOut {
            throw TranscriptionError.transcriptionTimedOut(request.timeoutInterval)
        }
    }

    static func request(apiKey: String, model: String, language: String?, contentType: String) -> URLRequest {
        var components = URLComponents()
        components.scheme = "https"
        components.host = host
        components.path = "/v1/listen"
        var query = [
            URLQueryItem(name: "model", value: model),
            URLQueryItem(name: "smart_format", value: "true"),
        ]
        if let language, !language.isEmpty {
            query.append(URLQueryItem(name: "language", value: language))
        } else {
            query.append(URLQueryItem(name: "detect_language", value: "true"))
        }
        components.queryItems = query
        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.timeoutInterval = TranscriptionService.configuredTimeoutSeconds
        request.setValue("Token \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        return request
    }

    static func parseTranscript(_ data: Data) throws -> String {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = json["results"] as? [String: Any],
              let channels = results["channels"] as? [[String: Any]] else {
            throw TranscriptionError.pollFailed("Invalid response")
        }
        let alternatives = channels.first?["alternatives"] as? [[String: Any]]
        let transcript = alternatives?.first?["transcript"] as? String ?? ""
        return transcript.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
