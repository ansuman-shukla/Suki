import Foundation

enum APIProviderTests {
    static func run() async {
        testStorageAccounts()
        testValidationRequests()
        await testValidation()
    }

    private static func testStorageAccounts() {
        // Keys saved before providers were shared must keep loading.
        TestSupport.expectEqual(APIProvider.groq.apiKeyStorageAccount, "groq_api_key")
        TestSupport.expectEqual(APIProvider.openAI.apiKeyStorageAccount, "openai_api_key")
        TestSupport.expectEqual(APIProvider.gemini.apiKeyStorageAccount, "gemini_api_key")
        TestSupport.expectEqual(
            Set(APIProvider.allCases.map(\.apiKeyStorageAccount)).count,
            APIProvider.allCases.count
        )
    }

    private static func testValidationRequests() {
        let expected: [APIProvider: (url: String, header: String, value: String)] = [
            .groq: ("https://api.groq.com/openai/v1/models", "Authorization", "Bearer k"),
            .openAI: ("https://api.openai.com/v1/models", "Authorization", "Bearer k"),
            .xAI: ("https://api.x.ai/v1/models", "Authorization", "Bearer k"),
            .cerebras: ("https://api.cerebras.ai/v1/models", "Authorization", "Bearer k"),
            .anthropic: ("https://api.anthropic.com/v1/models", "x-api-key", "k"),
            .gemini: ("https://generativelanguage.googleapis.com/v1beta/models", "x-goog-api-key", "k"),
            .deepgram: ("https://api.deepgram.com/v1/projects", "Authorization", "Token k"),
        ]
        TestSupport.expectEqual(expected.count, APIProvider.allCases.count)
        for (provider, want) in expected {
            let request = provider.keyValidationRequest(apiKey: "k")
            TestSupport.expectEqual(request.url?.absoluteString, want.url)
            TestSupport.expectEqual(request.value(forHTTPHeaderField: want.header), want.value)
            TestSupport.expectEqual(request.httpMethod, "GET")
        }
        TestSupport.expectEqual(
            APIProvider.anthropic.keyValidationRequest(apiKey: "k").value(forHTTPHeaderField: "anthropic-version"),
            "2023-06-01"
        )
        TestSupport.expect(
            APIProvider.anthropic.keyValidationRequest(apiKey: "k").value(forHTTPHeaderField: "Authorization") == nil,
            "Anthropic's models list rejects Bearer auth"
        )
    }

    private static func testValidation() async {
        func respond(_ status: Int) -> @Sendable (URLRequest) async throws -> (Data, URLResponse) {
            { request in
                TestSupport.expectEqual(request.value(forHTTPHeaderField: "x-goog-api-key"), "synthetic-key")
                return (Data(), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
            }
        }
        if case .failure = await APIKeyValidator.validate(" synthetic-key ", for: .gemini, transport: respond(200)) {
            TestSupport.expect(false, "200 means the trimmed key works")
        }
        guard case .failure(let rejected) = await APIKeyValidator.validate("synthetic-key", for: .gemini, transport: respond(401)) else {
            return TestSupport.expect(false, "Non-200 means the key is rejected")
        }
        TestSupport.expectEqual(rejected.localizedDescription, "Gemini rejected this API key.")
        let blank = await APIKeyValidator.validate("  ", for: .gemini) { _ in
            TestSupport.expect(false, "Blank keys are never sent")
            throw URLError(.cancelled)
        }
        if case .success = blank { TestSupport.expect(false, "Blank keys fail") }
        guard case .failure(let offline) = await APIKeyValidator.validate("k", for: .xAI, transport: { _ in
            throw URLError(.notConnectedToInternet)
        }) else {
            return TestSupport.expect(false, "Network errors fail validation")
        }
        TestSupport.expect(offline.localizedDescription.contains("Couldn't reach xAI"), "Network errors say the provider was unreachable")
    }
}
