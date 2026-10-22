import Foundation

enum MeetingEchoGateTests {
    static func run() {
        correlatorFindsTheEchoDelay()
        correlatorScoresUnrelatedAudioLow()
        speakerEchoIsSuppressedFromItsStart()
        suppressionWaitsForAgreeingAnalyses()
        weaklyCorrelatedResidueStillLocks()
        talkingOverTheEchoReleasesWithinASecond()
        nearEndSpeechIsNeverSuppressed()
        talkingOverTheEchoIsNotMarked()
        weakEchoIsCaughtByItsLearnedLevel()
        loudNearEndAfterALockIsNotCaughtByLevel()
        learnedEchoLevelFollowsAVolumeChange()
        quietMicIsNotJudged()
        movedCorrelationReleasesQuickly()
        droppedAudioForgetsTheLock()
        removingEchoSilencesOnlyEchoAndMovesTheStart()
        removingEchoDropsAChunkThatWasOnlyEcho()
    }

    private static let rate = Int(MeetingTranscriptCore.sampleRate)

    /// Seeded noise in syllable-length bursts with short gaps, a stand-in for speech.
    static func speechLike(seconds: Double, seed: UInt64, amplitude: Float = 0.1) -> [Float] {
        var state = seed | 1
        func next() -> UInt64 {
            state ^= state << 13
            state ^= state >> 7
            state ^= state << 17
            return state
        }
        func uniform() -> Float { Float(next() % 1_000_000) / 1_000_000 }
        var samples: [Float] = []
        let count = Int(seconds * Double(rate))
        samples.reserveCapacity(count)
        while samples.count < count {
            let burst = Int((0.15 + 0.15 * Double(uniform())) * Double(rate))
            let gap = Int((0.04 + 0.08 * Double(uniform())) * Double(rate))
            var smoothed: Float = 0
            for _ in 0..<burst {
                smoothed = 0.6 * smoothed + 0.4 * (uniform() * 2 - 1)
                samples.append(smoothed * amplitude * 2.5)
            }
            samples += repeatElement(0, count: gap)
        }
        return Array(samples.prefix(count))
    }

    /// `source` heard `delay` samples later at `gain`, as speakers leak into a mic.
    static func echo(of source: [Float], delay: Int, gain: Float) -> [Float] {
        [Float](repeating: 0, count: delay) + source.dropLast(delay).map { $0 * gain }
    }

    private static func mix(_ a: [Float], _ b: [Float]) -> [Float] {
        var result = [Float](repeating: 0, count: max(a.count, b.count))
        for (index, sample) in a.enumerated() { result[index] += sample }
        for (index, sample) in b.enumerated() { result[index] += sample }
        return result
    }

    /// Feeds both streams in 100 ms batches on the meeting clock, like live capture.
    private static func feed(_ gate: inout MeetingEchoGate, me: [Float], them: [Float], startingAt start: TimeInterval = 0) {
        let batch = rate / 10
        for offset in stride(from: 0, to: max(me.count, them.count), by: batch) {
            let arrival = start + Double(offset + batch) / Double(rate)
            if offset < them.count { gate.append(Array(them[offset..<min(offset + batch, them.count)]), from: .them, arrival: arrival) }
            if offset < me.count { gate.append(Array(me[offset..<min(offset + batch, me.count)]), from: .me, arrival: arrival) }
        }
    }

    private static func covered(_ intervals: [ClosedRange<TimeInterval>], _ range: ClosedRange<TimeInterval>) -> TimeInterval {
        intervals.reduce(0) { total, interval in
            guard interval.overlaps(range) else { return total }
            return total + min(interval.upperBound, range.upperBound) - max(interval.lowerBound, range.lowerBound)
        }
    }

    private static func decimated(_ samples: [Float]) -> [Float] {
        stride(from: 0, to: samples.count - 1, by: 2).map { (samples[$0] + samples[$0 + 1]) / 2 }
    }

