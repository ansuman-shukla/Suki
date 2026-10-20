import SwiftUI

private let iso8601DayFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter
}()

struct PromptsSettingsPane: View {
    @EnvironmentObject var appState: AppState
    @State private var customSystemPromptInput: String = ""
    @State private var customContextPromptInput: String = ""
    @FocusState private var customSystemPromptFocused: Bool
    @FocusState private var customContextPromptFocused: Bool
    @State private var showDefaultSystemPrompt = false
    @State private var showDefaultContextPrompt = false

    // System prompt test state
    @State private var systemTestInput: String = "Um, so I was like, thinking we should uh, refactor the authentication module, you know?"
    @State private var systemTestRunning = false
    @State private var systemTestOutput: String? = nil
    @State private var systemTestError: String? = nil
    @State private var systemTestPrompt: String? = nil

    // Context prompt test state
    @State private var contextTestRunning = false
    @State private var contextTestOutput: String? = nil
    @State private var contextTestError: String? = nil
    @State private var contextTestPrompt: String? = nil

    private var hasAPIKey: Bool {
        !appState.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        SettingsPane(title: "Prompts") {
            systemPromptGroup
            SettingsGroup("Instruction guard") {
                SettingsToggleRow(
                    "Prevent dictated prompts from being executed",
                    detail: "When enabled, Suki retries or falls back to the literal transcript if post-processing looks like it answered the dictated text instead of cleaning it.",
                    isOn: $appState.instructionExecutionGuardEnabled
                )
            }
            contextPromptGroup
        }
        .onAppear {
            customSystemPromptInput = appState.customSystemPrompt.isEmpty
                ? PostProcessingService.defaultSystemPrompt
                : appState.customSystemPrompt
            customContextPromptInput = appState.customContextPrompt.isEmpty
                ? AppContextService.defaultContextPrompt
                : appState.customContextPrompt
        }
        .onDisappear {
            commitCustomSystemPrompt()
            commitCustomContextPrompt()
        }
    }

    private func commitCustomSystemPrompt() {
        let trimmed = customSystemPromptInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let defaultTrimmed = PostProcessingService.defaultSystemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed == defaultTrimmed || trimmed.isEmpty {
            if !appState.customSystemPrompt.isEmpty {
                appState.customSystemPrompt = ""
                appState.customSystemPromptLastModified = ""
            }
        } else if appState.customSystemPrompt != trimmed {
            appState.customSystemPrompt = trimmed
            appState.customSystemPromptLastModified = iso8601DayFormatter.string(from: Date())
        }
    }

    private func commitCustomContextPrompt() {
        let trimmed = customContextPromptInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let defaultTrimmed = AppContextService.defaultContextPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed == defaultTrimmed || trimmed.isEmpty {
            if !appState.customContextPrompt.isEmpty {
                appState.customContextPrompt = ""
                appState.customContextPromptLastModified = ""
            }
        } else if appState.customContextPrompt != trimmed {
            appState.customContextPrompt = trimmed
            appState.customContextPromptLastModified = iso8601DayFormatter.string(from: Date())
        }
    }

    // MARK: System Prompt

