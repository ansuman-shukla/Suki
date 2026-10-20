import SwiftUI

struct DiagnosticsSettingsPane: View {
    @EnvironmentObject var appState: AppState
    @State private var copiedBuildInfo = false
    @State private var copiedBuildInfoResetWorkItem: DispatchWorkItem?

    var body: some View {
        SettingsPane(title: "Diagnostics") {
            buildGroup
            if AppBuild.isDevBundle {
                debugGroup
            }
        }
    }

    // MARK: Build

    private var appDisplayName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? "\(AppName.displayName)"
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
    }

    private var appBuildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "SukiBuildTag") as? String
            ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
            ?? "unknown"
    }

    private var macOSVersion: String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
    }

    private var appArchitecture: String {
        #if arch(arm64)
        return "arm64"
        #elseif arch(x86_64)
        return "x86_64"
        #else
        return "unknown"
        #endif
    }

    private var buildDiagnosticsText: String {
        "\(appDisplayName) \(appVersion) (\(appBuildNumber))\nmacOS \(macOSVersion) (\(appArchitecture))"
    }

    private var buildGroup: some View {
        SettingsGroup("Build") {
            SettingsRow("Build number") {
                monospacedValue(appBuildNumber)
            }
            SettingsRow("Build details") {
                monospacedValue(buildDiagnosticsText)
                    .multilineTextAlignment(.trailing)
                Button {
                    copyBuildDiagnostics()
                } label: {
                    Label(copiedBuildInfo ? "Copied" : "Copy", systemImage: copiedBuildInfo ? "checkmark" : "doc.on.doc")
                }
                .buttonStyle(.settings)
            }
        }
    }

    private func monospacedValue(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, design: .monospaced))
            .foregroundStyle(Theme.textSecondary)
            .textSelection(.enabled)
    }

    private func copyBuildDiagnostics() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(buildDiagnosticsText, forType: .string)
        copiedBuildInfo = true

        copiedBuildInfoResetWorkItem?.cancel()

        let resetWorkItem = DispatchWorkItem {
            copiedBuildInfo = false
            copiedBuildInfoResetWorkItem = nil
        }
        copiedBuildInfoResetWorkItem = resetWorkItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: resetWorkItem)
    }

    // MARK: Debug

    private var debugGroup: some View {
        SettingsGroup("Debug") {
            SettingsRow("Recording overlay", detail: "Show the recording overlay with simulated audio levels.") {
                Button(appState.isDebugOverlayActive ? "Stop Debug Overlay" : "Debug Overlay") {
                    appState.toggleDebugOverlay()
                }
                .buttonStyle(.settings)
            }
            SettingsToggleRow(
                "Show update overlay after dictation",
                detail: "Display the update available overlay after dictation finishes.",
                isOn: $appState.debugShowsUpdateReminderAfterDictation
            )
            SettingsRow("Update overlay") {
                Button("Show Update Overlay Now") {
                    appState.showDebugUpdateAvailableOverlay()
                }
                .buttonStyle(.settings)
            }
        }
    }
}
