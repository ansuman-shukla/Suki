import Accelerate
import Foundation

/// What the recorder needs from an echo gate, so tests can script one.
protocol MeetingEchoFiltering {
    var stats: MeetingEchoGate.Stats { get }
    mutating func append(_ samples: [Float], from speaker: MeetingSpeaker, arrival: TimeInterval)
    /// Echo spans in seconds since the meeting began, clipped to `range`, oldest first.
    func echoIntervals(overlapping range: ClosedRange<TimeInterval>) -> [ClosedRange<TimeInterval>]
}

/// Spots the other side leaking from the speakers into the mic after the mic's own echo
/// cancellation. Every `cadence` of mic audio it correlates the latest `windowSize` of both
/// streams with GCC-PHAT. Echo shows up as a strong peak at a steady lag; once enough recent
/// analyses agree on that lag, the gate suppresses mic audio until the correlation moves, the
/// near end talks over the echo, or the lock has been gone for `hangoverSeconds`.
/// Both streams are placed on the meeting clock the same way `MeetingChunkBuffer` does it,
/// so the suppressed intervals line up with chunk times.
struct MeetingEchoGate: MeetingEchoFiltering {
    struct Stats: Equatable {
        var analyses = 0
        /// Analyses skipped because the mic was too quiet to judge.
        var frozen = 0
        /// Analyses whose lag agreed with the locked echo lag.
        var locked = 0
        /// Analyses whose cadence slice was marked as echo.
        var suppressed = 0
        /// Unlocked analyses marked as echo because the mic stayed within the learned echo level.
        var enveloped = 0
    }

    /// Analysis rate; 16 kHz input is decimated 2:1 by averaging pairs.
    static let analysisRate = 8_000
    /// Correlation window, about 2 s at 8 kHz.
    static let windowSize = 16_384
    /// New mic audio that triggers an analysis: 320 ms.
    static let cadence = 2_560
    /// Mic RMS under this over the newest cadence slice is too quiet to judge.
    static let energyFloor: Float = 0.003
    /// GCC-PHAT peaks under this are noise; a perfect delayed copy scores 1.
    static let scoreFloor: Float = 0.03
    /// Recent analyses that vote on the lag lock.
    static let historyCount = 8
    /// Votes within `lagTolerance` of their median lag needed to lock.
    static let lockVotes = 5
    /// Lags this close (35 ms) count as the same echo path.
    static let lagTolerance = 280
    /// Largest echo lag (500 ms) either way; stream alignment comes from arrival times.
    static let maxLag = 4_000
    /// Consecutive locked analyses before suppression engages.
    static let engageCount = 3
    /// Consecutive near-end analyses (correlation moved or double talk) that release at once.
    static let fastReleaseCount = 3
    /// Analysed time without a lock that releases suppression; frozen time does not count.
    static let hangoverSeconds: TimeInterval = 2
    /// Analyses at the locked lag needed after a frozen stretch before the lock is trusted again.
    static let probationCount = 2
    /// Consecutive frozen analyses that count as a frozen stretch; one quiet gap between words does not.
    static let frozenStretch = 2
    /// Far-end level above which the learned echo level is used to judge unlocked mic audio.
    static let farActiveLevel: Float = 0.01
    /// Mic louder than this multiple (12 dB) of the predicted echo is the near end talking.
    static let doubleTalkRatio: Float = 4
    /// Weight of the newest echo coupling measurement in its moving average.
    static let couplingSmoothing: Float = 0.2
    /// Furthest suppression reaches back over the evidence that engaged it.
    static let maxBackfillSeconds: TimeInterval = 5
    /// How long after a mic chunk ends the gate may still mark it as echo: lock votes plus engage
    /// analyses, with slack for quiet gaps between words.
    static let decisionSeconds: TimeInterval = 3.5
    /// Far-end speech further back than this before a mic chunk cannot echo into it: covers the
    /// largest lag plus the correlation window the evidence is measured over.
    static let echoReachSeconds: TimeInterval = 2.5
    /// Echo intervals ending this long before the newest analysis are forgotten.
    static let retentionSeconds: TimeInterval = 60
    /// Ring buffer length per stream; streams may drift `ringCapacity - windowSize` apart.
    static let ringCapacity = 32_768

    private struct Stream {
        var ring = [Float](repeating: 0, count: MeetingEchoGate.ringCapacity)
        /// Meeting time of the first counted sample; moves only when the clock resyncs.
        var origin: TimeInterval = 0
        /// 16 kHz samples received since `origin`.
        var received = 0
        /// Absolute 8 kHz index of the first sample, and one past the newest.
        var first: Int?
        var end = 0
        /// Odd sample waiting for its decimation partner.
        var carry: Float?

