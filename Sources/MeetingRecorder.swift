import AppKit
import AVFoundation
import os

/// Runs a meeting recording: both audio sources, chunking, transcription, and saving.
@MainActor
final class MeetingRecorder: ObservableObject {
    @Published private(set) var phase: MeetingPhase = .idle
    @Published private(set) var startedAt: Date?
    @Published private(set) var liveSegments: [MeetingSegment] = []
    /// 0...1 display level of the louder side, for the waveform.
    @Published private(set) var level: Float = 0
    @Published private(set) var meetings: [MeetingRecord]
    @Published private(set) var toast: String?
    /// The mic is being blanked by another app and Suki is trying to get it back.
    @Published private(set) var micBlocked = false
    @Published var errorMessage: String?

    var isActive: Bool { phase != .idle }

    private let store: MeetingStore
    private let makeTranscriber: () throws -> SpeechToTextService
    private let makeSources: () throws -> [MeetingAudioSource]
    private let authorizeMicrophone: () async -> Bool
    private let copyToClipboard: @MainActor (String) -> Void
    private let makeEchoGate: () -> any MeetingEchoFiltering
    private let now: () -> Date
    private var sources: [MeetingAudioSource] = []
    private var queue: MeetingTranscriptionQueue?
    private var buffers: [MeetingSpeaker: MeetingChunkBuffer] = [:]
    private var levels: [MeetingSpeaker: Float] = [:]
    private var receivedSamples: [MeetingSpeaker: Int] = [:]
    private var peakRMS: [MeetingSpeaker: Float] = [:]
    private var micWatchdog = MeetingMicWatchdog()
    private var echoGate: any MeetingEchoFiltering = MeetingEchoGate()
    /// Me chunks wait `MeetingEchoGate.decisionSeconds` so a lock found after they were cut still covers them.
    private var heldMeChunks: [MeetingAudioChunk] = []
    private var echoDroppedChunks = 0
    private var toastTask: Task<Void, Never>?

    init(
        store: MeetingStore = MeetingStore(),
        makeTranscriber: @escaping () throws -> SpeechToTextService,
        makeSources: @escaping () throws -> [MeetingAudioSource],
        authorizeMicrophone: @escaping () async -> Bool = MeetingRecorder.authorizeMicrophone,
        copyToClipboard: @escaping @MainActor (String) -> Void = MeetingRecorder.copyToClipboard,
        makeEchoGate: @escaping () -> any MeetingEchoFiltering = { MeetingEchoGate() },
        now: @escaping () -> Date = Date.init
    ) {
        self.store = store
        self.makeTranscriber = makeTranscriber
        self.makeSources = makeSources
        self.authorizeMicrophone = authorizeMicrophone
        self.copyToClipboard = copyToClipboard
        self.makeEchoGate = makeEchoGate
        self.now = now
        meetings = store.loadAll()
    }

    func toggle() async {
        switch phase {
        case .idle: await start()
        case .recording: await stop()
        case .starting, .finishing: break
        }
    }

    func start() async {
        guard phase == .idle else { return }
        errorMessage = nil
        phase = .starting
        do {
            let sources = try makeSources()
            let transcriber = try makeTranscriber()
            guard await authorizeMicrophone() else { throw MeetingRecorderError.microphoneDenied }
            let queue = MeetingTranscriptionQueue(transcriber: transcriber)
            queue.onSegmentsChange = { [weak self] in self?.liveSegments = MeetingTranscriptCore.merged($0) }
            self.queue = queue
            buffers = Dictionary(uniqueKeysWithValues: MeetingSpeaker.allCases.map { ($0, MeetingChunkBuffer(speaker: $0)) })
            echoGate = makeEchoGate()
            liveSegments = []
            let startedAt = now()
            self.startedAt = startedAt
            self.sources = sources
            for source in sources {
                try startCapture(source, startedAt: startedAt)
            }
            phase = .recording
            os_log(.info, log: meetingLog, "Meeting started with sources: %{public}@",
                   sources.map(\.speaker.rawValue).joined(separator: ","))
        } catch {
            os_log(.error, log: meetingLog, "Meeting start failed: %{public}@", String(describing: error))
            sources.forEach { $0.stop() }
            queue?.cancelAll()
            reset()
            errorMessage = error.localizedDescription
        }
    }

    func stop() async {
        guard phase == .recording, let startedAt, let queue else { return }
        phase = .finishing
        sources.forEach { $0.stop() }
        sources = []
        let duration = now().timeIntervalSince(startedAt)
        for speaker in MeetingSpeaker.allCases {
            if let chunk = buffers[speaker]?.flush() { enqueue(chunk) }
        }
        releaseHeldMeChunks(through: .infinity)
        await queue.drain()
        let segments = queue.segments.sorted { $0.start < $1.start }
        for speaker in MeetingSpeaker.allCases {
            os_log(.info, log: meetingLog, "Meeting stopped after %.1fs: %{public}@ received %.1fs audio, peak rms %.4f",
                   duration, speaker.rawValue,
                   Double(receivedSamples[speaker] ?? 0) / MeetingTranscriptCore.sampleRate, peakRMS[speaker] ?? 0)
        }
        let echo = echoGate.stats
        os_log(.info, log: meetingLog, "Meeting echo gate: %d analyses, %d frozen, %d locked, %d suppressed, %d enveloped, %d me chunks dropped",
               echo.analyses, echo.frozen, echo.locked, echo.suppressed, echo.enveloped, echoDroppedChunks)
        os_log(.info, log: meetingLog, "Meeting produced %d segments", segments.count)
        reset()
        guard !segments.isEmpty else {
            errorMessage = "No speech was picked up, so nothing was saved."
            return
        }
        let meeting = MeetingRecord(
            title: MeetingTranscriptCore.defaultTitle(for: startedAt),
            date: startedAt,
            duration: duration,
            segments: segments
        )
        meetings.insert(meeting, at: 0)
        copy(meeting)
        do {
            try store.save(meeting)
        } catch {
            errorMessage = "Copied, but couldn't save this meeting."
        }
    }

