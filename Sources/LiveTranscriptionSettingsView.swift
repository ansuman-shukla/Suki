import SwiftUI

struct LiveTranscriptionSettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var modelDraft = ""

    private var provider: LiveTranscriptionProvider { appState.liveTranscriptionProvider }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("Transcribe while I speak", isOn: $appState.realtimeStreamingEnabled)
            Text("Streams audio over a WebSocket so text is ready the moment you stop. Falls back to the regular upload if the live connection fails.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Text("Provider")
                    .font(.caption.weight(.semibold))
                Spacer()
                SettingsPickerMenu(
                    "Live Transcription Provider",
                    selection: $appState.liveTranscriptionProvider,
                    options: LiveTranscriptionProvider.allCases,
                    label: \.displayName
                )
            }

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

            AsyncTestButton(title: "Test connection", successMessage: "Connected to \(provider.displayName)") {
                commitModel()
                guard let configuration = appState.liveTranscriptionConfiguration(provider: provider) else {
                    return .failure(RealtimeTranscriptionError.connectionFailed(
                        provider == .custom ? "Save a custom endpoint first." : "Save an API key first."
                    ))
                }
                return await LiveTranscriptionConnectionTest.run(configuration)
            }
            .id(provider)

            Divider()

            Toggle("Type text live into the focused app", isOn: $appState.liveTypingEnabled)
                .disabled(!appState.realtimeStreamingEnabled)
            Text("Words are typed as you speak, exactly as heard. Cleanup, voice macros, and the press-enter command are skipped. Edit Mode is unaffected.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .onAppear { modelDraft = appState.realtimeStreamingModel }
        .onChange(of: appState.realtimeStreamingModel) { modelDraft = $0 }
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
            .id(credential)
        } else {
            Text("Any OpenAI-compatible /v1/realtime WebSocket. Shares its endpoint with Custom upload transcription.")
                .font(.caption)
                .foregroundStyle(.secondary)
            CustomEndpointFields(
                savedBaseURL: appState.transcriptionAPIURL,
                savedAPIKey: appState.transcriptionAPIKey
            ) { baseURL, apiKey in
                appState.setCustomTranscriptionEndpoint(baseURL: baseURL, apiKey: apiKey)
            }
        }
    }

    private func commitModel() {
        let trimmed = modelDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        modelDraft = trimmed
        guard appState.realtimeStreamingModel != trimmed else { return }
        appState.realtimeStreamingModel = trimmed
    }
}