        /// Returns true when the clock resynced because the source dropped audio.
        mutating func append(_ samples: [Float], arrival: TimeInterval) -> Bool {
            let rate = MeetingTranscriptCore.sampleRate
            let batchStart = arrival - Double(samples.count) / rate
            var resynced = false
            if first == nil {
                origin = max(0, batchStart)
                end = MeetingEchoGate.index(origin)
                first = end
            } else {
                let counted = origin + Double(received) / rate
                if batchStart - counted > MeetingTranscriptCore.clockResyncSeconds {
                    origin += batchStart - counted
                    let resumed = MeetingEchoGate.index(origin + Double(received) / rate)
                    for index in max(end, resumed - MeetingEchoGate.ringCapacity)..<resumed {
                        ring[index & MeetingEchoGate.ringMask] = 0
                    }
                    end = resumed
                    carry = nil
                    resynced = true
                }
            }
            received += samples.count
            for sample in samples {
                if let pending = carry {
                    ring[end & MeetingEchoGate.ringMask] = (pending + sample) / 2
                    end += 1
                    carry = nil
                } else {
                    carry = sample
                }
            }
            return resynced
        }
    }

    private struct Evidence {
        let end: Int
        let score: Float
        let lag: Int
    }

    private struct Lock {
        let lag: Int
        /// End of the oldest analysis in the unbroken run of votes for `lag`.
        let earliestEnd: Int
    }

    /// How the far end reaches the mic, measured while echo was locked. Outlives the suppression
    /// so weakly correlated echo, common at higher speaker volume, is still recognised by level.
    private struct EchoPath {
        var lag: Int
        var coupling: Float
    }

    private struct Suppression {
        var lag: Int
        /// Moving average of mic level over the far-end level while echo is locked.
        var coupling: Float
        var unlockedSamples = 0
        var nearEndRun = 0
    }

    private static let ringMask = ringCapacity - 1
    private static let hangoverSamples = Int(hangoverSeconds * Double(analysisRate))
    private static let backfillSamples = Int(maxBackfillSeconds * Double(analysisRate))
    /// Keeps level ratios finite when the far end is digitally silent.
    private static let minimumLevel: Float = 1e-6

    private(set) var stats = Stats()
    var isSuppressing: Bool { suppression != nil }
    private let correlator = MeetingEchoCorrelator(size: windowSize)
    private var mic = Stream()
    private var them = Stream()
    private var micWindow = [Float](repeating: 0, count: windowSize)
    private var themWindow = [Float](repeating: 0, count: windowSize)
    private var nextAnalysisEnd: Int?
    private var history: [Evidence] = []
    private var lockedRun = 0
    private var probation = 0
    private var frozenRun = 0
    private var echoPath: EchoPath?
    private var suppression: Suppression?
    private var intervals: [ClosedRange<TimeInterval>] = []

    /// Feeds one 16 kHz batch; `arrival` is seconds since the meeting began when it was delivered.
    mutating func append(_ samples: [Float], from speaker: MeetingSpeaker, arrival: TimeInterval) {
        guard !samples.isEmpty else { return }
        let resynced: Bool
        switch speaker {
        case .me:
            resynced = mic.append(samples, arrival: arrival)
            if nextAnalysisEnd == nil, let first = mic.first { nextAnalysisEnd = first + Self.cadence }
        case .them:
            resynced = them.append(samples, arrival: arrival)
        }
        if resynced { startNewEpoch() }
        runDueAnalyses()
    }

    func echoIntervals(overlapping range: ClosedRange<TimeInterval>) -> [ClosedRange<TimeInterval>] {
        intervals.compactMap { interval in
            guard interval.overlaps(range) else { return nil }
            return max(interval.lowerBound, range.lowerBound)...min(interval.upperBound, range.upperBound)
        }
    }

    private static func index(_ seconds: TimeInterval) -> Int {
        Int((seconds * Double(analysisRate)).rounded())
    }

    private static func seconds(_ index: Int) -> TimeInterval {
        Double(index) / Double(analysisRate)
    }

    /// A dropped-audio gap breaks the alignment the lock was measured on, so start over.
    private mutating func startNewEpoch() {
        history.removeAll(keepingCapacity: true)
        lockedRun = 0
        probation = 0
        frozenRun = 0
        suppression = nil
        echoPath = nil
    }

