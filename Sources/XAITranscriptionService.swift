import Foundation
import os.log

private let xAITranscriptionLog = OSLog(subsystem: "com.ansumanshukla.suki", category: "XAITranscription")

/// Uploads a finished recording to xAI's speech-to-text REST endpoint.
final class XAITranscriptionService: SpeechToTextService {
    static let endpoint = URL(string: "https://api.x.ai/v1/stt")!

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
        let boundary = UUID().uuidString
        let request = Self.request(apiKey: apiKey, boundary: boundary)
        let body = Self.multipartBody(
            audio: audio,
            fileName: fileURL.lastPathComponent,
            model: model,
            language: language,
            boundary: boundary
        )
        do {
            let (data, response) = try await LLMAPITransport.upload(for: request, from: body)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard status == 200 else {
                os_log(.error, log: xAITranscriptionLog, "stt returned HTTP %ld", status)
                throw TranscriptionError.submissionFailed(
                    TranscriptionService.friendlyHTTPMessage(status: status, host: Self.endpoint.host)
                )
            }
            return try Self.parseTranscript(data)
        } catch let error as URLError where error.code == .timedOut {
            throw TranscriptionError.transcriptionTimedOut(request.timeoutInterval)
        }
    }

    static func request(apiKey: String, boundary: String) -> URLRequest {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = TranscriptionService.configuredTimeoutSeconds
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        return request
    }

    /// xAI ignores fields sent after `file`, so it goes last.
    static func multipartBody(audio: Data, fileName: String, model: String, language: String?, boundary: String) -> Data {
        var fields = [("model", model)]
        if let language, !language.isEmpty {
            fields.append(("language", language))
        }
        var body = Data()
        for (name, value) in fields {
            body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n".utf8))
        }
        body.append(Data((
            "--\(boundary)\r\n" +
            "Content-Disposition: form-data; name=\"file\"; filename=\"\(fileName)\"\r\n" +
            "Content-Type: \(TranscriptionService.audioContentType(for: fileName))\r\n\r\n"
        ).utf8))
        body.append(audio)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        return body
    }

    static func parseTranscript(_ data: Data) throws -> String {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let text = json["text"] as? String else {
            throw TranscriptionError.pollFailed("Invalid response")
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
