import Foundation

private final class FakeSource: MeetingAudioSource {
    let speaker: MeetingSpeaker
    var failsToStart = false
    private(set) var startCount = 0
    private(set) var stopCount = 0
    private var onSamples: (([Float]) -> Void)?

    init(_ speaker: MeetingSpeaker) {
        self.speaker = speaker
    }

    func start(onSamples: @escaping ([Float]) -> Void) throws {
        startCount += 1
        if failsToStart { throw MeetingRecorderError.audioSetupFailed("synthetic device") }
        self.onSamples = onSamples
    }

    func stop() {
        stopCount += 1
        onSamples = nil
    }

    func emit(_ samples: [Float], batch: Int = 1_600) {
        stride(from: 0, to: samples.count, by: batch).forEach {
            onSamples?(Array(samples[$0..<min($0 + batch, samples.count)]))
        }
    }
}

private final class EchoTranscriber: SpeechToTextService {
    private(set) var calls = 0

    func transcribe(fileURL: URL) async throws -> String {
        calls += 1
        let seconds = (try Data(contentsOf: fileURL).count - 44) / 32_000
        return "\(seconds) seconds"
    }
}

@MainActor
private final class Harness {
    let me = FakeSource(.me)
    let them = FakeSource(.them)
    let transcriber = EchoTranscriber()
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("MeetingRecorderTests-\(UUID().uuidString)")
    var clock = Date(timeIntervalSince1970: 1_700_000_000)
    var copied: [String] = []
    var transcriberError: Error?
    var sourcesError: Error?
    var micAllowed = true
    var micAsked = 0
    lazy var store = MeetingStore(directory: directory)
    lazy var recorder = MeetingRecorder(
        store: store,
        makeTranscriber: { [unowned self] in
            if let transcriberError { throw transcriberError }
            return transcriber
        },
        makeSources: { [unowned self] in
            if let sourcesError { throw sourcesError }
            return [me, them]
        },
        authorizeMicrophone: { [unowned self] in
            micAsked += 1
            return micAllowed
        },
        copyToClipboard: { [unowned self] in copied.append($0) },
        now: { [unowned self] in clock }
    )

    deinit {
        try? FileManager.default.removeItem(at: directory)
    }

    /// Lets main-queue sample deliveries and transcription tasks run, up to two seconds.
    func settle(until done: (() -> Bool)? = nil) async {
        for _ in 0..<(done == nil ? 1 : 40) where done?() != true {
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
    }
}

enum MeetingRecorderTests {
    @MainActor
    static func run() async {
        await unsupportedSystemStopsBeforeAnything()
        await missingKeyStopsBeforePermissionPrompt()
        await deniedMicrophoneShowsGuidance()
        await sourceFailureStopsEverySource()
        await recordingTranscribesCopiesAndSaves()
        await silentMeetingSavesNothing()
        await copyAndDeletePastMeetings()
        await blankedMicRestartsAndRecovers()
        await silentSystemAudioNeverRestartsAnything()
    }

    @MainActor
    private static func expectIdleWithoutCapture(_ harness: Harness, message: String) {
        TestSupport.expectEqual(harness.recorder.phase, .idle)
        TestSupport.expectEqual(harness.recorder.errorMessage, message)
        TestSupport.expect(harness.recorder.startedAt == nil, "No start time after a failed start")
    }

    @MainActor
    private static func unsupportedSystemStopsBeforeAnything() async {
        let harness = Harness()
        harness.sourcesError = MeetingRecorderError.unsupportedSystem
        await harness.recorder.start()
        expectIdleWithoutCapture(harness, message: "Needs macOS 14.2 or later.")
        TestSupport.expectEqual(harness.micAsked, 0)
    }

    @MainActor
    private static func missingKeyStopsBeforePermissionPrompt() async {
        let harness = Harness()
        harness.transcriberError = MeetingRecorderError.missingAPIKey
        await harness.recorder.start()
        expectIdleWithoutCapture(harness, message: "Add a transcription API key in Settings to record meetings.")
        TestSupport.expectEqual(harness.micAsked, 0)
        TestSupport.expectEqual(harness.me.startCount + harness.them.startCount, 0)
    }

    @MainActor
    private static func deniedMicrophoneShowsGuidance() async {
        let harness = Harness()
        harness.micAllowed = false
        await harness.recorder.start()
        expectIdleWithoutCapture(harness, message: MeetingRecorderError.microphoneDenied.localizedDescription)
        TestSupport.expectEqual(harness.me.startCount + harness.them.startCount, 0)
    }

    @MainActor
    private static func sourceFailureStopsEverySource() async {
        let harness = Harness()
        harness.them.failsToStart = true
        await harness.recorder.start()
        expectIdleWithoutCapture(harness, message: "Couldn't start recording: synthetic device")
        TestSupport.expectEqual(harness.me.startCount, 1)
        TestSupport.expect(harness.me.stopCount >= 1, "The microphone is released when system audio fails")
        await harness.recorder.start()
        TestSupport.expectEqual(harness.me.startCount, 2)
    }