    /// Analyses run on a grid every `cadence` of mic time, once both streams cover the window.
    private mutating func runDueAnalyses() {
        guard var next = nextAnalysisEnd, let micFirst = mic.first, let themFirst = them.first else { return }
        let covered = max(max(micFirst, themFirst), max(mic.end, them.end) - Self.ringCapacity) + Self.windowSize
        if next < covered {
            next += (covered - next + Self.cadence - 1) / Self.cadence * Self.cadence
        }
        while next <= min(mic.end, them.end) {
            analyze(endingAt: next)
            next += Self.cadence
        }
        nextAnalysisEnd = next
    }

    private mutating func analyze(endingAt end: Int) {
        stats.analyses += 1
        copyWindows(endingAt: end)
        let micLevel = Self.level(micWindow, from: Self.windowSize - Self.cadence, count: Self.cadence)
        guard micLevel >= Self.energyFloor else {
            stats.frozen += 1
            frozenRun += 1
            if frozenRun >= Self.frozenStretch { probation = Self.probationCount }
            return
        }
        frozenRun = 0
        let evidence = measure(endingAt: end)
        history.append(evidence)
        if history.count > Self.historyCount { history.removeFirst() }
        let lock = currentLock(endingAt: end)
        let reference = suppression?.lag ?? lock?.lag
        let scored = evidence.score >= Self.scoreFloor
        let consistent = scored && reference.map { abs(evidence.lag - $0) <= Self.lagTolerance } == true
        let moved = scored && reference.map { abs(evidence.lag - $0) > Self.lagTolerance } == true
        if reference == nil { probation = 0 }
        let trusted = probation == 0
        if consistent {
            stats.locked += 1
            probation = max(0, probation - 1)
        }
        if suppression == nil {
            lockedRun = consistent ? lockedRun + 1 : 0
            if lockedRun >= Self.engageCount, trusted, let lock {
                engage(lock, micLevel: micLevel, endingAt: end)
            } else if let path = echoPath, micLevel <= Self.doubleTalkRatio * path.coupling * farEndLevel(lag: path.lag),
                      farEndLevel(lag: path.lag) >= Self.farActiveLevel {
                stats.enveloped += 1
                mark(from: end - Self.cadence, to: end)
            }
        } else {
            judgeWhileSuppressing(consistent: consistent && trusted, moved: moved, micLevel: micLevel, endingAt: end)
        }
        let cutoff = Self.seconds(end) - Self.retentionSeconds
        intervals.removeAll { $0.upperBound < cutoff }
    }

    private mutating func copyWindows(endingAt end: Int) {
        let start = end - Self.windowSize
        for index in 0..<Self.windowSize {
            let slot = (start + index) & Self.ringMask
            micWindow[index] = mic.ring[slot]
            themWindow[index] = them.ring[slot]
        }
    }

    private func measure(endingAt end: Int) -> Evidence {
        let quiet = Self.level(micWindow, from: 0, count: Self.windowSize) < Self.energyFloor
            || Self.level(themWindow, from: 0, count: Self.windowSize) < Self.energyFloor
        guard !quiet else { return Evidence(end: end, score: 0, lag: 0) }
        let (score, lag) = correlator.correlate(micWindow, themWindow)
        return Evidence(end: end, score: score, lag: lag)
    }

    /// The lag most recent scored analyses agree on, if at least `lockVotes` of them do.
    private func currentLock(endingAt end: Int) -> Lock? {
        let scored = history.filter { $0.score >= Self.scoreFloor }
        guard scored.count >= Self.lockVotes else { return nil }
        let median = scored.map(\.lag).sorted()[scored.count / 2]
        guard abs(median) <= Self.maxLag,
              scored.filter({ abs($0.lag - median) <= Self.lagTolerance }).count >= Self.lockVotes else { return nil }
        var earliest = end
        for evidence in history.reversed() {
            guard evidence.score >= Self.scoreFloor, abs(evidence.lag - median) <= Self.lagTolerance else { break }
            earliest = evidence.end
        }
        return Lock(lag: median, earliestEnd: earliest)
    }

    /// Suppresses from one cadence before the oldest slice of the run that locked, so the
    /// echo heard while the evidence built up is covered too.
    private mutating func engage(_ lock: Lock, micLevel: Float, endingAt end: Int) {
        let farLevel = farEndLevel(lag: lock.lag)
        let coupling = micLevel / max(farLevel, Self.minimumLevel)
        suppression = Suppression(lag: lock.lag, coupling: coupling)
        echoPath = EchoPath(lag: lock.lag, coupling: coupling)
        let evidenceStart = lock.earliestEnd - 2 * Self.cadence
        mark(from: max(evidenceStart, end - Self.backfillSamples), to: end)
    }

