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
