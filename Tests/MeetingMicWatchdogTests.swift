import Foundation

enum MeetingMicWatchdogTests {
    static func run() {
        quietRoomNoiseNeverTriggers()
        twoSecondsOfExactZerosAsksForRestart()
        zerosAccumulateAcrossSmallBatches()
        oneRealSampleResetsTheRun()
        keepsRetryingWhileBlocked()
        realAudioAfterBlockingRecovers()
    }

    private static let rate = 16_000

    private static func zeros(seconds: Double) -> [Float] {
        [Float](repeating: 0, count: Int(Double(rate) * seconds))
    }

    /// Feeds 100 ms batches, like the recorder does, and returns every verdict that is not `.fine`.
    private static func feed(_ watchdog: inout MeetingMicWatchdog, _ samples: [Float]) -> [MeetingMicWatchdog.Verdict] {
        stride(from: 0, to: samples.count, by: rate / 10).compactMap {
            let verdict = watchdog.inspect(Array(samples[$0..<min($0 + rate / 10, samples.count)]))
            return verdict == .fine ? nil : verdict
        }
    }

    private static func quietRoomNoiseNeverTriggers() {
        var watchdog = MeetingMicWatchdog()
        let hiss = (0..<(rate * 10)).map { Float($0 % 7 - 3) * 0.000_01 }
        TestSupport.expectEqual(feed(&watchdog, hiss), [])
        TestSupport.expect(!watchdog.isBlocked, "Faint room noise is a working mic")
    }

    private static func twoSecondsOfExactZerosAsksForRestart() {
        var watchdog = MeetingMicWatchdog()
        TestSupport.expectEqual(feed(&watchdog, zeros(seconds: 1.9)), [])
        TestSupport.expect(!watchdog.isBlocked, "Under two seconds of zeros is not blocked yet")
        TestSupport.expectEqual(feed(&watchdog, zeros(seconds: 0.1)), [.restart])
        TestSupport.expect(watchdog.isBlocked, "Two seconds of exact zeros means the mic is blanked")
    }

    private static func zerosAccumulateAcrossSmallBatches() {
        var watchdog = MeetingMicWatchdog()
        var verdicts: [MeetingMicWatchdog.Verdict] = []
        for _ in 0..<(2 * rate / 160) { verdicts.append(watchdog.inspect([Float](repeating: 0, count: 160))) }
        TestSupport.expectEqual(verdicts.filter { $0 != .fine }, [.restart])
        TestSupport.expectEqual(verdicts.last, .restart)
    }

    private static func oneRealSampleResetsTheRun() {
        var watchdog = MeetingMicWatchdog()
        var batch = zeros(seconds: 0.1)
        batch[800] = 0.000_1
        let samples = zeros(seconds: 1.5) + batch + zeros(seconds: 1.5)
        TestSupport.expectEqual(feed(&watchdog, samples), [])
        TestSupport.expect(!watchdog.isBlocked, "A single real sample proves the mic is alive")
    }

    private static func keepsRetryingWhileBlocked() {
        var watchdog = MeetingMicWatchdog()
        TestSupport.expectEqual(feed(&watchdog, zeros(seconds: 2)), [.restart])
        TestSupport.expectEqual(feed(&watchdog, zeros(seconds: 3.9)), [])
        TestSupport.expectEqual(feed(&watchdog, zeros(seconds: 0.1)), [.restart])
        TestSupport.expectEqual(feed(&watchdog, zeros(seconds: 4)), [.restart])
        TestSupport.expect(watchdog.isBlocked, "Still blocked while zeros continue")
    }

    private static func realAudioAfterBlockingRecovers() {
        var watchdog = MeetingMicWatchdog()
        _ = feed(&watchdog, zeros(seconds: 2))
        TestSupport.expectEqual(feed(&watchdog, MeetingTranscriptCoreTests.tone(seconds: 0.3)), [.recovered])
        TestSupport.expect(!watchdog.isBlocked, "Real audio clears the blocked state")
        TestSupport.expectEqual(feed(&watchdog, zeros(seconds: 1.9)), [])
        TestSupport.expectEqual(feed(&watchdog, zeros(seconds: 0.1)), [.restart])
    }
}