    private mutating func judgeWhileSuppressing(consistent: Bool, moved: Bool, micLevel: Float, endingAt end: Int) {
        guard var state = suppression else { return }
        let farLevel = farEndLevel(lag: state.lag)
        let nearEndTalks = micLevel > Self.doubleTalkRatio * state.coupling * farLevel
        if consistent && !nearEndTalks {
            state.unlockedSamples = 0
            state.nearEndRun = 0
            state.coupling += Self.couplingSmoothing * (micLevel / max(farLevel, Self.minimumLevel) - state.coupling)
            echoPath = EchoPath(lag: state.lag, coupling: state.coupling)
            mark(from: end - Self.cadence, to: end)
        } else if moved || nearEndTalks {
            state.nearEndRun += 1
            state.unlockedSamples += Self.cadence
        } else {
            state.nearEndRun = 0
            state.unlockedSamples += Self.cadence
            mark(from: end - Self.cadence, to: end)
        }
        if state.nearEndRun >= Self.fastReleaseCount || state.unlockedSamples >= Self.hangoverSamples {
            suppression = nil
            lockedRun = 0
        } else {
            suppression = state
        }
    }

    /// Far-end level over the slice that would echo into the newest mic slice.
    private func farEndLevel(lag: Int) -> Float {
        let offset = min(max(Self.windowSize - Self.cadence - lag, 0), Self.windowSize - Self.cadence)
        return Self.level(themWindow, from: offset, count: Self.cadence)
    }

    private mutating func mark(from start: Int, to end: Int) {
        stats.suppressed += 1
        var lower = Self.seconds(max(0, start))
        var upper = Self.seconds(end)
        while let last = intervals.last, last.upperBound >= lower {
            lower = min(lower, last.lowerBound)
            upper = max(upper, last.upperBound)
            intervals.removeLast()
        }
        intervals.append(lower...upper)
    }

    private static func level(_ samples: [Float], from offset: Int, count: Int) -> Float {
        var result: Float = 0
        samples.withUnsafeBufferPointer { vDSP_rmsqv($0.baseAddress! + offset, 1, &result, vDSP_Length(count)) }
        return result
    }
}

/// GCC-PHAT between two equal-length windows with cached vDSP setups and scratch buffers.
/// Not thread safe; one gate uses it from one thread.
final class MeetingEchoCorrelator {
    let size: Int
    private let half: Int
    private let forward: vDSP_DFT_Setup
    private let inverse: vDSP_DFT_Setup
    private let real: UnsafeMutablePointer<Float>
    private let micRe: UnsafeMutablePointer<Float>
    private let micIm: UnsafeMutablePointer<Float>
    private let themRe: UnsafeMutablePointer<Float>
    private let themIm: UnsafeMutablePointer<Float>
    private let crossRe: UnsafeMutablePointer<Float>
    private let crossIm: UnsafeMutablePointer<Float>
    /// Makes a perfect delayed copy score exactly 1, whatever vDSP's transform scaling is.
    private var scale: Float = 1

    /// `size` must be a power of two of at least 16.
    init(size: Int) {
        precondition(size >= 16 && size & (size - 1) == 0, "GCC-PHAT size must be a power of two")
        guard let forward = vDSP_DFT_zrop_CreateSetup(nil, vDSP_Length(size), .FORWARD),
              let inverse = vDSP_DFT_zrop_CreateSetup(forward, vDSP_Length(size), .INVERSE) else {
            preconditionFailure("vDSP could not set up a \(size)-point real DFT")
        }
        self.size = size
        half = size / 2
        self.forward = forward
        self.inverse = inverse
        real = .allocate(capacity: size)
        micRe = .allocate(capacity: half)
        micIm = .allocate(capacity: half)
        themRe = .allocate(capacity: half)
        themIm = .allocate(capacity: half)
        crossRe = .allocate(capacity: half)
        crossIm = .allocate(capacity: half)
        crossRe.initialize(repeating: 1, count: half)
        crossIm.initialize(repeating: 0, count: half)
        crossRe[0] = 0
        scale = 1 / inverseTransformPeak()
    }

    deinit {
        vDSP_DFT_DestroySetup(forward)
        vDSP_DFT_DestroySetup(inverse)
        [real, micRe, micIm, themRe, themIm, crossRe, crossIm].forEach { $0.deallocate() }
    }

