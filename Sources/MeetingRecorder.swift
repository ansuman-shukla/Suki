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
    private let callAppsUsingMicrophone: () -> Set<String>
    private let copyToClipboard: @MainActor (String) -> Void
    private let sleepNotifications: NotificationCenter
    private let now: () -> Date
    private var sources: [MeetingAudioSource] = []
    private var queue: MeetingTranscriptionQueue?
    private var buffers: [MeetingSpeaker: MeetingChunkBuffer] = [:]
    private var levels: [MeetingSpeaker: Float] = [:]
    private var receivedSamples: [MeetingSpeaker: Int] = [:]
    private var peakRMS: [MeetingSpeaker: Float] = [:]
    private var micWatchdog = MeetingMicWatchdog()
    private var toastTask: Task<Void, Never>?
    private var autoStopPolicy = MeetingAutoStopPolicy()
    private var autoStopTimer: Timer?
    private var sleepObserver: NSObjectProtocol?
    private let autoStopCheckInterval: TimeInterval = 2

    /// The periodic auto-stop check or the sleep observer is installed.
    var isWatchingForAutoStop: Bool { autoStopTimer != nil || sleepObserver != nil }

    init(
        store: MeetingStore = MeetingStore(),
        makeTranscriber: @escaping () throws -> SpeechToTextService,
        makeSources: @escaping () throws -> [MeetingAudioSource],
        authorizeMicrophone: @escaping () async -> Bool = MeetingRecorder.authorizeMicrophone,
        callAppsUsingMicrophone: @escaping () -> Set<String>,
        copyToClipboard: @escaping @MainActor (String) -> Void = MeetingRecorder.copyToClipboard,
        sleepNotifications: NotificationCenter = NSWorkspace.shared.notificationCenter,
        now: @escaping () -> Date = Date.init
    ) {
        self.store = store
        self.makeTranscriber = makeTranscriber
        self.makeSources = makeSources
        self.authorizeMicrophone = authorizeMicrophone
        self.callAppsUsingMicrophone = callAppsUsingMicrophone
        self.copyToClipboard = copyToClipboard
        self.sleepNotifications = sleepNotifications
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
            liveSegments = []
            let startedAt = now()
            self.startedAt = startedAt
            self.sources = sources
            for source in sources {
                try startCapture(source, startedAt: startedAt)
            }
            phase = .recording
            watchForAutoStop()
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
        await finish(autoStopReason: nil)
    }

    /// Stops by itself: saves like a manual stop, but shows why instead of copying the transcript.
    func autoStop(_ reason: MeetingAutoStopReason) async {
        guard phase == .recording else { return }
        os_log(.info, log: meetingLog, "Meeting auto-stopped: %{public}@", reason.rawValue)
        await finish(autoStopReason: reason)
    }

    /// Applies the auto-stop rules once. Runs every couple of seconds while recording.
    func checkAutoStop() async {
        guard phase == .recording, let startedAt else { return }
        guard let reason = autoStopPolicy.update(
            elapsed: now().timeIntervalSince(startedAt),
            callApps: callAppsUsingMicrophone(),
            lastSpeechTime: buffers.values.compactMap(\.lastSpeechTime).max()
        ) else { return }
        await autoStop(reason)
    }

    private func finish(autoStopReason: MeetingAutoStopReason?) async {
        guard phase == .recording, let startedAt, let queue else { return }
        phase = .finishing
        stopWatchingForAutoStop()
        sources.forEach { $0.stop() }
        sources = []
        let duration = now().timeIntervalSince(startedAt)
        for speaker in MeetingSpeaker.allCases {
            if let chunk = buffers[speaker]?.flush() { queue.enqueue(chunk) }
        }
        await queue.drain()
        let segments = queue.segments.sorted { $0.start < $1.start }
        for speaker in MeetingSpeaker.allCases {
            os_log(.info, log: meetingLog, "Meeting stopped after %.1fs: %{public}@ received %.1fs audio, peak rms %.4f",
                   duration, speaker.rawValue,
                   Double(receivedSamples[speaker] ?? 0) / MeetingTranscriptCore.sampleRate, peakRMS[speaker] ?? 0)
        }
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
        if autoStopReason == nil { copy(meeting) }
        do {
            try store.save(meeting)
            if let autoStopReason { showToast(autoStopReason.notice) }
        } catch {
            errorMessage = autoStopReason == nil ? "Copied, but couldn't save this meeting." : "Couldn't save this meeting."
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
        let otherSpeechTime = buffers.filter { $0.key != speaker }.compactMap(\.value.lastSpeechTime).max()
        for chunk in buffers[speaker]?.append(samples, arrival: arrival, otherSpeechTime: otherSpeechTime) ?? [] {
            queue?.enqueue(chunk)
        }
        if speaker == .me { watchMicrophone(samples) }
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

    private func watchForAutoStop() {
        let timer = Timer(timeInterval: autoStopCheckInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                Task { await self.checkAutoStop() }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        autoStopTimer = timer
        sleepObserver = sleepNotifications.addObserver(
            forName: NSWorkspace.willSleepNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                Task { await self.autoStop(.systemSleep) }
            }
        }
    }

    private func stopWatchingForAutoStop() {
        autoStopTimer?.invalidate()
        autoStopTimer = nil
        if let sleepObserver { sleepNotifications.removeObserver(sleepObserver) }
        sleepObserver = nil
        autoStopPolicy = MeetingAutoStopPolicy()
    }

    private func reset() {
        stopWatchingForAutoStop()
        sources = []
        queue = nil
        buffers = [:]
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