    private static func correlatorFindsTheEchoDelay() {
        let size = MeetingEchoGate.windowSize
        let them = decimated(speechLike(seconds: 2.1, seed: 11)).prefix(size + 400)
        let noise = decimated(speechLike(seconds: 2.1, seed: 99, amplitude: 0.002))
        let mic = (0..<size).map { 0.05 * them[$0] + noise[$0] }
        let correlator = MeetingEchoCorrelator(size: size)
        let (score, lag) = correlator.correlate(Array(mic), Array(them.dropFirst(400).prefix(size)))
        TestSupport.expectEqual(lag, 400)
        let (delayedScore, delayedLag) = correlator.correlate(Array(them.dropFirst(400).prefix(size)), Array(them.prefix(size)))
        TestSupport.expectEqual(delayedLag, -400)
        TestSupport.expect(delayedScore > 0.9, "A clean shifted copy scores near 1, got \(delayedScore)")
        TestSupport.expect(score > 0.2, "Attenuated echo under noise still scores well, got \(score)")
    }

    private static func correlatorScoresUnrelatedAudioLow() {
        let size = MeetingEchoGate.windowSize
        let a = Array(decimated(speechLike(seconds: 2.1, seed: 5)).prefix(size))
        let b = Array(decimated(speechLike(seconds: 2.1, seed: 6)).prefix(size))
        let (score, _) = MeetingEchoCorrelator(size: size).correlate(a, b)
        TestSupport.expect(score < 0.05, "Unrelated speech has no echo peak, got \(score)")
    }

    private static func speakerEchoIsSuppressedFromItsStart() {
        var gate = MeetingEchoGate()
        let them = MeetingTranscriptCoreTests.silence(seconds: 1) + speechLike(seconds: 11, seed: 21)
        feed(&gate, me: echo(of: them, delay: 1_280, gain: 0.15), them: them)
        let intervals = gate.echoIntervals(overlapping: 0...12)
        TestSupport.expect(gate.isSuppressing, "Steady echo keeps the gate suppressing \(gate.stats) \(intervals)")
        TestSupport.expect(intervals.first.map { $0.lowerBound <= 1.6 } == true,
                           "Suppression reaches back to the echo onset, got \(intervals)")
        TestSupport.expect(covered(intervals, 1.08...12) >= 9.5, "Most of the echo is marked, got \(intervals)")
        TestSupport.expect(covered(intervals, 0...0.8) == 0, "Nothing before the far end spoke is marked")
        TestSupport.expect(gate.stats.locked >= MeetingEchoGate.lockVotes, "Echo analyses agree on the lag")
    }

    private static func suppressionWaitsForAgreeingAnalyses() {
        var gate = MeetingEchoGate()
        let them = speechLike(seconds: 6, seed: 51)
        let mic = echo(of: them, delay: 800, gain: 0.15)
        // The first analysis needs a 2 s window; then 5 agreeing votes and 3 locked analyses in a row.
        feed(&gate, me: Array(mic.prefix(39 * rate / 10)), them: Array(them.prefix(39 * rate / 10)))
        TestSupport.expect(!gate.isSuppressing, "One lock vote too few is not enough at 3.9 s, got \(gate.stats)")
        feed(&gate, me: Array(mic.dropFirst(39 * rate / 10)), them: Array(them.dropFirst(39 * rate / 10)), startingAt: 3.9)
        TestSupport.expect(gate.isSuppressing, "Steady echo is suppressed by 6 s")
    }

    /// Real speaker residue after cancellation scores 0.03-0.17: echo under uncorrelated residue.
    private static func weaklyCorrelatedResidueStillLocks() {
        var gate = MeetingEchoGate()
        let them = speechLike(seconds: 10, seed: 91)
        let residue = speechLike(seconds: 10, seed: 92, amplitude: 0.12)
        let mic = mix(echo(of: them, delay: 800, gain: 0.15), residue).map { $0 * 0.25 }
        let size = MeetingEchoGate.windowSize
        let (score, _) = MeetingEchoCorrelator(size: size).correlate(
            Array(decimated(mic).dropFirst(20_000).prefix(size)), Array(decimated(them).dropFirst(20_000).prefix(size))
        )
        TestSupport.expect(score > 0.05 && score < 0.2, "Fixture correlates like real residue, got \(score)")
        feed(&gate, me: mic, them: them)
        TestSupport.expect(gate.isSuppressing, "Weak but steady echo still locks, got \(gate.stats)")
        TestSupport.expect(covered(gate.echoIntervals(overlapping: 0...10), 3...10) >= 6, "Weak echo is marked")
    }

