import AVFoundation
import ServiceManagement
import SwiftUI

struct SystemSettingsPane: View {
    @EnvironmentObject var appState: AppState
    @AppStorage("show_menu_bar_icon") private var showMenuBarIcon = true
    @AppStorage("overlay_display_id") private var overlayDisplayID = 0
    @AppStorage("use_compact_overlay") private var useCompactOverlay = true
    @AppStorage(RecordingTimerPreference.storageKey) private var showRecordingTimer = RecordingTimerPreference.defaultEnabled
    @State private var screensVersion = 0
    @State private var micPermissionGranted = false
    @ObservedObject private var updateManager = UpdateManager.shared

    var body: some View {
        SettingsPane(title: "System") {
            appGroup
            permissionsGroup
            overlayGroup
            clipboardGroup
            if UpdateManager.isConfigured {
                updatesGroup
            }
        }
        .onAppear {
            micPermissionGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
            appState.refreshLaunchAtLoginStatus()
        }
    }

    // MARK: App

    private var appGroup: some View {
        SettingsGroup("App") {
            SettingsToggleRow("Launch \(AppName.displayName) at login", isOn: $appState.launchAtLogin)
            SettingsToggleRow("Show menu bar icon", isOn: $showMenuBarIcon)
            if SMAppService.mainApp.status == .requiresApproval {
                SettingsRow("Approval required", detail: "Login item requires approval in System Settings.") {
                    Button("Open Login Items Settings") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension")!)
                    }
                    .buttonStyle(.settings)
                }
            }
        }
    }

    // MARK: Permissions

    private var permissionsGroup: some View {
        SettingsGroup("Permissions") {
            permissionRow("Microphone", granted: micPermissionGranted) {
                appState.requestMicrophoneAccess { granted in
                    micPermissionGranted = granted
                }
            }
            permissionRow("Accessibility", granted: appState.hasAccessibility) {
                appState.openAccessibilitySettings()
            }
            permissionRow("Screen Recording", granted: appState.hasScreenRecordingPermission) {
                appState.requestScreenCapturePermission()
            }
        }
    }

    private func permissionRow(_ title: String, granted: Bool, action: @escaping () -> Void) -> some View {
        SettingsRow(title, detail: granted ? "Granted" : "Not granted") {
            if granted {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Theme.textPrimary)
                    .accessibilityLabel("Granted")
            } else {
                Button("Grant Access", action: action)
                    .buttonStyle(.settings)
            }
        }
    }

    // MARK: Recording Overlay

    private var overlayGroup: some View {
        SettingsGroup("Recording overlay") {
            SettingsBlock("Style", detail: useCompactOverlay ? "Minimalist menu-bar overlay" : "Drop-down pill") {
                OverlayStyleOptionRow(
                    title: "Minimalist menu-bar overlay",
                    subtitle: "Two slim wings flank the camera notch and stay inside the menu bar. Never covers app tabs or toolbars.",
                    isMinimalist: true,
                    selection: $useCompactOverlay
                )
                OverlayStyleOptionRow(
                    title: "Drop-down pill",
                    subtitle: "Single pill hangs below the menu bar during recording. Larger and more visible, but covers a thin strip of whatever app is active.",
                    isMinimalist: false,
                    selection: $useCompactOverlay
                )
            }
            SettingsToggleRow(
                "Show recording timer",
                detail: "When off, the minimalist overlay shows a waveform instead of the timer, and the drop-down pill hides the timer. Applies to the next recording.",
                isOn: $showRecordingTimer
            )
            overlayDisplayRow
        }
    }

    /// Picks which physical display the recording overlay drops down on.
    /// Without this, AppKit defaults to "the screen with the active key
    /// window" (NSScreen.main), which makes the pill follow focus across
    /// monitors — disorienting on multi-display setups.
    private var overlayDisplayRow: some View {
        SettingsRow("Show on", detail: overlayDisplayName) {
            SettingsMenuButton {
                Picker("Show on", selection: $overlayDisplayID) {
                    Text("Active window (default)").tag(0)
                    Text("Primary display").tag(-1)
                    ForEach(connectedScreenEntries, id: \.tag) { entry in
                        Text(entry.name).tag(entry.tag)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }
            .accessibilityLabel("Show on")
        }
        // Re-query NSScreen.screens whenever the display arrangement
        // changes so newly-attached monitors appear in the menu without
        // reopening Settings. screensVersion is just a cache-buster.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in
            screensVersion &+= 1
        }
    }

    private var overlayDisplayName: String {
        switch overlayDisplayID {
        case 0: return "Active window (default)"
        case -1: return "Primary display"
        default: return connectedScreenEntries.first { $0.tag == overlayDisplayID }?.name ?? "Disconnected display"
        }
    }

    private var connectedScreenEntries: [(name: String, tag: Int)] {
        _ = screensVersion
        return NSScreen.screens.compactMap { screen in
            guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else {
                return nil
            }
            return (name: screen.localizedName, tag: Int(id))
        }
    }

    // MARK: Clipboard

    private var clipboardGroup: some View {
        SettingsGroup("Clipboard") {
            SettingsToggleRow(
                "Preserve clipboard after paste",
                detail: "\(AppName.displayName) will temporarily place the transcript on your clipboard to paste it, then restore whatever was there before. If you copy something else before the restore happens, \(AppName.displayName) leaves it alone.",
                isOn: $appState.preserveClipboard
            )
            SettingsToggleRow(
                "Keep dictations in clipboard history",
                detail: "When on, your clipboard manager (Paste, Raycast, Maccy, etc.) records each dictation so you can find it in your recent history. When off, \(AppName.displayName) marks dictations transient and your clipboard manager skips them.",
                isOn: $appState.keepDictationInClipboardHistory
            )
            SettingsToggleRow(
                "Say \"press enter\" to submit after paste",
                detail: "When the transcription ends with \"press enter\", \(AppName.displayName) removes those words before cleanup, pastes the remaining transcript, then presses Return.",
                isOn: $appState.isPressEnterVoiceCommandEnabled
            )
        }
    }

    // MARK: Updates

    private var updatesGroup: some View {
        SettingsGroup("Updates") {
            SettingsToggleRow("Automatically check for updates", isOn: Binding(
                get: { updateManager.autoCheckEnabled },
                set: { updateManager.autoCheckEnabled = $0 }
            ))
            SettingsRow(
                "Check for updates",
                detail: updateManager.lastCheckDate.map { "Last checked: \($0.formatted(date: .abbreviated, time: .shortened))" }
            ) {
                Button {
                    Task {
                        await updateManager.checkForUpdates(userInitiated: true)
                    }
                } label: {
                    if updateManager.isChecking {
                        HStack(spacing: 6) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Checking...")
                        }
                    } else {
                        Text("Check Now")
                    }
                }
                .buttonStyle(.settings)
                .disabled(updateManager.isChecking || updateManager.updateStatus != .idle)
            }
            if updateManager.updateAvailable {
                updateStatusRow
            }
        }
    }

    @ViewBuilder
    private var updateStatusRow: some View {
        switch updateManager.updateStatus {
        case .downloading:
            SettingsBlock("Downloading update...", detail: updateManager.downloadProgress.map { "\(Int($0 * 100))%" }) {
                HStack(spacing: 12) {
                    ProgressView(value: updateManager.downloadProgress ?? 0)
                        .progressViewStyle(.linear)
                        .tint(Theme.textPrimary)
                    Button("Cancel") {
                        updateManager.cancelDownload()
                    }
                    .buttonStyle(.settings)
                }
            }

        case .installing:
            SettingsRow("Installing update...") {
                ProgressView()
                    .controlSize(.small)
            }

        case .readyToRelaunch:
            SettingsRow("Relaunching...") {
                ProgressView()
                    .controlSize(.small)
            }

        case .error(let message):
            SettingsRow("Update failed", detail: message) {
                Button("Retry") {
                    updateManager.updateStatus = .idle
                    if let release = updateManager.latestRelease {
                        updateManager.downloadAndInstall(release: release)
                    }
                }
                .buttonStyle(.settings)
            }

        case .idle:
            SettingsRow(
                updateManager.latestReleaseVersion.isEmpty
                    ? "A new version of \(AppName.displayName) is available!"
                    : "\(AppName.displayName) v\(updateManager.latestReleaseVersion) is available!"
            ) {
                Button("What's New") {
                    updateManager.showReleaseNotes()
                }
                .buttonStyle(.settings)
                Button("Update Now") {
                    if let release = updateManager.latestRelease {
                        updateManager.downloadAndInstall(release: release)
                    }
                }
                .buttonStyle(.settingsProminent)
            }
        }
    }
}
