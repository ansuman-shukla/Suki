import Foundation

/// Why a meeting recording stopped by itself. Raw values are safe to log: they hold no user content.
enum MeetingAutoStopReason: String, CaseIterable {
    case callEnded
    case silence
    case systemSleep
    case maxDuration

    /// Short notice shown instead of the "Copied to clipboard" toast.
    var notice: String {
        switch self {
        case .callEnded: return "Meeting saved: call ended"
        case .silence: return "Meeting saved: no one talking"
        case .systemSleep: return "Meeting saved: Mac went to sleep"
        case .maxDuration: return "Meeting saved: 4 hour limit"
        }
    }
}

/// Decides when a recording should stop by itself, from values polled every few seconds.
/// The call-ended rule only applies once a call app was seen using the mic during this
/// recording, so a manually started in-person meeting is never cut off by it. Sleep is an
/// event rather than a polled value, so the recorder handles it directly.
struct MeetingAutoStopPolicy {
    static let callEndedGraceSeconds: TimeInterval = 30
    static let silenceSeconds: TimeInterval = 10 * 60
    static let maxDurationSeconds: TimeInterval = 4 * 60 * 60

    private(set) var sawCallApp = false
    /// When no call app was using the mic any more, in seconds since the recording started.
    private var callAppsGoneSince: TimeInterval?

    /// `elapsed` is seconds since the recording started. `lastSpeechTime` is the end of the
    /// latest voiced speech on either side in the same timeline, nil before anyone spoke.
    /// When several rules apply, the hard cap wins, then a finished call, then silence.
    mutating func update(
        elapsed: TimeInterval,
        callApps: Set<String>,
        lastSpeechTime: TimeInterval?
    ) -> MeetingAutoStopReason? {
        if !callApps.isEmpty {
            sawCallApp = true
            callAppsGoneSince = nil
        } else if sawCallApp, callAppsGoneSince == nil {
            callAppsGoneSince = elapsed
        }
        if elapsed >= Self.maxDurationSeconds { return .maxDuration }
        if let gone = callAppsGoneSince, elapsed - gone >= Self.callEndedGraceSeconds { return .callEnded }
        if elapsed - (lastSpeechTime ?? 0) >= Self.silenceSeconds { return .silence }
        return nil
    }
}