    func copy(_ meeting: MeetingRecord) {
        copyToClipboard(meeting.transcript)
        showToast("Copied to clipboard")
    }

    func delete(_ meeting: MeetingRecord) {
        do {
            try store.delete(id: meeting.id)
            meetings.removeAll { $0.id == meeting.id }
        } catch {
            errorMessage = "Couldn't delete this meeting."
        }
    }

    /// Blank or unchanged titles keep the old one. Memory only changes once the new title is on disk.
    func rename(_ meeting: MeetingRecord, to title: String) {
        guard let index = meetings.firstIndex(where: { $0.id == meeting.id }),
              let title = MeetingTranscriptCore.renamedTitle(title, current: meetings[index].title) else { return }
        var renamed = meetings[index]
        renamed.title = title
        do {
            try store.save(renamed)
            meetings[index] = renamed
        } catch {
            errorMessage = "Couldn't rename this meeting."
        }
    }

    /// Feeds one batch of a speaker's samples; cuts and uploads a chunk when one is ready.
    /// `arrival` is seconds since the start when the audio thread delivered the batch.
    func ingest(_ samples: [Float], from speaker: MeetingSpeaker, arrival: TimeInterval) {
        guard phase == .recording else { return }
        let rms = MeetingTranscriptCore.rms(samples)
        receivedSamples[speaker, default: 0] += samples.count
        peakRMS[speaker] = max(peakRMS[speaker] ?? 0, rms)
        levels[speaker] = MeetingTranscriptCore.displayLevel(rms: rms)
        let loudest = levels.values.max() ?? 0
        if abs(loudest - level) > 0.02 { level = loudest }
        echoGate.append(samples, from: speaker, arrival: arrival)
        let otherSpeechTime = buffers.filter { $0.key != speaker }.compactMap(\.value.lastSpeechTime).max()
        for chunk in buffers[speaker]?.append(samples, arrival: arrival, otherSpeechTime: otherSpeechTime) ?? [] {
            enqueue(chunk)
        }
        releaseHeldMeChunks(through: arrival)
        if speaker == .me { watchMicrophone(samples) }
    }

    /// Them chunks upload right away. Me chunks the other side may have echoed into wait for the
    /// echo gate to decide; with the other side quiet since before the chunk, there is nothing to cancel.
    private func enqueue(_ chunk: MeetingAudioChunk) {
        let farEndSpoke = (buffers[.them]?.lastSpeechTime ?? -.infinity) > chunk.audioStart - MeetingEchoGate.echoReachSeconds
        guard chunk.speaker == .me, farEndSpoke || !heldMeChunks.isEmpty else { return queue?.enqueue(chunk) ?? () }
        heldMeChunks.append(chunk)
    }

    /// Uploads held Me chunks that ended `MeetingEchoGate.decisionSeconds` before `time`,
    /// with speaker echo silenced. Chunks left with no real speech are dropped.
    private func releaseHeldMeChunks(through time: TimeInterval) {
        while let chunk = heldMeChunks.first,
              chunk.audioStart + chunk.duration + MeetingEchoGate.decisionSeconds <= time {
            heldMeChunks.removeFirst()
            let span = chunk.audioStart...(chunk.audioStart + chunk.duration)
            guard let kept = chunk.removingEcho(echoGate.echoIntervals(overlapping: span)) else {
                echoDroppedChunks += 1
                os_log(.info, log: meetingLog, "me chunk %.1fs dropped as echo", chunk.duration)
                continue
            }
            queue?.enqueue(kept)
        }
    }

    private func startCapture(_ source: MeetingAudioSource, startedAt: Date) throws {
        let speaker = source.speaker, now = now
        try source.start { [weak self] samples in
            let arrival = now().timeIntervalSince(startedAt)
            DispatchQueue.main.async { self?.ingest(samples, from: speaker, arrival: arrival) }
        }
    }

    private func watchMicrophone(_ samples: [Float]) {
        switch micWatchdog.inspect(samples) {
        case .fine:
            break
        case .recovered:
            micBlocked = false
            os_log(.info, log: meetingLog, "Meeting mic recovered")
        case .restart:
            micBlocked = true
            guard let startedAt, let mic = sources.first(where: { $0.speaker == .me }) else { return }
            os_log(.info, log: meetingLog, "Meeting mic is blanked by another app, restarting it")
            mic.stop()
            do {
                try startCapture(mic, startedAt: startedAt)
            } catch {
                os_log(.error, log: meetingLog, "Meeting mic restart failed: %{public}@", String(describing: error))
            }
        }
    }

    private func reset() {
        sources = []
        queue = nil
        buffers = [:]
        heldMeChunks = []
        echoDroppedChunks = 0
        levels = [:]
        receivedSamples = [:]
        peakRMS = [:]
        micWatchdog = MeetingMicWatchdog()
        micBlocked = false
        level = 0
        startedAt = nil
        liveSegments = []
        phase = .idle
    }

    private func showToast(_ message: String) {
        toast = message
        toastTask?.cancel()
        toastTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            guard !Task.isCancelled else { return }
            self?.toast = nil
        }
    }

    nonisolated static func authorizeMicrophone() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .audio)
        default: return false
        }
    }

    static func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