    /// Peak of the phase-transform cross-correlation and its lag in samples; a positive lag
    /// means `mic` hears `them` that many samples later.
    func correlate(_ mic: [Float], _ them: [Float]) -> (score: Float, lag: Int) {
        precondition(mic.count == size && them.count == size, "GCC-PHAT windows must be \(size) samples")
        mic.withUnsafeBufferPointer { spectrum(of: $0.baseAddress!, re: micRe, im: micIm) }
        them.withUnsafeBufferPointer { spectrum(of: $0.baseAddress!, re: themRe, im: themIm) }
        let count = vDSP_Length(half)
        var micSpectrum = DSPSplitComplex(realp: micRe, imagp: micIm)
        var themSpectrum = DSPSplitComplex(realp: themRe, imagp: themIm)
        var cross = DSPSplitComplex(realp: crossRe, imagp: crossIm)
        vDSP_zvmul(&themSpectrum, 1, &micSpectrum, 1, &cross, 1, count, -1)
        // Bin 0 packs DC and Nyquist, which carry no timing.
        crossRe[0] = 0
        crossIm[0] = 0
        vDSP_zvabs(&cross, 1, real, 1, count)
        var tiny = Float.leastNormalMagnitude
        vDSP_vsadd(real, 1, &tiny, real, 1, count)
        vDSP_vdiv(real, 1, crossRe, 1, crossRe, 1, count)
        vDSP_vdiv(real, 1, crossIm, 1, crossIm, 1, count)
        var peak: Float = 0
        var index: vDSP_Length = 0
        inverseTransform()
        vDSP_maxmgvi(real, 1, &peak, &index, vDSP_Length(size))
        let lag = Int(index) < half ? Int(index) : Int(index) - size
        return (peak * scale, lag)
    }

    /// Mean-removed packed real spectrum of `samples`.
    private func spectrum(of samples: UnsafePointer<Float>, re: UnsafeMutablePointer<Float>, im: UnsafeMutablePointer<Float>) {
        var mean: Float = 0
        vDSP_meanv(samples, 1, &mean, vDSP_Length(size))
        var negativeMean = -mean
        vDSP_vsadd(samples, 1, &negativeMean, real, 1, vDSP_Length(size))
        var packed = DSPSplitComplex(realp: crossRe, imagp: crossIm)
        real.withMemoryRebound(to: DSPComplex.self, capacity: half) {
            vDSP_ctoz($0, 2, &packed, 1, vDSP_Length(half))
        }
        vDSP_DFT_Execute(forward, crossRe, crossIm, re, im)
    }

    /// Inverse of the cross spectrum into `real`, reusing the mic spectrum as scratch.
    private func inverseTransform() {
        vDSP_DFT_Execute(inverse, crossRe, crossIm, micRe, micIm)
        var packed = DSPSplitComplex(realp: micRe, imagp: micIm)
        real.withMemoryRebound(to: DSPComplex.self, capacity: half) {
            vDSP_ztoc(&packed, 1, $0, 2, vDSP_Length(half))
        }
    }

    private func inverseTransformPeak() -> Float {
        inverseTransform()
        return real[0]
    }
}

extension MeetingAudioChunk {
    /// The chunk with `echo` silenced, starting at its first voiced window that is left.
    /// Nil when fewer than `minVoicedWindows` voiced windows remain.
    func removingEcho(_ echo: [ClosedRange<TimeInterval>]) -> MeetingAudioChunk? {
        guard !echo.isEmpty else { return self }
        let rate = MeetingTranscriptCore.sampleRate
        var kept = samples
        for interval in echo {
            let lower = max(0, Int(((interval.lowerBound - audioStart) * rate).rounded()))
            let upper = min(kept.count, Int(((interval.upperBound - audioStart) * rate).rounded()))
            guard lower < upper else { continue }
            kept.replaceSubrange(lower..<upper, with: repeatElement(0, count: upper - lower))
        }
        let levels = MeetingTranscriptCore.windowLevels(kept)
        guard !MeetingTranscriptCore.isSilent(levels),
              let firstVoiced = levels.firstIndex(where: { $0 >= MeetingTranscriptCore.silenceRMS }) else { return nil }
        let voicedStart = audioStart + Double(firstVoiced) * MeetingTranscriptCore.levelWindowSeconds
        return MeetingAudioChunk(speaker: speaker, start: max(start, voicedStart), audioStart: audioStart, samples: kept)
    }
}
