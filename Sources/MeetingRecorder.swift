import AppKit
import AVFoundation

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
    @Published var errorMessage: String?

    var isActive: Bool { phase != .idle }

    private let store: MeetingStore
    private let makeTranscriber: () throws -> SpeechToTextService
    private let makeSources: () throws -> [MeetingAudioSource]
    private let authorizeMicrophone: () async -> Bool
    private let copyToClipboard: @MainActor (String) -> Void
    private let now: () -> Date
    private var sources: [MeetingAudioSource] = []
    private var queue: MeetingTranscriptionQueue?
    private var buffers: [MeetingSpeaker: MeetingChunkBuffer] = [:]
    private var levels: [MeetingSpeaker: Float] = [:]
    private var toastTask: Task<Void, Never>?

    init(
        store: MeetingStore = MeetingStore(),
        makeTranscriber: @escaping () throws -> SpeechToTextService,
        makeSources: @escaping () throws -> [MeetingAudioSource],
        authorizeMicrophone: @escaping () async -> Bool = MeetingRecorder.authorizeMicrophone,
        copyToClipboard: @escaping @MainActor (String) -> Void = MeetingRecorder.copyToClipboard,
        now: @escaping () -> Date = Date.init
    ) {
        self.store = store
        self.makeTranscriber = makeTranscriber
        self.makeSources = makeSources
        self.authorizeMicrophone = authorizeMicrophone
        self.copyToClipboard = copyToClipboard
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
            let startedAt = now(), now = now
            self.startedAt = startedAt
            self.sources = sources
            for source in sources {
                let speaker = source.speaker
                try source.start { [weak self] samples in
                    let arrival = now().timeIntervalSince(startedAt)
                    DispatchQueue.main.async { self?.ingest(samples, from: speaker, arrival: arrival) }
                }
            }
            phase = .recording
        } catch {
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
            if let chunk = buffers[speaker]?.flush() { queue.enqueue(chunk) }
        }
        await queue.drain()
        let segments = queue.segments.sorted { $0.start < $1.start }
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

    /// Feeds one batch of a speaker's samples; cuts and uploads a chunk when one is ready.
    /// `arrival` is seconds since the start when the audio thread delivered the batch.
    func ingest(_ samples: [Float], from speaker: MeetingSpeaker, arrival: TimeInterval) {
        guard phase == .recording else { return }
        levels[speaker] = MeetingTranscriptCore.displayLevel(rms: MeetingTranscriptCore.rms(samples))
        let loudest = levels.values.max() ?? 0
        if abs(loudest - level) > 0.02 { level = loudest }
        if let chunk = buffers[speaker]?.append(samples, arrival: arrival) {
            queue?.enqueue(chunk)
        }
    }

    private func reset() {
        sources = []
        queue = nil
        buffers = [:]
        levels = [:]
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
