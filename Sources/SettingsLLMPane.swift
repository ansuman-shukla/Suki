import SwiftUI

struct LLMSettingsPane: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        SettingsPane(title: "LLM") {
            SettingsGroup("Provider") {
                SettingsRow("Provider", detail: "Cleans up transcripts, runs Edit Mode, and reads screenshot context.") {
                    LLMProviderMenu(selection: $appState.llmProvider)
                }
                SettingsBlock { LLMCredentialFields() }
            }
            SettingsGroup("Models") {
                SettingsBlock { LLMModelFields() }
                SettingsBlock(
                    "Test models",
                    detail: "Sends a one-line test prompt to each model above, so you can check a new model ID before dictating."
                ) {
                    LLMModelTestButton()
                }
            }
            SettingsGroup("Cleanup") {
                SettingsToggleRow(
                    "Preserve exact wording",
                    detail: "When on, \(AppName.displayName) skips the LLM cleanup step and pastes the transcript verbatim — filler words, informal phrasing, and explicit language are all preserved. Voice macros and Edit Mode still run. If Output Language is set, the transcript is still translated into that language, but the translation is literal: no rewording, no filler removal, no reformatting.",
                    isOn: $appState.preserveExactWording
                )
            }
            EditModeSettingsGroup()
        }
    }
}

struct LLMProviderMenu: View {
    @Binding var selection: LLMProvider

    var body: some View {
        SettingsMenuButton(title: selection.displayName) {
            Picker("LLM Provider", selection: $selection) {
                ForEach(LLMProvider.allCases) { provider in
                    Text(provider.displayName).tag(provider)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        }
    }
}

/// Key field for a preset provider, or URL and key for a custom endpoint.
struct LLMCredentialFields: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        if let credential = appState.llmProvider.credential {
            ProviderAPIKeyField(provider: credential) { key in
                await APIKeyValidator.validate(key, for: credential)
            }
            .id(credential)
        } else {
            CustomEndpointFields(
                savedBaseURL: appState.customLLMBaseURL,
                savedAPIKey: appState.customLLMAPIKey
            ) { baseURL, apiKey in
                appState.setCustomLLMEndpoint(baseURL: baseURL, apiKey: apiKey)
            }
        }
    }
}

private struct LLMModelTestButton: View {
    private enum Outcome: Equatable {
        case passed
        case failed(String)
    }

    @EnvironmentObject var appState: AppState
    @State private var isTesting = false
    @State private var outcomes: [(model: String, outcome: Outcome)] = []

    private var models: [String] {
        var seen = Set<String>()
        return [appState.postProcessingModel, appState.postProcessingFallbackModel, appState.contextModel]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(isTesting ? "Testing..." : "Test models", action: runTests)
                .buttonStyle(.settings)
                .disabled(isTesting || models.isEmpty)
            ForEach(outcomes, id: \.model) { result in
                switch result.outcome {
                case .passed:
                    Label("\(result.model) works", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.caption)
                case .failed(let message):
                    Label("\(result.model): \(message)", systemImage: "xmark.circle.fill")
                        .foregroundStyle(.red)
                        .font(.caption)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .onChange(of: appState.llmProvider) { _ in outcomes = [] }
    }

    private func runTests() {
        let configuration = appState.llmConfiguration
        let models = models
        isTesting = true
        outcomes = []
        Task { @MainActor in
            for model in models {
                let outcome: Outcome
                switch await LLMModelTest.run(model: model, configuration: configuration) {
                case .success: outcome = .passed
                case .failure(let error): outcome = .failed(error.localizedDescription)
                }
                guard appState.llmConfiguration == configuration else { break }
                outcomes.append((model, outcome))
            }
            isTesting = false
        }
    }
}

struct EditModeSettingsGroup: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
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
