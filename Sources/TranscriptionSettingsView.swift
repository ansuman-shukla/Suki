import SwiftUI

struct TranscriptionSettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var modelDraft = ""

    private var provider: TranscriptionProvider { appState.transcriptionProvider }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Where your recording is sent after you stop speaking. Live transcription uses this as its fallback.")
                .font(.caption)
                .foregroundStyle(.secondary)

            SukiSegmentedPicker(
                "Provider",
                selection: $appState.transcriptionProvider,
                options: Array(TranscriptionProvider.allCases),
                label: \.displayName
            )

            if let credential = provider.credential {
                ProviderAPIKeyField(provider: credential) { key in
                    await APIKeyValidator.validate(key, for: credential)
                }
            } else {
                Text("Uses the API key and endpoint from API Key settings (Groq by default).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ModelDropdownView(
                title: "Transcription Model",
                subtitle: "Used for speech-to-text transcription.",
                predefinedModels: provider.suggestedModels,
                defaultModel: provider.defaultModel,
                textDraft: $modelDraft,
                onCommit: commitModel,
                onReset: {
                    modelDraft = provider.defaultModel
                    appState.transcriptionModel = provider.defaultModel
                }
            )
            .id(provider)

            VStack(alignment: .leading, spacing: 6) {
                Text("Transcription Language")
                    .font(.caption.weight(.semibold))
                Picker("", selection: $appState.transcriptionLanguage) {
                    ForEach(AppState.transcriptionLanguageOptions, id: \.code) { option in
                        Text(option.name).tag(option.code)
                    }
                }
                .accessibilityLabel("Transcription Language")
                .labelsHidden()
                Text("Hint to the transcription model. Auto-detect works for most users. Pick a specific language if you see wrong-script characters (for example Chinese) appear in your output.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear { modelDraft = appState.transcriptionModel }
        .onChange(of: appState.transcriptionModel) { modelDraft = $0 }
    }

    private func commitModel() {
        let trimmed = modelDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        modelDraft = trimmed
        guard appState.transcriptionModel != trimmed else { return }
        appState.transcriptionModel = trimmed
    }
}