    private var systemPromptGroup: some View {
        let isCustom = !appState.customSystemPrompt.isEmpty
        let hasNewerDefault = isCustom
            && !appState.customSystemPromptLastModified.isEmpty
            && appState.customSystemPromptLastModified < PostProcessingService.defaultSystemPromptDate

        return SettingsGroup("System prompt") {
            if hasNewerDefault {
                newerDefaultRow(
                    onView: { showDefaultSystemPrompt.toggle() },
                    onSwitch: {
                        customSystemPromptInput = PostProcessingService.defaultSystemPrompt
                        appState.customSystemPrompt = ""
                        appState.customSystemPromptLastModified = ""
                    }
                )
            }
            SettingsBlock(
                "Cleanup prompt",
                detail: "\(isCustom ? "Using custom prompt" : "Using default"). Controls how raw transcriptions are cleaned up."
            ) {
                if showDefaultSystemPrompt {
                    defaultPromptViewer("Default System Prompt", text: PostProcessingService.defaultSystemPrompt) {
                        showDefaultSystemPrompt = false
                    }
                }
                promptEditor($customSystemPromptInput, focus: $customSystemPromptFocused, minHeight: 120, maxHeight: 200)
                    .onChange(of: customSystemPromptFocused) { focused in
                        if !focused { commitCustomSystemPrompt() }
                    }
                if isCustom {
                    resetButton {
                        customSystemPromptInput = PostProcessingService.defaultSystemPrompt
                        appState.customSystemPrompt = ""
                        appState.customSystemPromptLastModified = ""
                    }
                }
            }
            SettingsBlock("Test system prompt", detail: "Enter sample text to see how the current prompt cleans it up.") {
                promptEditor($systemTestInput, minHeight: 60, maxHeight: 100)
                testButton("Test System Prompt", isRunning: systemTestRunning, action: runSystemPromptTest)
                    .disabled(systemTestRunning || !hasAPIKey || systemTestInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                testResults(error: systemTestError, output: systemTestOutput, prompt: systemTestPrompt)
            }
        }
    }

    private func runSystemPromptTest() {
        commitCustomSystemPrompt()
        systemTestRunning = true
        systemTestOutput = nil
        systemTestError = nil
        systemTestPrompt = nil

        let service = PostProcessingService(
            apiKey: appState.apiKey,
            baseURL: appState.apiBaseURL,
            preferredModel: appState.postProcessingModel,
            preferredFallbackModel: appState.postProcessingFallbackModel,
            instructionExecutionGuardEnabled: appState.instructionExecutionGuardEnabled
        )
        let input = systemTestInput
        let customPrompt = appState.customSystemPrompt
        let vocabulary = appState.customVocabulary

        let context = AppContext(
            appName: "\(AppName.displayName) Settings",
            bundleIdentifier: "com.ansumanshukla.suki",
            windowTitle: "System Prompt Test",
            selectedText: nil,
            currentActivity: "User is testing the system prompt in \(AppName.displayName) settings.",
            contextSystemPrompt: nil,
            contextPrompt: nil,
            screenshotDataURL: nil,
            screenshotMimeType: nil,
            screenshotError: nil
        )

        Task {
            do {
                let result = try await service.postProcess(
                    transcript: input,
                    context: context,
                    customVocabulary: vocabulary,
                    customSystemPrompt: customPrompt
                )
                await MainActor.run {
                    systemTestOutput = result.transcript
                    systemTestPrompt = result.prompt
                    systemTestRunning = false
                }
            } catch {
                await MainActor.run {
                    systemTestError = error.localizedDescription
                    systemTestRunning = false
                }
            }
        }
    }

    // MARK: Context Prompt

    private var contextPromptGroup: some View {
        let isCustom = !appState.customContextPrompt.isEmpty
        let hasNewerDefault = isCustom
            && !appState.customContextPromptLastModified.isEmpty
            && appState.customContextPromptLastModified < AppContextService.defaultContextPromptDate
        let isDefaultDimension = appState.contextScreenshotMaxDimension == AppState.defaultContextScreenshotMaxDimension

        return SettingsGroup("Context prompt") {
            if hasNewerDefault {
                newerDefaultRow(
                    onView: { showDefaultContextPrompt.toggle() },
                    onSwitch: {
                        customContextPromptInput = AppContextService.defaultContextPrompt
                        appState.customContextPrompt = ""
                        appState.customContextPromptLastModified = ""
                    }
                )
            }
            SettingsBlock(
                "Context prompt",
                detail: "\(isCustom ? "Using custom prompt" : "Using default"). Controls how \(AppName.displayName) infers your current activity from app metadata and screenshots."
            ) {
                if showDefaultContextPrompt {
                    defaultPromptViewer("Default Context Prompt", text: AppContextService.defaultContextPrompt) {
                        showDefaultContextPrompt = false
                    }
                }
                promptEditor($customContextPromptInput, focus: $customContextPromptFocused, minHeight: 120, maxHeight: 200)
                    .onChange(of: customContextPromptFocused) { focused in
                        if !focused { commitCustomContextPrompt() }
                    }
                if isCustom {
                    resetButton {
                        customContextPromptInput = AppContextService.defaultContextPrompt
                        appState.customContextPrompt = ""
                        appState.customContextPromptLastModified = ""
                    }
                }
            }
            SettingsRow(
                "Screenshot resolution",
                detail: "\(appState.contextScreenshotMaxDimension) px (\(isDefaultDimension ? "default" : "custom")). Controls the maximum image dimension sent for context inference."
            ) {
                if !isDefaultDimension {
                    Button("Reset to Default") {
                        appState.contextScreenshotMaxDimension = AppState.defaultContextScreenshotMaxDimension
                    }
                    .buttonStyle(.settings)
                }
                Picker("", selection: $appState.contextScreenshotMaxDimension) {
                    ForEach(AppState.contextScreenshotDimensionOptions, id: \.self) { dimension in
                        Text("\(dimension) px").tag(dimension)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .accessibilityLabel("Screenshot Resolution")
            }
            SettingsToggleRow(
                "Allow full-desktop screenshot fallback",
                detail: "When active-window capture fails, Suki can capture the full desktop, including other apps, and send it to your configured context provider. Turn this off to continue without a screenshot when active-window capture fails. Applies to new context captures.",
                isOn: $appState.desktopScreenshotFallbackEnabled
            )
            SettingsBlock(
                "Test context prompt",
                detail: "Captures a screenshot and metadata from the frontmost app, then runs the context prompt to infer activity."
            ) {
                testButton("Test Context Prompt", isRunning: contextTestRunning, action: runContextPromptTest)
                    .disabled(contextTestRunning || !hasAPIKey)
                testResults(error: contextTestError, output: contextTestOutput, prompt: contextTestPrompt)
            }
        }
    }

    private func runContextPromptTest() {
        commitCustomContextPrompt()
        contextTestRunning = true
        contextTestOutput = nil
        contextTestError = nil
        contextTestPrompt = nil

        let service = appState.makeAppContextService()

        Task {
            let context = await service.collectContext()
            await MainActor.run {
                if let prompt = context.contextPrompt {
                    contextTestOutput = context.contextSummary
                    contextTestPrompt = prompt
                } else {
                    contextTestError = context.contextSummary
                    contextTestOutput = context.contextSummary
                }
                contextTestRunning = false
            }
        }
    }

    // MARK: Shared Pieces

    private func newerDefaultRow(onView: @escaping () -> Void, onSwitch: @escaping () -> Void) -> some View {
        SettingsRow("A newer default prompt is available.") {
            Button("View Default", action: onView)
                .buttonStyle(.settings)
            Button("Switch to Default", action: onSwitch)
                .buttonStyle(.settingsProminent)
        }
    }

    private func defaultPromptViewer(_ title: String, text: String, onHide: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(SukiFont.ui(12.5, .semibold))
                Spacer()
                Button("Hide", action: onHide)
                    .buttonStyle(.settings)
            }
            Text(text)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Theme.textSecondary)
                .textSelection(.enabled)
        }
        .padding(10)
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
    }

