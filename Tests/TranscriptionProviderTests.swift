import Foundation

enum TranscriptionProviderTests {
    static func run() async {
        testMetadata()
        testLegacyMigration()
        testResolve()
        testFactory()
        testGeminiRequestBody()
        testGeminiParseTranscript()
        testXAIRequest()
        testDeepgramRequest()
    }

    private static func testMetadata() {
        for provider in TranscriptionProvider.allCases where provider != .custom {
            TestSupport.expect(!provider.suggestedModels.isEmpty, "\(provider) suggests models")
            TestSupport.expectEqual(provider.suggestedModels.first, provider.defaultModel)
            TestSupport.expectEqual(provider.credential?.rawValue, provider.rawValue)
        }
        TestSupport.expect(TranscriptionProvider.custom.credential == nil, "Custom has its own endpoint")
        TestSupport.expectEqual(TranscriptionProvider.custom.defaultModel, "")
        TestSupport.expectEqual(TranscriptionProvider.xAI.defaultModel, "grok-voice-transcribe-2.0")
        TestSupport.expectEqual(TranscriptionProvider.deepgram.defaultModel, "nova-3")
    }

    private static func migrate(
        _ stored: String?,
        baseURL: String = "",
        legacyKey: String = "legacy",
        url: String = "",
        key: String = "",
        keys: [APIProvider: String] = [:]
    ) -> MigratedTranscriptionSettings {
        TranscriptionProvider.migrateLegacySelection(
            storedValue: stored,
            legacyBaseURL: baseURL,
            legacyAPIKey: legacyKey,
            transcriptionURL: url,
            transcriptionAPIKey: key,
            providerAPIKeys: keys
        )
    }

    private static func testLegacyMigration() {
        let gemini = migrate("gemini", keys: [.gemini: "g"])
        TestSupport.expectEqual(gemini, MigratedTranscriptionSettings(provider: .gemini, providerAPIKeys: [.gemini: "g"], customEndpoint: nil))

        // Old "Default" on Groq: the legacy key already lives in Groq's slot.
        TestSupport.expectEqual(migrate("default", keys: [.groq: "legacy"]).provider, .groq)
        TestSupport.expectEqual(migrate(nil, keys: [.groq: "legacy"]).providerAPIKeys[.groq], "legacy")

        // The LLM migration may have moved the key out of Groq's slot.
        let groqOverride = migrate("default", baseURL: "https://api.openai.com/v1", url: "https://api.groq.com/openai/v1/", key: "groq-key")
        TestSupport.expectEqual(groqOverride.provider, .groq)
        TestSupport.expectEqual(groqOverride.providerAPIKeys[.groq], "groq-key")

        let openAI = migrate("default", baseURL: "https://api.openai.com/v1", keys: [.openAI: "saved"])
        TestSupport.expectEqual(openAI.provider, .openAI)
        TestSupport.expectEqual(openAI.providerAPIKeys[.openAI], "saved")

        let custom = migrate("default", baseURL: "https://router.example.invalid/v1", url: "https://stt.example.invalid/v1/", key: "")
        TestSupport.expectEqual(custom, MigratedTranscriptionSettings(
            provider: .custom,
            providerAPIKeys: [:],
            customEndpoint: CustomEndpoint(baseURL: "https://stt.example.invalid/v1", apiKey: "legacy")
        ))
        TestSupport.expectEqual(
            migrate("default", baseURL: "https://router.example.invalid/v1").customEndpoint,
            CustomEndpoint(baseURL: "https://router.example.invalid/v1", apiKey: "legacy")
        )
    }

    private static func resolve(_ provider: TranscriptionProvider, key: String = " provider-key ", model: String = "") -> TranscriptionConfiguration {
        TranscriptionConfiguration.resolve(
            provider: provider,
            providerAPIKey: key,
            customEndpoint: CustomEndpoint(baseURL: "https://custom.invalid/v1/", apiKey: " custom-key "),
            model: model,
            language: "en"
        )
    }

    private static func testResolve() {
        TestSupport.expectEqual(resolve(.groq), TranscriptionConfiguration(
            provider: .groq,
            baseURL: "https://api.groq.com/openai/v1",
            apiKey: "provider-key",
            model: "whisper-large-v3",
            language: "en"
        ))
        let openAI = resolve(.openAI, model: " whisper-1 ")
        TestSupport.expectEqual(openAI.baseURL, "https://api.openai.com/v1")
        TestSupport.expectEqual(openAI.model, "whisper-1")
        TestSupport.expectEqual(resolve(.gemini).model, "gemini-3.5-transcribe")
        TestSupport.expectEqual(resolve(.custom, model: "local-whisper"), TranscriptionConfiguration(
            provider: .custom,
            baseURL: "https://custom.invalid/v1",
            apiKey: "custom-key",
            model: "local-whisper",
            language: "en"
        ))
    }