    private static func talkingOverTheEchoReleasesWithinASecond() {
        var gate = MeetingEchoGate()
        let them = speechLike(seconds: 10, seed: 41)
        let echoed = echo(of: them, delay: 800, gain: 0.15)
        feed(&gate, me: Array(echoed.prefix(8 * rate)), them: Array(them.prefix(8 * rate)))
        TestSupport.expect(gate.isSuppressing, "Echo locked before the interruption")
        let interruption = mix(Array(echoed.dropFirst(8 * rate).prefix(rate)), speechLike(seconds: 1, seed: 42, amplitude: 0.15))
        feed(&gate, me: interruption, them: Array(them.dropFirst(8 * rate).prefix(rate)), startingAt: 8)
        TestSupport.expect(!gate.isSuppressing, "Three loud near-end analyses release before the 2 s hangover")
    }

    private static func nearEndSpeechIsNeverSuppressed() {
        var gate = MeetingEchoGate()
        feed(&gate, me: speechLike(seconds: 12, seed: 31), them: speechLike(seconds: 12, seed: 32))
        TestSupport.expect(gate.echoIntervals(overlapping: 0...12).isEmpty, "Independent speech is never echo")
        TestSupport.expectEqual(gate.stats.suppressed, 0)
        TestSupport.expect(gate.stats.analyses > 30, "The gate kept analysing, got \(gate.stats.analyses)")
    }

    private static func talkingOverTheEchoIsNotMarked() {
        var gate = MeetingEchoGate()
        let them = speechLike(seconds: 14, seed: 41)
        let nearEnd = MeetingTranscriptCoreTests.silence(seconds: 8) + speechLike(seconds: 4, seed: 42, amplitude: 0.15)
        feed(&gate, me: mix(echo(of: them, delay: 800, gain: 0.15), nearEnd), them: them)
        let intervals = gate.echoIntervals(overlapping: 0...14)
        TestSupport.expect(covered(intervals, 3...7.5) >= 4, "The echo before the interruption is marked, got \(intervals)")
        TestSupport.expect(covered(intervals, 9...12) <= 0.7, "Near-end speech over the echo stays, got \(intervals)")
    }

    private static func weakEchoIsCaughtByItsLearnedLevel() {
        var gate = MeetingEchoGate()
        let them = speechLike(seconds: 16, seed: 51)
        // Clean echo for 8 s, then residue that no longer correlates but stays at echo level.
        let residue = speechLike(seconds: 8, seed: 52, amplitude: 0.015)
        let mic = Array(echo(of: them, delay: 800, gain: 0.15).prefix(8 * rate)) + residue
        feed(&gate, me: mic, them: them)
        TestSupport.expect(gate.stats.enveloped >= 5, "Residue at the learned echo level is marked, got \(gate.stats)")
        let intervals = gate.echoIntervals(overlapping: 0...16)
        TestSupport.expect(covered(intervals, 8.5...11.5) >= 2.8, "Residue is marked while the lock times out, got \(intervals)")
        TestSupport.expect(covered(intervals, 12...16) >= 3.5, "Residue after the lock is gone stays marked, got \(intervals)")
    }

    private static func learnedEchoLevelFollowsAVolumeChange() {
        var gate = MeetingEchoGate()
        let them = speechLike(seconds: 18, seed: 55)
        // Speakers turned up 5x at 6 s while echo stays locked, then only uncorrelated residue at the new level.
        let quiet = Array(echo(of: them, delay: 800, gain: 0.1).prefix(6 * rate))
        let loud = Array(echo(of: them, delay: 800, gain: 0.5).dropFirst(6 * rate).prefix(6 * rate))
        let residue = speechLike(seconds: 6, seed: 56, amplitude: 0.05)
        feed(&gate, me: quiet + loud + residue, them: them)
        let intervals = gate.echoIntervals(overlapping: 0...18)
        TestSupport.expect(covered(intervals, 15...18) >= 2.5, "Residue at the louder echo level is still echo, got \(intervals)")
    }