    private func promptEditor(
        _ text: Binding<String>,
        focus: FocusState<Bool>.Binding? = nil,
        minHeight: CGFloat,
        maxHeight: CGFloat
    ) -> some View {
        Group {
            if let focus {
                TextEditor(text: text).focused(focus)
            } else {
                TextEditor(text: text)
            }
        }
        .font(.system(.body, design: .monospaced))
        .scrollContentBackground(.hidden)
        .padding(6)
        .frame(minHeight: minHeight, maxHeight: maxHeight)
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .stroke(Theme.border, lineWidth: 1)
        )
    }

    private func resetButton(action: @escaping () -> Void) -> some View {
        HStack {
            Spacer()
            Button("Reset to Default", action: action)
                .buttonStyle(.settings)
        }
    }

    private func testButton(_ title: String, isRunning: Bool, action: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: action) {
                HStack(spacing: 6) {
                    if isRunning {
                        ProgressView()
                            .controlSize(.small)
                        Text("Running...")
                    } else {
                        Image(systemName: "play.fill")
                        Text(title)
                    }
                }
            }
            .buttonStyle(.settings)
            if !hasAPIKey {
                Label("API key required to test", systemImage: "exclamationmark.triangle")
                    .settingsCaptionStyle()
            }
        }
    }

    @ViewBuilder
    private func testResults(error: String?, output: String?, prompt: String?) -> some View {
        if let error {
            Label(error, systemImage: "xmark.circle.fill")
                .font(SukiFont.ui(12.5))
                .foregroundStyle(Theme.destructive)
        }

        if let output {
            VStack(alignment: .leading, spacing: 4) {
                Text("Result:")
                    .font(SukiFont.ui(12.5, .semibold))
                Text(output.isEmpty ? "(empty — no output)" : output)
                    .font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.panel, in: RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
            }
        }

        if let prompt {
            DisclosureGroup("Full prompt sent") {
                Text(prompt)
                    .font(.system(size: 10, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .font(SukiFont.ui(12.5))
            .foregroundStyle(Theme.textSecondary)
        }
    }
}