    private static func testFactory() {
        TestSupport.expect((try? SpeechToTextServiceFactory.make(resolve(.gemini))) is GeminiTranscriptionService, "Gemini uses generateContent")
        TestSupport.expect((try? SpeechToTextServiceFactory.make(resolve(.xAI))) is XAITranscriptionService, "xAI uses /v1/stt")
        TestSupport.expect((try? SpeechToTextServiceFactory.make(resolve(.deepgram))) is DeepgramTranscriptionService, "Deepgram uses /v1/listen")
        for provider in [TranscriptionProvider.groq, .openAI, .custom] {
            TestSupport.expect((try? SpeechToTextServiceFactory.make(resolve(provider))) is TranscriptionService, "\(provider) uses audio/transcriptions")
        }
        do {
            _ = try SpeechToTextServiceFactory.make(resolve(.deepgram, key: " "))
            TestSupport.expect(false, "Missing provider key must fail")
        } catch {
            TestSupport.expect(error.localizedDescription.contains("Deepgram API key"), "Missing key error names the provider")
        }
        let noEndpoint = TranscriptionConfiguration.resolve(
            provider: .custom,
            providerAPIKey: "",
            customEndpoint: CustomEndpoint(baseURL: "", apiKey: ""),
            model: "m",
            language: nil
        )
        do {
            _ = try SpeechToTextServiceFactory.make(noEndpoint)
            TestSupport.expect(false, "Custom without an endpoint must fail")
        } catch {
            TestSupport.expect(error.localizedDescription.contains("custom transcription endpoint"), "Explains the missing endpoint")
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

    private static func testXAIRequest() {
        let request = XAITranscriptionService.request(apiKey: "k", boundary: "B")
        TestSupport.expectEqual(request.url?.absoluteString, "https://api.x.ai/v1/stt")
        TestSupport.expectEqual(request.httpMethod, "POST")
        TestSupport.expectEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer k")
        TestSupport.expectEqual(request.value(forHTTPHeaderField: "Content-Type"), "multipart/form-data; boundary=B")
        let body = String(decoding: XAITranscriptionService.multipartBody(
            audio: Data("AUDIO".utf8),
            fileName: "clip.wav",
            model: "grok-voice-transcribe-2.0",
            language: "fr",
            boundary: "B"
        ), as: UTF8.self)
        TestSupport.expect(body.contains("name=\"model\"\r\n\r\ngrok-voice-transcribe-2.0\r\n"), "Sends the model")
        TestSupport.expect(body.contains("name=\"language\"\r\n\r\nfr\r\n"), "Sends the language")
        TestSupport.expect(body.contains("filename=\"clip.wav\"\r\nContent-Type: audio/wav\r\n\r\nAUDIO\r\n--B--"), "Sends the audio")
        let fileIndex = body.range(of: "name=\"file\"")!.lowerBound
        TestSupport.expect(body.range(of: "name=\"model\"")!.lowerBound < fileIndex, "file must be the last field")
        TestSupport.expect(body.range(of: "name=\"language\"")!.lowerBound < fileIndex, "file must be the last field")
        let auto = String(decoding: XAITranscriptionService.multipartBody(audio: Data(), fileName: "a.wav", model: "m", language: nil, boundary: "B"), as: UTF8.self)
        TestSupport.expect(!auto.contains("name=\"language\""), "Auto-detect sends no language")
        TestSupport.expectEqual(try? XAITranscriptionService.parseTranscript(Data(#"{"text":" Synthetic words. ","duration":1.2}"#.utf8)), "Synthetic words.")
        TestSupport.expect((try? XAITranscriptionService.parseTranscript(Data(#"{"error":"x"}"#.utf8))) == nil, "Missing text is an error")
    }

    private static func testDeepgramRequest() {
        let request = DeepgramTranscriptionService.request(apiKey: "k", model: "nova-3", language: "de", contentType: "audio/wav")
        TestSupport.expectEqual(request.url?.absoluteString, "https://api.deepgram.com/v1/listen?model=nova-3&smart_format=true&language=de")
        TestSupport.expectEqual(request.httpMethod, "POST")
        TestSupport.expectEqual(request.value(forHTTPHeaderField: "Authorization"), "Token k")
        TestSupport.expectEqual(request.value(forHTTPHeaderField: "Content-Type"), "audio/wav")
        let auto = DeepgramTranscriptionService.request(apiKey: "k", model: "nova-3", language: nil, contentType: "audio/wav")
        TestSupport.expectEqual(auto.url?.absoluteString, "https://api.deepgram.com/v1/listen?model=nova-3&smart_format=true&detect_language=true")
        let response = #"{"metadata":{},"results":{"channels":[{"alternatives":[{"transcript":" Synthetic words. ","confidence":0.9}]}]}}"#
        TestSupport.expectEqual(try? DeepgramTranscriptionService.parseTranscript(Data(response.utf8)), "Synthetic words.")
        let silent = #"{"results":{"channels":[{"alternatives":[{"transcript":""}]}]}}"#
        TestSupport.expectEqual(try? DeepgramTranscriptionService.parseTranscript(Data(silent.utf8)), "")
        TestSupport.expect((try? DeepgramTranscriptionService.parseTranscript(Data(#"{"err_code":"x"}"#.utf8))) == nil, "Missing results is an error")
    }
}
