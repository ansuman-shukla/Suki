import Foundation

/// Whether Suki offers to record when a call app starts using the microphone.
enum MeetingDetectionMode: String, CaseIterable, Identifiable {
    case notify
    case off

    static let storageKey = "meeting_detection_mode"
    static let defaultValue = MeetingDetectionMode.notify

    var id: String { rawValue }

    var title: String {
        switch self {
        case .notify: return "Notify me"
        case .off: return "Do nothing"
        }
    }

    static func load(from defaults: UserDefaults) -> MeetingDetectionMode {
        defaults.string(forKey: storageKey).flatMap(MeetingDetectionMode.init(rawValue:)) ?? defaultValue
    }
}

/// Apps whose microphone use most likely means a call. Matched by bundle ID prefix so helper
/// processes (e.g. `com.google.Chrome.helper`) count for their app. FaceTime captures audio
/// through `avconferenced`, not its own process.
enum CallApps {
    static let known: [(prefix: String, name: String)] = [
        ("us.zoom", "Zoom"),
        ("com.microsoft.teams", "Microsoft Teams"),
        ("com.apple.FaceTime", "FaceTime"),
        ("com.apple.avconferenced", "FaceTime"),
        ("com.tinyspeck.slackmacgap", "Slack"),
        ("com.hnc.Discord", "Discord"),
        ("com.cisco.webexmeetingsapp", "Webex"),
        ("Cisco-Systems.Spark", "Webex"),
        ("net.whatsapp.WhatsApp", "WhatsApp"),
        ("com.google.Chrome", "Google Chrome"),
        ("com.apple.Safari", "Safari"),
        ("com.apple.WebKit", "Safari"),
        ("company.thebrowser.Browser", "Arc"),
        ("com.brave.Browser", "Brave"),
        ("com.microsoft.edgemac", "Microsoft Edge"),
        ("org.mozilla.firefox", "Firefox"),
        ("com.operasoftware.Opera", "Opera"),
        ("com.vivaldi.Vivaldi", "Vivaldi"),
    ]

    static func name(forBundleID bundleID: String) -> String? {
        known.first { bundleID.hasPrefix($0.prefix) }?.name
    }
}

/// Decides when to offer a meeting recording. Prompts once per call: an app must hold the mic
/// for `settleSeconds` first, and after a prompt (or while Suki itself records) that app stays
/// quiet until it releases the mic.
struct MeetingCallDetector {
    var settleSeconds: TimeInterval = 3
    private var firstSeen: [String: Date] = [:]
    private var handled: Set<String> = []

    mutating func update(activeApps: Set<String>, now: Date, canPrompt: Bool) -> String? {
        for app in firstSeen.keys where !activeApps.contains(app) {
            firstSeen[app] = nil
            handled.remove(app)
        }
        for app in activeApps where firstSeen[app] == nil {
            firstSeen[app] = now
        }
        guard canPrompt else {
            handled.formUnion(activeApps)
            return nil
        }
        let ready = activeApps.sorted().first { app in
            !handled.contains(app) && now.timeIntervalSince(firstSeen[app] ?? now) >= settleSeconds
        }
        if let ready { handled.insert(ready) }
        return ready
    }
}
