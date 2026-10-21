import SwiftUI

struct LiveTranscriptionSettingsView: View {
    private enum TestState: Equatable {
        case idle
        case testing
        case succeeded
        case failed(String)
    }

    @EnvironmentObject var appState: AppState
    @State private var modelDraft = ""
    @State private var testState: TestState = .idle

    private var provider: LiveTranscriptionProvider { appState.liveTranscriptionProvider }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("Transcribe while I speak", isOn: $appState.realtimeStreamingEnabled)
            Text("Streams audio over a WebSocket so text is ready the moment you stop. Falls back to the regular upload if the live connection fails.")
                .font(.caption)
                .foregroundStyle(.secondary)

            SukiSegmentedPicker(
                "Provider",
                selection: $appState.liveTranscriptionProvider,
                options: Array(LiveTranscriptionProvider.allCases),
                label: \.displayName
            )

            credentialsSection

            ModelDropdownView(
                title: "Live Model",
                subtitle: provider == .custom
                    ? "Leave empty for providers that supply a server default."
                    : "Use a live model so words arrive while you speak.",
                predefinedModels: provider.suggestedModels,
                defaultModel: provider.defaultModel.isEmpty ? "Server default" : provider.defaultModel,
                textDraft: $modelDraft,
                onCommit: commitModel,
                onReset: {
                    modelDraft = provider.defaultModel
                    appState.realtimeStreamingModel = provider.defaultModel
                }
            )
            .id(provider)

            Divider()

            Toggle("Type text live into the focused app", isOn: $appState.liveTypingEnabled)
                .disabled(!appState.realtimeStreamingEnabled)
            Text("Words are typed as you speak, exactly as heard. Cleanup, voice macros, and the press-enter command are skipped. Edit Mode is unaffected.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .onAppear(perform: loadDrafts)
        .onChange(of: appState.liveTranscriptionProvider) { _ in loadDrafts() }
        .onChange(of: appState.realtimeStreamingModel) { value in
            modelDraft = value
        }
    }

    @ViewBuilder
    private var credentialsSection: some View {
        if let credential = provider.credential {
            ProviderAPIKeyField(provider: credential) { key in
                commitModel()
                guard let configuration = appState.liveTranscriptionConfiguration(provider: provider, apiKey: key) else {
                    return .failure(RealtimeTranscriptionError.connectionFailed("Enter an API key first."))
                }
                return await LiveTranscriptionConnectionTest.run(configuration)
            }
        } else {
            customEndpointSection
        }
    }

    private var customEndpointSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Uses the Transcription API URL and key from API Key > Advanced Provider Settings, over its OpenAI-compatible /v1/realtime WebSocket.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button(testState == .testing ? "Testing..." : "Test Connection", action: testCustomEndpoint)
                .disabled(testState == .testing)

            switch testState {
            case .succeeded:
                Label("Connected to \(provider.displayName)", systemImage: "checkmark.circle.fill")
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
    }

    private func loadDrafts() {
        modelDraft = appState.realtimeStreamingModel
        testState = .idle
    }

    private func commitModel() {
        let trimmed = modelDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        modelDraft = trimmed
        guard appState.realtimeStreamingModel != trimmed else { return }
        appState.realtimeStreamingModel = trimmed
    }

    private func testCustomEndpoint() {
        commitModel()
        guard let configuration = appState.liveTranscriptionConfiguration(provider: .custom) else {
            testState = .failed("Set a transcription API URL first.")
            return
        }
        testState = .testing
        Task { @MainActor in
            let result = await LiveTranscriptionConnectionTest.run(configuration)
            guard appState.liveTranscriptionProvider == .custom, testState == .testing else { return }
            switch result {
            case .success: testState = .succeeded
            case .failure(let error): testState = .failed(error.localizedDescription)
            }
        }
    }
}
