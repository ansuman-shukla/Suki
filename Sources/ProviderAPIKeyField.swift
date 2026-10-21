import SwiftUI

/// Edits a provider key shared by every feature that uses that provider.
/// Like the main API key, a key is saved only after the provider accepts it.
struct ProviderAPIKeyField: View {
    private enum TestState: Equatable {
        case idle
        case testing
        case succeeded
        case failed(String)
    }

    @EnvironmentObject var appState: AppState
    let provider: APIProvider
    let test: (String) async -> Result<Void, Error>

    @State private var draft = ""
    @State private var testState: TestState = .idle

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(provider.displayName) API Key")
                .font(.caption.weight(.semibold))
            HStack(spacing: 8) {
                SecureField("Enter your \(provider.displayName) API key", text: $draft)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .disabled(testState == .testing)
                Button(testState == .testing ? "Testing..." : "Save & Test", action: saveAndTest)
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || testState == .testing)
            }
            switch testState {
            case .succeeded:
                Label("\(provider.displayName) key saved", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.caption)
            case .failed(let message):
                Label(message, systemImage: "xmark.circle.fill")
                    .foregroundStyle(.red)
                    .font(.caption)
            case .idle, .testing:
                EmptyView()
            }
        }
        .onAppear(perform: loadDraft)
        .onChange(of: provider) { _ in loadDraft() }
        // The same key can be edited from another card on this page.
        .onChange(of: appState.providerAPIKeys[provider]) { draft = $0 ?? "" }
    }

    private func loadDraft() {
        draft = appState.providerAPIKeys[provider] ?? ""
        testState = .idle
    }

    private func saveAndTest() {
        let testedProvider = provider
        let key = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        testState = .testing
        Task { @MainActor in
            let result = await test(key)
            guard provider == testedProvider, testState == .testing else { return }
            switch result {
            case .success:
                appState.setProviderAPIKey(key, for: testedProvider)
                testState = .succeeded
            case .failure(let error):
                testState = .failed(error.localizedDescription)
            }
        }
    }
}

/// Edits a custom OpenAI-compatible endpoint. Saved only after the
/// endpoint lists its models with the given key.
struct CustomEndpointFields: View {
    private enum TestState: Equatable {
        case idle
        case testing
        case succeeded
        case failed(String)
    }

    let savedBaseURL: String
    let savedAPIKey: String
    let save: (_ baseURL: String, _ apiKey: String) -> Void

    @State private var baseURL = ""
    @State private var apiKey = ""
    @State private var testState: TestState = .idle

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Base URL")
                .font(.caption.weight(.semibold))
            TextField("https://api.example.com/v1", text: $baseURL)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
            Text("API Key")
                .font(.caption.weight(.semibold))
            HStack(spacing: 8) {
                SecureField("Optional for local servers", text: $apiKey)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                Button(testState == .testing ? "Testing..." : "Save & Test", action: saveAndTest)
                    .disabled(baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || testState == .testing)
            }
            .disabled(testState == .testing)
            switch testState {
            case .succeeded:
                Label("Endpoint saved", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.caption)
            case .failed(let message):
                Label(message, systemImage: "xmark.circle.fill")
                    .foregroundStyle(.red)
                    .font(.caption)
            case .idle, .testing:
                EmptyView()
            }
        }
        .onAppear {
            baseURL = savedBaseURL
            apiKey = savedAPIKey
        }
        .onChange(of: savedBaseURL) { baseURL = $0 }
        .onChange(of: savedAPIKey) { apiKey = $0 }
    }

    private func saveAndTest() {
        let url = LLMProvider.normalizedBaseURL(baseURL)
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        testState = .testing
        Task { @MainActor in
            switch await CustomEndpointValidator.validate(baseURL: url, apiKey: key) {
            case .success:
                save(url, key)
                baseURL = url
                testState = .succeeded
            case .failure(let error):
                testState = .failed(error.localizedDescription)
            }
        }
    }
}

/// Runs a live check and shows whether it passed.
struct AsyncTestButton: View {
    private enum TestState: Equatable {
        case idle
        case testing
        case succeeded
        case failed(String)
    }

    let title: String
    let successMessage: String
    let run: () async -> Result<Void, Error>

    @State private var testState: TestState = .idle

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button(testState == .testing ? "Testing..." : title) {
                testState = .testing
                Task { @MainActor in
                    switch await run() {
                    case .success: testState = .succeeded
                    case .failure(let error): testState = .failed(error.localizedDescription)
                    }
                }
            }
            .disabled(testState == .testing)
            switch testState {
            case .succeeded:
                Label(successMessage, systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.caption)
            case .failed(let message):
                Label(message, systemImage: "xmark.circle.fill")
                    .foregroundStyle(.red)
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
            case .idle, .testing:
                EmptyView()
            }
        }
    }
}
