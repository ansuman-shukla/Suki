import SwiftUI

struct GeneralSettingsPane: View {
    @EnvironmentObject var appState: AppState
    @State private var showMutedHint = false

    var body: some View {
        SettingsPane(title: "General") {
            shortcutsGroup
            SettingsGroup("Microphone") {
                microphoneRow
            }
            SettingsGroup("Language") {
                outputLanguageRow
            }
            soundsGroup
            SettingsGroup("Audio during dictation") {
                SettingsToggleRow(
                    "Mute audio when dictation starts",
                    detail: "\(AppName.displayName) restores the audio state it changed when dictation ends.",
                    isOn: $appState.dictationAudioInterruptionEnabled
                )
            }
        }
    }

    // MARK: Dictation Shortcuts

    private var shortcutsGroup: some View {
        SettingsGroup("Keyboard shortcuts") {
            SettingsBlock {
                DictationShortcutEditor { isCapturing in
                    if isCapturing {
                        appState.suspendHotkeyMonitoringForShortcutCapture()
                    } else {
                        appState.resumeHotkeyMonitoringAfterShortcutCapture()
                    }
                }
            }
            SettingsBlock(
                "Shortcut start delay",
                detail: "\(appState.shortcutStartDelayMilliseconds) ms. Applies before recording starts for both hold and tap shortcuts. Stopping still happens immediately."
            ) {
                Slider(
                    value: $appState.shortcutStartDelay,
                    in: 0...0.5,
                    step: 0.025
                )
                .tint(Theme.textPrimary)
            }
        }
    }

    // MARK: Microphone

    private var microphoneSelection: String {
        appState.selectedMicrophoneID.isEmpty ? "default" : appState.selectedMicrophoneID
    }

    private var microphoneName: String {
        if microphoneSelection == "default" { return "System Default" }
        return appState.availableMicrophones.first { $0.uid == microphoneSelection }?.name ?? "Disconnected microphone"
    }

    private var microphoneRow: some View {
        SettingsRow("Microphone", detail: microphoneName) {
            SettingsMenuButton {
                Picker("Microphone", selection: Binding(
                    get: { microphoneSelection },
                    set: { appState.selectedMicrophoneID = $0 }
                )) {
                    Text("System Default").tag("default")
                    ForEach(appState.availableMicrophones) { device in
                        Text(device.name).tag(device.uid)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }
            .accessibilityLabel("Microphone")
        }
        .onAppear {
            appState.refreshAvailableMicrophones()
        }
    }

    // MARK: Output Language

    private static let outputLanguageOptions = [
        "English",
        "Chinese (Simplified)",
        "Chinese (Traditional)",
        "Spanish",
        "French",
        "Japanese",
        "Korean",
        "German",
        "Portuguese",
    ]

    private var outputLanguageRow: some View {
        SettingsRow(
            "Output language",
            detail: "\(appState.outputLanguage.isEmpty ? "Same as spoken" : appState.outputLanguage). When set, Suki translates your speech into the selected language."
        ) {
            SettingsMenuButton {
                Picker("Language", selection: $appState.outputLanguage) {
                    Text("Same as spoken").tag("")
                    ForEach(Self.outputLanguageOptions, id: \.self) { lang in
                        Text(lang).tag(lang)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }
            .accessibilityLabel("Output language")
        }
    }

    // MARK: Sound Volume

    private var soundsGroup: some View {
        SettingsGroup("Sounds") {
            SettingsToggleRow("Play alert sounds", isOn: $appState.alertSoundsEnabled)
            SettingsRow("Volume", detail: "\(Int(appState.soundVolume * 100))%") {
                Slider(value: $appState.soundVolume, in: 0...1, step: 0.1)
                    .tint(Theme.textPrimary)
                    .frame(width: 160)
                Button("Preview") {
                    let muted = SystemAudioStatus.isDefaultOutputMuted()
                    let volume = SystemAudioStatus.defaultOutputVolume()
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showMutedHint = muted || (volume ?? 1) < 0.10
                    }
                    appState.playAlertSound(named: "Tink")
                }
                .buttonStyle(.settings)
            }
            .disabled(!appState.alertSoundsEnabled)
            .opacity(appState.alertSoundsEnabled ? 1 : 0.5)
            if showMutedHint {
                SettingsBlock {
                    Label("System volume is muted or very low. Unmute to hear the preview.", systemImage: "speaker.slash.fill")
                        .settingsCaptionStyle()
                }
                .transition(.opacity)
            }
        }
        .onChange(of: appState.alertSoundsEnabled) { enabled in
            if !enabled { showMutedHint = false }
        }
    }
}
