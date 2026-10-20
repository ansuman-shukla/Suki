import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    let appState = AppState()
    var setupWindow: NSWindow?
    private var hubWindow: NSWindow?
    private let hubRouter = HubRouter()
    private(set) lazy var meetingRecorder = MainActor.assumeIsolated { MeetingRecorder.live(appState: appState) }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NetworkMonitor.shared.start()
        SukiFont.registerBundled()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleShowSetup),
            name: .showSetup,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleShowSettings),
            name: .showSettings,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleShowHub),
            name: .showHub,
            object: nil
        )

        if !appState.hasCompletedSetup {
            showSetupWindow()
        } else {
            appState.startHotkeyMonitoring()
            appState.startAccessibilityPolling()
            Task { @MainActor in
                UpdateManager.shared.startPeriodicChecks()
            }

            if !AXIsProcessTrusted() {
                appState.showAccessibilityAlert()
            }
        }

    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard appState.hasCompletedSetup else { return true }
        if !flag {
            showHubWindow()
        }
        return true
    }

    @objc func handleShowSetup() {
        // Single wizard at a time — opening a second leaks the first's
        // willClose observer and breaks the bail-restore.
        if let existing = setupWindow, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let wasCompleted = appState.hasCompletedSetup
        appState.hasCompletedSetup = false
        appState.stopAccessibilityPolling()
        appState.stopHotkeyMonitoring()
        showSetupWindow()

        // Restore prior state if the user closes the wizard without completing.
        // completeSetup() flips hasCompletedSetup back to true before window.close(),
        // so the !hasCompletedSetup check below correctly skips the restore there.
        if wasCompleted, let window = setupWindow {
            NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                guard let self = self else { return }
                if !self.appState.hasCompletedSetup {
                    self.appState.hasCompletedSetup = true
                    self.appState.startHotkeyMonitoring()
                    self.appState.startAccessibilityPolling()
                    NSApp.setActivationPolicy(.accessory)
                }
                self.setupWindow = nil
            }
        }
    }

    @objc private func handleShowSettings() {
        showHubWindow()
        hubRouter.isSettingsPresented = true
    }

    @objc private func handleShowHub(_ notification: Notification) {
        if let section = notification.object as? HubSection {
            hubRouter.section = section
        }
        showHubWindow()
    }

    private func showHubWindow() {
        NSApp.setActivationPolicy(.regular)

        if hubWindow == nil {
            hubWindow = makeHubWindow()
        }
        hubWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func makeHubWindow() -> NSWindow {
        let hubView = HubView()
            .environmentObject(appState)
            .environmentObject(hubRouter)
            .environmentObject(meetingRecorder)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1040, height: 680),
            styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = AppName.displayName
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.contentView = NSHostingView(rootView: hubView)
        window.minSize = NSSize(width: 900, height: 600)
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("SukiHubWindow")
        if !window.setFrameUsingName("SukiHubWindow") {
            window.center()
        }

        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            if self?.setupWindow == nil {
                NSApp.setActivationPolicy(.accessory)
            }
            self?.hubRouter.isSettingsPresented = false
            self?.hubWindow = nil
        }
        return window
    }


    func showSetupWindow() {
        NSApp.setActivationPolicy(.regular)

        let setupView = SetupView(onComplete: { [weak self] in
            self?.completeSetup()
        })
        .environmentObject(appState)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 680),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = AppName.displayName
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.contentView = NSHostingView(rootView: setupView)
        window.minSize = NSSize(width: 520, height: 680)
        window.center()
        window.makeKeyAndOrderFront(nil)
        window.isReleasedWhenClosed = false

        self.setupWindow = window
        NSApp.activate(ignoringOtherApps: true)
    }

    func completeSetup() {
        appState.hasCompletedSetup = true
        setupWindow?.close()
        setupWindow = nil
        NSApp.setActivationPolicy(.accessory)
        appState.startHotkeyMonitoring()
        appState.startAccessibilityPolling()
        Task { @MainActor in
            UpdateManager.shared.startPeriodicChecks()
        }

        if !AXIsProcessTrusted() {
            appState.showAccessibilityAlert()
        }
    }
}
