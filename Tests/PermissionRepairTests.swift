import Foundation

enum PermissionRepairTests {
    static func run() {
        testTCCServiceNames()
        testGrantHistoryDetectsLostGrant()
        testResetTargetsOnlyThisApp()
        testResetRefusesMissingBundleIdentifier()
        testFailedResetKeepsHistory()
    }

    private static func makeDefaults() -> (UserDefaults, String) {
        let suite = "SukiTests.PermissionRepair.\(UUID().uuidString)"
        return (UserDefaults(suiteName: suite)!, suite)
    }

    private static func testTCCServiceNames() {
        TestSupport.expectEqual(PrivacyPermission.accessibility.rawValue, "Accessibility")
        TestSupport.expectEqual(PrivacyPermission.screenRecording.rawValue, "ScreenCapture")
    }

    private static func testGrantHistoryDetectsLostGrant() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let history = PermissionGrantHistory(defaults: defaults)

        TestSupport.expect(!history.wasLost(.accessibility, currentlyGranted: false), "A never-granted permission is not lost")
        history.record(.accessibility, granted: false)
        TestSupport.expect(!history.wasLost(.accessibility, currentlyGranted: false), "Recording a denial must not mark the permission as held")

        history.record(.accessibility, granted: true)
        TestSupport.expect(!history.wasLost(.accessibility, currentlyGranted: true), "A currently granted permission is not lost")
        TestSupport.expect(history.wasLost(.accessibility, currentlyGranted: false), "A held permission that is now denied is lost")
        TestSupport.expect(!history.wasLost(.screenRecording, currentlyGranted: false), "History is tracked per permission")

        history.record(.accessibility, granted: false)
        let reloaded = PermissionGrantHistory(defaults: UserDefaults(suiteName: suite)!)
        TestSupport.expect(reloaded.wasLost(.accessibility, currentlyGranted: false), "A later denial must not erase the history, and it must persist")

        history.forget(.accessibility)
        TestSupport.expect(!history.wasLost(.accessibility, currentlyGranted: false), "Forgetting clears the lost state")
    }

    private static func testResetTargetsOnlyThisApp() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let history = PermissionGrantHistory(defaults: defaults)
        history.record(.screenRecording, granted: true)
        history.record(.accessibility, granted: true)

        var calls: [(URL, [String])] = []
        try! PermissionReset.reset(.screenRecording, bundleIdentifier: "com.example.synthetic", history: history) { url, args in
            calls.append((url, args))
            return 0
        }

        TestSupport.expectEqual(calls.count, 1)
        TestSupport.expectEqual(calls[0].0.path, "/usr/bin/tccutil")
        TestSupport.expectEqual(calls[0].1, ["reset", "ScreenCapture", "com.example.synthetic"])
        TestSupport.expect(!history.wasLost(.screenRecording, currentlyGranted: false), "A successful reset forgets the stale grant")
        TestSupport.expect(history.wasLost(.accessibility, currentlyGranted: false), "Resetting one permission must not forget another")
    }

    private static func testResetRefusesMissingBundleIdentifier() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let history = PermissionGrantHistory(defaults: defaults)

        for bundleIdentifier in [nil, ""] as [String?] {
            var ranTool = false
            do {
                try PermissionReset.reset(.accessibility, bundleIdentifier: bundleIdentifier, history: history) { _, _ in
                    ranTool = true
                    return 0
                }
                TestSupport.expect(false, "Reset without a bundle identifier must throw")
            } catch {
                TestSupport.expectEqual(error as? PermissionResetError, .missingBundleIdentifier)
            }
            TestSupport.expect(!ranTool, "tccutil must never run without a bundle identifier; it would reset every app")
        }
    }

    private static func testFailedResetKeepsHistory() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let history = PermissionGrantHistory(defaults: defaults)
        history.record(.accessibility, granted: true)

        do {
            try PermissionReset.reset(.accessibility, bundleIdentifier: "com.example.synthetic", history: history) { _, _ in 1 }
            TestSupport.expect(false, "A non-zero tccutil exit must throw")
        } catch {
            TestSupport.expectEqual(error as? PermissionResetError, .toolFailed(exitCode: 1))
        }
        TestSupport.expect(history.wasLost(.accessibility, currentlyGranted: false), "A failed reset must keep offering repair")
    }
}
