import SwiftUI

/// First-run step where the user picks an LLM and a transcription provider
/// and saves a working key for each. Nothing is preselected on a fresh
/// install; a provider sharing one key (for example Groq) asks for it once.
struct SetupProvidersStep: View {
    @EnvironmentObject var appState: AppState
    @Binding var llmChoice: LLMProvider?
    @Binding var transcriptionChoice: TranscriptionProvider?

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Image(systemName: "key.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.blue)

                Text("Providers")
                    .font(.title)
                    .fontWeight(.bold)

                Text("Pick where \(AppName.displayName) sends your words. If one provider does both, its key is saved once and used for both.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                section(
                    title: "Transcription",
                    detail: "Turns your speech into text.",
                    picker: Picker("Transcription provider", selection: transcriptionBinding) {
                        Text("Choose a provider").tag(TranscriptionProvider?.none)
                        ForEach(TranscriptionProvider.allCases) { provider in
                            Text(provider.displayName).tag(TranscriptionProvider?.some(provider))
                        }
                    }
                ) {
                    if transcriptionChoice != nil {
                        TranscriptionCredentialFields()
                    }
                }

                section(
                    title: "LLM",
                    detail: "Cleans up the transcript and runs Edit Mode.",
                    picker: Picker("LLM provider", selection: llmBinding) {
                        Text("Choose a provider").tag(LLMProvider?.none)
                        ForEach(LLMProvider.allCases) { provider in
                            Text(provider.displayName).tag(LLMProvider?.some(provider))
                        }
                    }
                ) {
                    if llmChoice != nil {
                        LLMCredentialFields()
                    }
                }

                Text("Models and live transcription can be changed later in Settings.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var llmBinding: Binding<LLMProvider?> {
        Binding(
            get: { llmChoice },
            set: { choice in
                llmChoice = choice
                if let choice { appState.llmProvider = choice }
            }
        )
    }

    private var transcriptionBinding: Binding<TranscriptionProvider?> {
        Binding(
            get: { transcriptionChoice },
            set: { choice in
                transcriptionChoice = choice
                if let choice { appState.transcriptionProvider = choice }
            }
        )
    }

    private func section<P: View, Content: View>(
        title: String,
        detail: String,
        picker: P,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                picker
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .fixedSize()
            }
            content()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.55))
        )
    }
}

/// Key field for a transcription provider, or the custom endpoint.
struct TranscriptionCredentialFields: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        if let credential = appState.transcriptionProvider.credential {
            ProviderAPIKeyField(provider: credential) { key in
                await APIKeyValidator.validate(key, for: credential)
            }
            .id(credential)
        } else {
            CustomEndpointFields(
                savedBaseURL: appState.transcriptionAPIURL,
                savedAPIKey: appState.transcriptionAPIKey
            ) { baseURL, apiKey in
                appState.setCustomTranscriptionEndpoint(baseURL: baseURL, apiKey: apiKey)
            }
        }
    }
}
