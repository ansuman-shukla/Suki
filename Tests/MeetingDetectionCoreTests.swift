import Foundation

enum MeetingDetectionCoreTests {
    static func run() {
        modeDefaultsToNotify()
        modeLoadsSavedChoiceAndFallsBack()
        mapsCallAppsAndHelpers()
        ignoresNonCallApps()
        promptsOnlyAfterSettling()
        promptsOncePerCall()
        promptsAgainAfterCallEnds()
        staysQuietForCallsSeenWhileRecording()
        offStateNeverPrompts()
    }

    private static let start = Date(timeIntervalSinceReferenceDate: 1_000)

    private static func makeDefaults() -> UserDefaults {
        let suite = "MeetingDetectionCoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    private static func modeDefaultsToNotify() {
        TestSupport.expectEqual(MeetingDetectionMode.load(from: makeDefaults()), .notify)
    }

    private static func modeLoadsSavedChoiceAndFallsBack() {
        let defaults = makeDefaults()
        defaults.set("off", forKey: "meeting_detection_mode")
        TestSupport.expectEqual(MeetingDetectionMode.load(from: defaults), .off)
        defaults.set("loud", forKey: "meeting_detection_mode")
        TestSupport.expectEqual(MeetingDetectionMode.load(from: defaults), .notify)
    }

    private static func mapsCallAppsAndHelpers() {
        TestSupport.expectEqual(CallApps.name(forBundleID: "us.zoom.xos"), "Zoom")
        TestSupport.expectEqual(CallApps.name(forBundleID: "com.google.Chrome.helper"), "Google Chrome")
        TestSupport.expectEqual(CallApps.name(forBundleID: "com.microsoft.teams2"), "Microsoft Teams")
        TestSupport.expectEqual(CallApps.name(forBundleID: "com.apple.avconferenced"), "FaceTime")
        TestSupport.expectEqual(CallApps.name(forBundleID: "com.apple.WebKit.GPU"), "Safari")
    }

    private static func ignoresNonCallApps() {
        TestSupport.expectEqual(CallApps.name(forBundleID: "com.apple.CoreSpeech"), nil)
        TestSupport.expectEqual(CallApps.name(forBundleID: "com.example.recorder"), nil)
        TestSupport.expectEqual(CallApps.name(forBundleID: "com.ansumanshukla.suki.dev"), nil)
    }

    private static func promptsOnlyAfterSettling() {
        var detector = MeetingCallDetector()
        TestSupport.expectEqual(detector.update(activeApps: ["Zoom"], now: start, canPrompt: true), nil)
        TestSupport.expectEqual(detector.update(activeApps: ["Zoom"], now: start + 2.9, canPrompt: true), nil)
        TestSupport.expectEqual(detector.update(activeApps: ["Zoom"], now: start + 3, canPrompt: true), "Zoom")
    }

    private static func promptsOncePerCall() {
        var detector = MeetingCallDetector()
        _ = detector.update(activeApps: ["Zoom"], now: start, canPrompt: true)
        TestSupport.expectEqual(detector.update(activeApps: ["Zoom"], now: start + 5, canPrompt: true), "Zoom")
        TestSupport.expectEqual(detector.update(activeApps: ["Zoom"], now: start + 60, canPrompt: true), nil)
    }

    private static func promptsAgainAfterCallEnds() {
        var detector = MeetingCallDetector()
        _ = detector.update(activeApps: ["Zoom"], now: start, canPrompt: true)
        _ = detector.update(activeApps: ["Zoom"], now: start + 5, canPrompt: true)
        TestSupport.expectEqual(detector.update(activeApps: [], now: start + 10, canPrompt: true), nil)
        TestSupport.expectEqual(detector.update(activeApps: ["Zoom"], now: start + 20, canPrompt: true), nil)
        TestSupport.expectEqual(detector.update(activeApps: ["Zoom"], now: start + 23, canPrompt: true), "Zoom")
    }

    private static func staysQuietForCallsSeenWhileRecording() {
        var detector = MeetingCallDetector()
        _ = detector.update(activeApps: ["Google Chrome"], now: start, canPrompt: false)
        TestSupport.expectEqual(detector.update(activeApps: ["Google Chrome"], now: start + 30, canPrompt: true), nil)
        TestSupport.expectEqual(
            detector.update(activeApps: ["Google Chrome", "Zoom"], now: start + 31, canPrompt: true),
            nil
        )
        TestSupport.expectEqual(
            detector.update(activeApps: ["Google Chrome", "Zoom"], now: start + 34, canPrompt: true),
            "Zoom"
        )
    }

    private static func offStateNeverPrompts() {
        var detector = MeetingCallDetector()
        for second in 0...10 {
            TestSupport.expectEqual(
                detector.update(activeApps: ["Zoom"], now: start + Double(second), canPrompt: false),
                nil
            )
        }
    }
}
