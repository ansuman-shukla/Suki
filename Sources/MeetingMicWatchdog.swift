import Foundation

/// Spots a microphone that another app is blanking. A real mic always carries a little noise, even in
/// a silent room, so a long run of exact zeros means the audio is being muted, not that nobody is talking.
struct MeetingMicWatchdog {
    enum Verdict: Equatable {
        case fine
        /// The mic has been blanked for a while: restart it. Repeats while the blanking lasts.
        case restart
        /// Real audio is back after a restart.
        case recovered
    }

    static let blockedAfterSeconds: TimeInterval = 2
    static let retryAfterSeconds: TimeInterval = 4

    private(set) var isBlocked = false
    private var zeroRun = 0
    private let blockedAfter: Int
    private let retryAfter: Int

    init(sampleRate: Double = MeetingTranscriptCore.sampleRate) {
        blockedAfter = Int(sampleRate * Self.blockedAfterSeconds)
        retryAfter = Int(sampleRate * Self.retryAfterSeconds)
    }

    mutating func inspect(_ samples: [Float]) -> Verdict {
        guard samples.allSatisfy({ $0 == 0 }) else {
            zeroRun = 0
            guard isBlocked else { return .fine }
            isBlocked = false
            return .recovered
        }
        let previous = zeroRun
        zeroRun += samples.count
        let threshold = isBlocked ? retryAfter : blockedAfter
        guard previous < threshold, zeroRun >= threshold else { return .fine }
        isBlocked = true
        zeroRun = 0
        return .restart
    }
}