    @MainActor
    private static func recordingTranscribesCopiesAndSaves() async {
        let harness = Harness()
        let recorder = harness.recorder
        await recorder.start()
        TestSupport.expectEqual(recorder.phase, .recording)
        TestSupport.expectEqual(recorder.startedAt, harness.clock)
        TestSupport.expectEqual(harness.micAsked, 1)

        harness.clock += 1
        harness.them.emit(MeetingTranscriptCoreTests.tone(seconds: 1))
        harness.clock += 10
        harness.me.emit(MeetingTranscriptCoreTests.tone(seconds: 10) + MeetingTranscriptCoreTests.silence(seconds: 0.1))
        await harness.settle { !recorder.liveSegments.isEmpty }
        TestSupport.expect(recorder.level > 0.5, "Waveform follows the louder side")
        TestSupport.expectEqual(harness.transcriber.calls, 1)
        TestSupport.expectEqual(recorder.liveSegments.map(\.text), ["10 seconds"])
        TestSupport.expectEqual(recorder.liveSegments.first?.speaker, .me)

        harness.clock += 5
        await recorder.toggle()
        TestSupport.expectEqual(recorder.phase, .idle)
        TestSupport.expectEqual(harness.me.stopCount, 1)
        TestSupport.expectEqual(harness.them.stopCount, 1)
        TestSupport.expectEqual(harness.transcriber.calls, 2)
        TestSupport.expect(recorder.liveSegments.isEmpty && recorder.level == 0, "Live state clears after stop")
        TestSupport.expectEqual(harness.copied, ["Them: 1 seconds\nMe: 10 seconds"])
        TestSupport.expectEqual(recorder.toast, "Copied to clipboard")
        TestSupport.expect(recorder.errorMessage == nil, "A good meeting has no error")

        let saved = harness.store.loadAll()
        TestSupport.expectEqual(saved.count, 1)
        TestSupport.expectEqual(recorder.meetings, saved)
        TestSupport.expectEqual(saved.first?.date, Date(timeIntervalSince1970: 1_700_000_000))
        TestSupport.expectEqual(saved.first?.duration, 16)
        TestSupport.expectEqual(saved.first?.segments.map(\.speaker), [.them, .me])

        harness.me.emit(MeetingTranscriptCoreTests.tone(seconds: 25))
        await harness.settle()
        TestSupport.expectEqual(harness.transcriber.calls, 2)
    }

    @MainActor
    private static func silentMeetingSavesNothing() async {
        let harness = Harness()
        await harness.recorder.start()
        harness.me.emit(MeetingTranscriptCoreTests.silence(seconds: 21))
        harness.them.emit(MeetingTranscriptCoreTests.silence(seconds: 2))
        await harness.settle()
        await harness.recorder.stop()
        TestSupport.expectEqual(harness.transcriber.calls, 0)
        TestSupport.expect(harness.copied.isEmpty, "Nothing copied for silence")
        TestSupport.expect(harness.store.loadAll().isEmpty && harness.recorder.meetings.isEmpty, "Nothing saved for silence")
        TestSupport.expectEqual(harness.recorder.errorMessage, "No speech was picked up, so nothing was saved.")
    }

    @MainActor
    private static func copyAndDeletePastMeetings() async {
        let harness = Harness()
        let older = MeetingRecord(title: "Older", date: Date(timeIntervalSince1970: 10), duration: 60, segments: [
            MeetingSegment(speaker: .me, start: 0, text: "Synthetic hello."),
        ])
        let newer = MeetingRecord(title: "Newer", date: Date(timeIntervalSince1970: 20), duration: 60, segments: [
            MeetingSegment(speaker: .them, start: 0, text: "Synthetic reply."),
        ])
        try? harness.store.save(older)
        try? harness.store.save(newer)
        let recorder = harness.recorder
        TestSupport.expectEqual(recorder.meetings.map(\.title), ["Newer", "Older"])
        recorder.copy(older)
        TestSupport.expectEqual(harness.copied, ["Me: Synthetic hello."])
        TestSupport.expectEqual(recorder.toast, "Copied to clipboard")
        recorder.delete(newer)
        TestSupport.expectEqual(recorder.meetings.map(\.title), ["Older"])
        TestSupport.expectEqual(harness.store.loadAll().map(\.title), ["Older"])
    }

    @MainActor
    private static func blankedMicRestartsAndRecovers() async {
        let harness = Harness()
        let recorder = harness.recorder
        await recorder.start()
        harness.me.emit(MeetingTranscriptCoreTests.silence(seconds: 1.9))
        await harness.settle()
        TestSupport.expect(!recorder.micBlocked, "Under two seconds of exact zeros is not a blocked mic")
        TestSupport.expectEqual(harness.me.startCount, 1)

        harness.me.emit(MeetingTranscriptCoreTests.silence(seconds: 0.1))
        await harness.settle { recorder.micBlocked }
        TestSupport.expect(recorder.micBlocked, "Two seconds of exact zeros flags the mic as blocked")
        TestSupport.expectEqual(harness.me.stopCount, 1)
        TestSupport.expectEqual(harness.me.startCount, 2)
        TestSupport.expectEqual(harness.them.startCount, 1)

        harness.me.emit(MeetingTranscriptCoreTests.silence(seconds: 4))
        await harness.settle { harness.me.startCount == 3 }
        TestSupport.expectEqual(harness.me.startCount, 3)

        harness.me.emit(MeetingTranscriptCoreTests.tone(seconds: 0.2))
        await harness.settle { !recorder.micBlocked }
        TestSupport.expect(!recorder.micBlocked, "Real audio after a restart clears the warning")
        TestSupport.expectEqual(recorder.phase, .recording)

        harness.me.emit(MeetingTranscriptCoreTests.silence(seconds: 2))
        await harness.settle { recorder.micBlocked }
        await recorder.stop()
        TestSupport.expect(!recorder.micBlocked, "Stopping the meeting clears the warning")
    }

    @MainActor
    private static func silentSystemAudioNeverRestartsAnything() async {
        let harness = Harness()
        await harness.recorder.start()
        harness.them.emit(MeetingTranscriptCoreTests.silence(seconds: 6))
        await harness.settle()
        TestSupport.expect(!harness.recorder.micBlocked, "Nothing playing on the Mac is normal, not a blocked mic")
        TestSupport.expectEqual(harness.them.startCount + harness.me.startCount, 2)
        TestSupport.expectEqual(harness.them.stopCount + harness.me.stopCount, 0)
    }
}
