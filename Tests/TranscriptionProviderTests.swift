import Foundation

enum TranscriptionProviderTests {
    static func run() async {
        testInitialSelection()
        testResolve()
        testFactory()
        testGeminiRequestBody()
        testGeminiParseTranscript()
        await testGeminiKeyValidation()
    }

    private static func testInitialSelection() {
        TestSupport.expectEqual(TranscriptionProvider.initialSelection(storedValue: nil), .standard)
        TestSupport.expectEqual(TranscriptionProvider.initialSelection(storedValue: "gemini"), .gemini)
        TestSupport.expectEqual(TranscriptionProvider.initialSelection(storedValue: "retired"), .standard)
        for provider in TranscriptionProvider.allCases {
            TestSupport.expect(provider.suggestedModels.first == provider.defaultModel, "\(provider) lists its default model first")
        }
    }

    private static func resolve(_ provider: TranscriptionProvider, key: String = " provider-key ", model: String = "") -> TranscriptionConfiguration {
        TranscriptionConfiguration.resolve(
            provider: provider,
            providerAPIKey: key,
            standardBaseURL: "https://standard.invalid/v1",
            standardAPIKey: "standard-key",
            model: model,
            language: "en"
        )
    }

    private static func testResolve() {
        TestSupport.expectEqual(resolve(.standard), TranscriptionConfiguration(
            provider: .standard,
            baseURL: "https://standard.invalid/v1",
            apiKey: "standard-key",
            model: "whisper-large-v3",
            language: "en"
        ))
        let openAI = resolve(.openAI, model: " whisper-1 ")
        TestSupport.expectEqual(openAI.baseURL, "https://api.openai.com/v1")
        TestSupport.expectEqual(openAI.apiKey, "provider-key")
        TestSupport.expectEqual(openAI.model, "whisper-1")
        let gemini = resolve(.gemini)
        TestSupport.expectEqual(gemini.apiKey, "provider-key")
        TestSupport.expectEqual(gemini.model, "gemini-3.5-transcribe")
    }

    private static func testFactory() {
        TestSupport.expect((try? SpeechToTextServiceFactory.make(resolve(.gemini))) is GeminiTranscriptionService, "Gemini uses generateContent")
        TestSupport.expect((try? SpeechToTextServiceFactory.make(resolve(.openAI))) is TranscriptionService, "OpenAI uses audio/transcriptions")
        TestSupport.expect((try? SpeechToTextServiceFactory.make(resolve(.standard))) is TranscriptionService, "Default uses audio/transcriptions")
        do {
            _ = try SpeechToTextServiceFactory.make(resolve(.gemini, key: " "))
            TestSupport.expect(false, "Missing provider key must fail")
        } catch {
            TestSupport.expect(error.localizedDescription.contains("Gemini API key"), "Missing key error names the provider")
        }
    }

    private static func testGeminiRequestBody() {
        let body = try! GeminiTranscriptionService.requestBody(audio: Data([1, 2, 3]), mimeType: "audio/wav", language: "fr")
        let json = try! JSONSerialization.jsonObject(with: body) as! [String: Any]
        let parts = ((json["contents"] as! [[String: Any]])[0]["parts"] as! [[String: Any]])
        let inline = parts[0]["inlineData"] as! [String: Any]
        TestSupport.expectEqual(inline["mimeType"] as? String, "audio/wav")
        TestSupport.expectEqual(inline["data"] as? String, "AQID")
        let config = (json["generationConfig"] as! [String: Any])["audioTranscriptionConfig"] as! [String: Any]
        TestSupport.expectEqual(config["languageCodes"] as? [String], ["fr"])

        let auto = try! GeminiTranscriptionService.requestBody(audio: Data(), mimeType: "audio/wav", language: nil)
        let autoJSON = try! JSONSerialization.jsonObject(with: auto) as! [String: Any]
        let autoConfig = (autoJSON["generationConfig"] as! [String: Any])["audioTranscriptionConfig"] as! [String: Any]
        TestSupport.expect(autoConfig.isEmpty, "Auto-detect sends no language codes")
    }

    private static func testGeminiParseTranscript() {
        let transcribeModel = #"{"candidates":[{"content":{"parts":[{"audioTranscription":{"text":"Synthetic phrase 83 times."}}],"role":"model"},"finishReason":"STOP"}]}"#
        TestSupport.expectEqual(try? GeminiTranscriptionService.parseTranscript(Data(transcribeModel.utf8)), "Synthetic phrase 83 times.")
        let response = #"{"candidates":[{"content":{"parts":[{"text":" Hello, "},{"text":"world. \n"}]}}]}"#
        TestSupport.expectEqual(try? GeminiTranscriptionService.parseTranscript(Data(response.utf8)), "Hello, world.")
        let empty = #"{"candidates":[{"content":{"parts":[]}}]}"#
        TestSupport.expectEqual(try? GeminiTranscriptionService.parseTranscript(Data(empty.utf8)), "")
        TestSupport.expect((try? GeminiTranscriptionService.parseTranscript(Data(#"{"error":{}}"#.utf8))) == nil, "Responses without candidates are errors")
    }

    private static func testGeminiKeyValidation() async {
        func transport(status: Int) -> @Sendable (URLRequest) async throws -> (Data, URLResponse) {
            { request in
                TestSupport.expectEqual(request.value(forHTTPHeaderField: "x-goog-api-key"), "synthetic-key")
                TestSupport.expectEqual(request.url?.absoluteString, "https://generativelanguage.googleapis.com/v1beta/models")
                return (Data(), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
            }
        }
        let valid = await GeminiTranscriptionService.validateAPIKey(" synthetic-key ", transport: transport(status: 200))
        TestSupport.expect(valid, "200 from models list means the key works")
        let rejected = await GeminiTranscriptionService.validateAPIKey("synthetic-key", transport: transport(status: 400))
        TestSupport.expect(!rejected, "Non-200 means the key is rejected")
        let blank = await GeminiTranscriptionService.validateAPIKey("  ", transport: transport(status: 200))
        TestSupport.expect(!blank, "Blank keys are never sent")
    }
}
