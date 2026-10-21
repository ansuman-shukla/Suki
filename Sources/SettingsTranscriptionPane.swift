import SwiftUI

struct TranscriptionSettingsPane: View {
    @EnvironmentObject var appState: AppState
    @State private var apiDraft = APIConfigurationDraft()
    @State private var advancedProviderSettingsExpanded = false
    @State private var isValidatingKey = false
    @State private var keyValidationError: String?
    @State private var successfulAPIConfiguration: ValidatedAPIConfiguration?

    var body: some View {
        SettingsPane(title: "Transcription") {
            apiKeyGroup
            SettingsGroup("Transcription") {
                SettingsBlock { TranscriptionSettingsView() }
            }
            SettingsGroup("Live transcription") {
                SettingsBlock { LiveTranscriptionSettingsView() }
            }
            SettingsGroup("Cleanup") {
                SettingsToggleRow(
                    "Preserve exact wording",
                    detail: "When on, \(AppName.displayName) skips the LLM cleanup step and pastes the transcript verbatim — filler words, informal phrasing, and explicit language are all preserved. Voice macros and Edit Mode still run. If Output Language is set, the transcript is still translated into that language, but the translation is literal: no rewording, no filler removal, no reformatting.",
                    isOn: $appState.preserveExactWording
                )
            }
            editModeGroup
        }
        .onAppear {
            apiDraft.present(appState.committedAPIConfiguration)
            isValidatingKey = false
            keyValidationError = nil
            successfulAPIConfiguration = nil
        }
        .onDisappear {
            apiDraft.dismiss()
        }
        .onChange(of: appState.committedAPIConfiguration) { saved in
            apiDraft.reconcile(saved)
            keyValidationError = nil
            if successfulAPIConfiguration != saved {
                successfulAPIConfiguration = nil
            }
        }
        .onChange(of: apiDraft.configuration) { value in
            keyValidationError = nil
            if successfulAPIConfiguration != value {
                successfulAPIConfiguration = nil
            }
        }
    }

    // MARK: API Key

    private var apiKeyGroup: some View {
        SettingsGroup("API key") {
            SettingsBlock(
                "API key",
                detail: "\(AppName.displayName) uses the configured transcription model with your selected OpenAI-compatible provider."
            ) {
                HStack(spacing: 8) {
                    SecureField("Enter your Groq API key", text: $apiDraft.apiKey)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                        .disabled(isValidatingKey)

                    Button(isValidatingKey ? "Validating..." : "Save") {
                        validateAndSaveKey()
                    }
                    .buttonStyle(.settingsProminent)
                    .disabled(apiDraft.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isValidatingKey)
                }

                if let error = keyValidationError {
                    Label(error, systemImage: "xmark.circle.fill")
                        .font(SukiFont.ui(12.5))
                        .foregroundStyle(Theme.destructive)
                } else if apiDraft.showsSavedSuccess(successfulAPIConfiguration, committed: appState.committedAPIConfiguration) {
                    Label("API key saved", systemImage: "checkmark.circle.fill")
                        .settingsCaptionStyle()
                }
            }
            SettingsRow("Advanced provider settings", detail: apiDraft.baseURL) {
                Button(advancedProviderSettingsExpanded ? "Hide" : "Change") {
                    advancedProviderSettingsExpanded.toggle()
                }
                .buttonStyle(.settings)
            }
            if advancedProviderSettingsExpanded {
                SettingsBlock {
                    ProviderSettingsFields(
                        apiBaseURLInput: $apiDraft.baseURL,
                        transcriptionAPIURLInput: $apiDraft.transcriptionAPIURL,
                        transcriptionAPIKeyInput: $apiDraft.transcriptionAPIKey,
                        showsModelDescription: false
                    )
                }
            }
        }
    }

    private func validateAndSaveKey() {
        guard !isValidatingKey else { return }
        let submission = apiDraft.submission
        isValidatingKey = true
        keyValidationError = nil
        successfulAPIConfiguration = nil

        Task { @MainActor in
            var accepted: ValidatedAPIConfiguration?
            let valid = await APIConfigurationSaveFlow.validateAndApply(
                apiKey: submission.configuration.apiKey,
                baseURL: submission.configuration.baseURL,
                transcriptionAPIURL: submission.configuration.transcriptionAPIURL,
                transcriptionAPIKey: submission.configuration.transcriptionAPIKey
            ) { configuration in
                if apiDraft.accept(configuration, for: submission) {
                    accepted = configuration
                }
                appState.updateAPIConfiguration(
                    apiKey: configuration.apiKey,
                    baseURL: configuration.baseURL,
                    transcriptionAPIURL: configuration.transcriptionAPIURL,
                    transcriptionAPIKey: configuration.transcriptionAPIKey
                )
            }
            guard apiDraft.isCurrent(submission) else { return }
            isValidatingKey = false
            if valid, let accepted, apiDraft.configuration == accepted,
               appState.committedAPIConfiguration == accepted {
                successfulAPIConfiguration = accepted
            } else if !valid && apiDraft.matches(submission) {
                keyValidationError = "Validation failed. Please check your API key and provider settings, then try again."
            }
        }
    }

    // MARK: Edit Mode

    private var editModeGroup: some View {
        SettingsGroup("Edit mode") {
            SettingsToggleRow(
                "Enable Edit Mode",
                detail: "Transform highlighted text with a spoken instruction instead of dictating over it.",
                isOn: Binding(
                    get: { appState.isCommandModeEnabled },
                    set: { newValue in
                        _ = appState.setCommandModeEnabled(newValue)
                    }
                )
            )
            Group {
                SettingsRow("Invocation style", detail: invocationStyleDetail) {
                    SukiSegmentedPicker(
                        "Invocation Style",
                        selection: Binding(
                            get: { appState.commandModeStyle },
                            set: { newValue in
                                _ = appState.setCommandModeStyle(newValue)
                            }
                        ),
                        options: Array(CommandModeStyle.allCases),
                        label: \.title
                    )
                    .fixedSize()
                    .disabled(!appState.isCommandModeEnabled)
                }
                if appState.commandModeStyle == .manual {
                    SettingsRow("Extra modifier", detail: appState.commandModeManualModifier.title) {
                        SettingsMenuButton {
                            Picker("Extra Modifier", selection: Binding(
                                get: { appState.commandModeManualModifier },
                                set: { newValue in
                                    _ = appState.setCommandModeManualModifier(newValue)
                                }
                            )) {
                                ForEach(CommandModeManualModifier.allCases) { modifier in
                                    Text(modifier.title).tag(modifier)
                                }
                            }
                            .pickerStyle(.inline)
                            .labelsHidden()
                        }
                        .disabled(!appState.isCommandModeEnabled || appState.commandModeStyle != .manual)
                    }
                }
            }
            .opacity(appState.isCommandModeEnabled ? 1 : 0.5)
            if let validationMessage = appState.commandModeManualModifierValidationMessage {
                SettingsBlock {
                    Label(validationMessage, systemImage: "xmark.circle.fill")
                        .font(SukiFont.ui(12.5))
                        .foregroundStyle(Theme.destructive)
                }
            }
        }
    }

    private var invocationStyleDetail: String {
        switch appState.commandModeStyle {
        case .automatic:
            return "If text is selected, your normal dictation shortcut transforms the selection instead of dictating over it."
        case .manual:
            return "Hold the extra modifier together with your normal dictation shortcut to transform selected text."
        }
    }
}