    private static func loudNearEndAfterALockIsNotCaughtByLevel() {
        var gate = MeetingEchoGate()
        let them = speechLike(seconds: 16, seed: 51)
        let mic = Array(echo(of: them, delay: 800, gain: 0.15).prefix(8 * rate)) + speechLike(seconds: 8, seed: 53, amplitude: 0.1)
        feed(&gate, me: mic, them: them)
        let intervals = gate.echoIntervals(overlapping: 0...16)
        TestSupport.expect(covered(intervals, 9...16) <= 0.7, "Loud near-end speech is not echo, got \(intervals)")
        TestSupport.expectEqual(gate.stats.enveloped, 0)
    }

    private static func quietMicIsNotJudged() {
        var gate = MeetingEchoGate()
        feed(&gate, me: speechLike(seconds: 10, seed: 61, amplitude: 0.001), them: speechLike(seconds: 10, seed: 62))
        TestSupport.expect(gate.stats.analyses > 20, "Analyses still run on schedule")
        TestSupport.expectEqual(gate.stats.frozen, gate.stats.analyses)
        TestSupport.expect(gate.echoIntervals(overlapping: 0...10).isEmpty, "A quiet mic is never marked")
    }

    private static func movedCorrelationReleasesQuickly() {
        var gate = MeetingEchoGate()
        let them = speechLike(seconds: 14, seed: 71)
        // The mic hears the far end 100 ms late for 7 s, then 400 ms late: a different path.
        let first = Array(echo(of: them, delay: 1_600, gain: 0.15).prefix(7 * rate))
        let second = Array(echo(of: them, delay: 6_400, gain: 0.15).dropFirst(7 * rate))
        feed(&gate, me: first + second, them: them)
        let intervals = gate.echoIntervals(overlapping: 0...14)
        TestSupport.expect(covered(intervals, 2...7) >= 4, "The first echo path is marked, got \(intervals)")
        TestSupport.expect(gate.isSuppressing, "The new steady path locks again")
    }

    private static func droppedAudioForgetsTheLock() {
        var gate = MeetingEchoGate()
        let them = speechLike(seconds: 8, seed: 81)
        feed(&gate, me: echo(of: them, delay: 800, gain: 0.15), them: them)
        TestSupport.expect(gate.isSuppressing, "Echo locked before the drop")
        // The mic stalls for 3 s: its next batch arrives far later than its sample count predicts.
        gate.append(Array(repeating: 0.01, count: rate / 10), from: .me, arrival: 11.1)
        TestSupport.expect(!gate.isSuppressing, "A clock resync drops the lock measured on the old alignment")
    }

    private static func removingEchoSilencesOnlyEchoAndMovesTheStart() {
        let tone = MeetingTranscriptCoreTests.tone
        let chunk = MeetingAudioChunk(speaker: .me, start: 10.2, audioStart: 10, samples: tone(2, 0.2) + tone(1, 0.2))
        guard let kept = chunk.removingEcho([9...11.5]) else { return TestSupport.expect(false, "Near-end part survives") }
        TestSupport.expectEqual(kept.samples.count, chunk.samples.count)
        TestSupport.expect(kept.samples[0..<(rate + rate / 2)].allSatisfy { $0 == 0 }, "Echo span is silenced")
        TestSupport.expect(kept.samples[(rate * 2)...].contains { $0 != 0 }, "Speech after the echo is kept")
        TestSupport.expectApproximatelyEqual(kept.start, 11.5, accuracy: 0.001)
        TestSupport.expectEqual(kept.audioStart, 10)
        TestSupport.expectEqual(chunk.removingEcho([]), chunk)
        TestSupport.expectEqual(chunk.removingEcho([20...21]), chunk)
    }

    private static func removingEchoDropsAChunkThatWasOnlyEcho() {
        let chunk = MeetingAudioChunk(speaker: .me, start: 5, audioStart: 5, samples: MeetingTranscriptCoreTests.tone(seconds: 2))
        TestSupport.expect(chunk.removingEcho([4.9...7.1]) == nil, "A fully echoed chunk is dropped")
        TestSupport.expect(chunk.removingEcho([4...6.85]) == nil, "Two voiced windows left are still a blip")
        TestSupport.expect(chunk.removingEcho([4...6.6]) != nil, "Four voiced windows left are speech")
    }
}
