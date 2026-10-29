import SwiftUI

/// Cleanup, fallback, and context model pickers for the selected LLM provider.
struct LLMModelFields: View {
    @EnvironmentObject var appState: AppState
    @State private var postProcessingModelDraft: String = ""
    @State private var postProcessingFallbackModelDraft: String = ""
    @State private var contextModelDraft: String = ""
    /// Updated by the cooldown timer so warning labels clear at expiry without user interaction.
    @State private var now: Date = Date()
    /// Tracks whether the Settings window is the frontmost active window.
    @Environment(\.controlActiveState) private var controlActiveState

    private var provider: LLMProvider { appState.llmProvider }
    private var defaults: LLMModelSelection? { provider.defaultModels }

    private func commitPostProcessingModel() {
        let trimmed = postProcessingModelDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        postProcessingModelDraft = trimmed
        guard appState.postProcessingModel != trimmed else { return }
        appState.postProcessingModel = trimmed
    }

    private func commitPostProcessingFallbackModel() {
        let trimmed = postProcessingFallbackModelDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        postProcessingFallbackModelDraft = trimmed
        guard appState.postProcessingFallbackModel != trimmed else { return }
        appState.postProcessingFallbackModel = trimmed
    }

    private func commitContextModel() {
        let trimmed = contextModelDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        contextModelDraft = trimmed
        guard appState.contextModel != trimmed else { return }
        appState.contextModel = trimmed
    }

    /// True when this view's hosting window is the frontmost key window. While true a 5s timer
    /// advances `now`, so a daily-limit warning appears within ~5s of being written and clears
    /// within ~5s of expiry. SwiftUI removes the timer when this view leaves the hierarchy
    /// (switching tabs or dismissing the Setup sheet). The timer must NOT be gated on a warning
    /// already being visible: nothing else observes the UserDefaults cooldown keys, so a freshly
    /// written cooldown would otherwise never trigger a re-render. Cost is negligible.
    private var shouldRunCooldownTimer: Bool {
        controlActiveState == .key
    }

    /// Reads the persisted daily-limit expiry date for a model directly from UserDefaults.
    /// Uses the shared key from LLMCooldownManager to avoid duplicating the storage contract.
    /// Returns nil if no daily limit is active or if the entry has already expired.
    private func dailyCooldownExpiry(for model: String) -> Date? {
        let key = LLMCooldownManager.udKey(for: model)
        let timestamp = UserDefaults.standard.double(forKey: key)
        guard timestamp > 0 else { return nil }
        let date = Date(timeIntervalSince1970: timestamp)
        return date > now ? date : nil
    }

    /// Formats a cooldown reset time, including the date only when the reset falls on a later day,
    /// so a daily limit that resets after midnight is not shown as an ambiguous bare time.
    private func formattedCooldownReset(_ expiry: Date) -> String {
        // Calendar.isDate(_:inSameDayAs:) is a macOS-native calendar-aware same-day comparison.
        if Calendar.current.isDate(expiry, inSameDayAs: now) {
            return expiry.formatted(date: .omitted, time: .shortened)
        }
        return expiry.formatted(date: .abbreviated, time: .shortened)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ModelDropdownView(
                title: "Post-Processing Model",
                subtitle: "Used for transcript cleanup and Edit Mode transforms.",
                predefinedModels: provider.models,
                defaultModel: defaults?.postProcessing ?? "",
                textDraft: $postProcessingModelDraft,
                onCommit: commitPostProcessingModel,
                onReset: {
                    guard let defaults else { return }
                    postProcessingModelDraft = defaults.postProcessing
                    appState.postProcessingModel = defaults.postProcessing
                }
            )

            // Shows when this model has hit its daily Groq rate limit.
            // Disappears automatically once the limit window resets.
            if let expiry = dailyCooldownExpiry(for: appState.postProcessingModel) {
                Label {
                    Text("Daily limit reached — resets at \(formattedCooldownReset(expiry))")
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                }
                .font(.caption)
                .foregroundStyle(.orange)
            }

            ModelDropdownView(
                title: "Post-Processing Fallback Model",
                subtitle: "Used as the explicit retry model for transcript cleanup and Edit Mode transforms.",
                predefinedModels: provider.models,
                defaultModel: defaults?.postProcessingFallback ?? "",
                textDraft: $postProcessingFallbackModelDraft,
                onCommit: commitPostProcessingFallbackModel,
                onReset: {
                    guard let defaults else { return }
                    postProcessingFallbackModelDraft = defaults.postProcessingFallback
                    appState.postProcessingFallbackModel = defaults.postProcessingFallback
                }
            )

            // Shows when the fallback model has also hit its daily limit.
            // In this state, both models are unavailable until their limits reset.
            if let expiry = dailyCooldownExpiry(for: appState.postProcessingFallbackModel) {
                Label {
                    Text("Fallback daily limit reached — resets at \(formattedCooldownReset(expiry))")
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                }
                .font(.caption)
                .foregroundStyle(.orange)
            }

            ModelDropdownView(
                title: "Context Model",
                subtitle: "Used for context inference, with a text-only retry when screenshot analysis fails. Screenshot analysis requires a model that accepts image input.",
                predefinedModels: provider.visionModels,
                defaultModel: defaults?.context ?? "",
                textDraft: $contextModelDraft,
                onCommit: commitContextModel,
                onReset: {
                    guard let defaults else { return }
                    contextModelDraft = defaults.context
                    appState.contextModel = defaults.context
                }
            )
        }
        // Model lists differ per provider, so rebuild the pickers when it changes.
        .id(provider)
        .onAppear {
            postProcessingModelDraft = appState.postProcessingModel
            postProcessingFallbackModelDraft = appState.postProcessingFallbackModel
            contextModelDraft = appState.contextModel
        }
        .onChange(of: appState.postProcessingModel) { postProcessingModelDraft = $0 }
        .onChange(of: appState.postProcessingFallbackModel) { postProcessingFallbackModelDraft = $0 }
        .onChange(of: appState.contextModel) { contextModelDraft = $0 }
        // Tick every 5s while this view's window is key so a daily-limit warning can appear and
        // auto-clear without any external state change. SwiftUI removes this timer when the
        // window is backgrounded or this view leaves the hierarchy (tab switch or sheet dismissal).
        if shouldRunCooldownTimer {
            Color.clear.frame(width: 0, height: 0)
                .onReceive(Timer.publish(every: 5, on: .main, in: .common).autoconnect()) { value in
                    now = value
                }
        }
    }
}
