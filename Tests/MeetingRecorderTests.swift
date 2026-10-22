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
    var callApps: Set<String> = []
    let sleepNotifications = NotificationCenter()
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
        callAppsUsingMicrophone: { [unowned self] in callApps },
        copyToClipboard: { [unowned self] in copied.append($0) },
        sleepNotifications: sleepNotifications,
        now: { [unowned self] in clock }
    )

    deinit {
        try? FileManager.default.removeItem(at: directory)
    }

    /// Feeds both sides together in 100 ms batches, advancing the clock like live capture.
    func play(them themAudio: [Float], me meAudio: [Float]) {
        let batch = 1_600
        for offset in stride(from: 0, to: max(themAudio.count, meAudio.count), by: batch) {
            clock += 0.1
            them.emit(Array(themAudio[min(offset, themAudio.count)..<min(offset + batch, themAudio.count)]))
            me.emit(Array(meAudio[min(offset, meAudio.count)..<min(offset + batch, meAudio.count)]))
        }
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
        await renameSavesTrimmedTitleAndKeepsTheRest()
        await renameIgnoresBlankAndUnchangedTitles()
        await renameFailureKeepsOldTitle()
        await conversationKeepsSpeakingOrder()
        await quickRepliesStayInterleaved()
    }

    @MainActor
    private static func conversationKeepsSpeakingOrder() async {
        let harness = Harness()
        let recorder = harness.recorder
        await recorder.start()
        let tone = MeetingTranscriptCoreTests.tone, silence = MeetingTranscriptCoreTests.silence
        // Them 0-1 s, me 3-5 s, them 6.5-9.5 s, me 11-15 s, then both quiet until 15.5 s.
        harness.play(
            them: tone(1, 0.2) + silence(5.5) + tone(3, 0.2) + silence(6),
            me: silence(3) + tone(2, 0.2) + silence(6) + tone(4, 0.2) + silence(0.5)
        )
        await harness.settle()
        await recorder.stop()
        TestSupport.expectEqual(harness.transcriber.calls, 4)
        TestSupport.expectEqual(harness.copied, ["Them: 1 seconds\nMe: 2 seconds\nThem: 3 seconds\nMe: 4 seconds"])
        let segments = harness.store.loadAll().first?.segments ?? []
        TestSupport.expectEqual(segments.map(\.speaker), [.them, .me, .them, .me])
        for (actual, expected) in zip(segments.map(\.start), [0, 3, 6.5, 11]) {
            TestSupport.expectApproximatelyEqual(actual, expected, accuracy: 0.001)
        }
        TestSupport.expectEqual(MeetingTranscriptCore.turns(segments).count, 4)
    }

    @MainActor
    private static func quickRepliesStayInterleaved() async {
        let harness = Harness()
        let recorder = harness.recorder
        await recorder.start()
        let tone = MeetingTranscriptCoreTests.tone, silence = MeetingTranscriptCoreTests.silence
        // Each side pauses only 1.6 s while the other answers, shorter than the long pause.
        harness.play(
            them: tone(1, 0.2) + silence(1.6) + tone(1, 0.2) + silence(3.9),
            me: silence(1.3) + tone(1, 0.2) + silence(1.6) + tone(3, 0.2) + silence(0.6)
        )
        await harness.settle { harness.transcriber.calls == 3 }
        TestSupport.expectEqual(recorder.liveSegments.map(\.speaker), [.them, .me, .them])
        await recorder.stop()
        TestSupport.expectEqual(harness.transcriber.calls, 4)
        TestSupport.expectEqual(harness.copied, ["Them: 1 seconds\nMe: 1 seconds\nThem: 1 seconds\nMe: 3 seconds"])
        let segments = harness.store.loadAll().first?.segments ?? []
        for (actual, expected) in zip(segments.map(\.start), [0, 1.3, 2.6, 3.9]) {
            TestSupport.expectApproximatelyEqual(actual, expected, accuracy: 0.001)
        }
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

    private static func renameFixtures() -> (older: MeetingRecord, newer: MeetingRecord) {
        let older = MeetingRecord(title: "Older", date: Date(timeIntervalSince1970: 10), duration: 75, segments: [
            MeetingSegment(speaker: .me, start: 0, text: "Synthetic hello."),
            MeetingSegment(speaker: .them, start: 12.5, text: "Synthetic reply."),
        ])
        let newer = MeetingRecord(title: "Newer", date: Date(timeIntervalSince1970: 20), duration: 60, segments: [
            MeetingSegment(speaker: .them, start: 0, text: "Synthetic question."),
        ])
        return (older, newer)
    }

    @MainActor
    private static func renameSavesTrimmedTitleAndKeepsTheRest() async {
        let harness = Harness()
        let (older, newer) = renameFixtures()
        try? harness.store.save(older)
        try? harness.store.save(newer)
        let recorder = harness.recorder

        recorder.rename(older, to: "  Design sync \n")

        var expected = older
        expected.title = "Design sync"
        TestSupport.expectEqual(recorder.meetings, [newer, expected])
        TestSupport.expectEqual(MeetingStore(directory: harness.directory).loadAll(), [newer, expected])
        TestSupport.expect(recorder.errorMessage == nil, "A good rename has no error")

        recorder.rename(older, to: "Design sync v2")
        TestSupport.expectEqual(recorder.meetings.map(\.title), ["Newer", "Design sync v2"])
        TestSupport.expectEqual(MeetingStore(directory: harness.directory).loadAll().map(\.title), ["Newer", "Design sync v2"])
    }

    @MainActor
    private static func renameIgnoresBlankAndUnchangedTitles() async {
        let harness = Harness()
        let (older, newer) = renameFixtures()
        try? harness.store.save(older)
        try? harness.store.save(newer)
        let recorder = harness.recorder
        let fileURL = harness.store.fileURL(for: older.id)
        let savedAt = Date(timeIntervalSince1970: 1_000)
        try? FileManager.default.setAttributes([.modificationDate: savedAt], ofItemAtPath: fileURL.path)

        for blank in ["", "   ", "\n\t ", " Older "] {
            recorder.rename(older, to: blank)
        }

        TestSupport.expectEqual(recorder.meetings, [newer, older])
        TestSupport.expectEqual(MeetingStore(directory: harness.directory).loadAll(), [newer, older])
        let modified = (try? FileManager.default.attributesOfItem(atPath: fileURL.path))?[.modificationDate] as? Date
        TestSupport.expectEqual(modified, savedAt)
        TestSupport.expect(recorder.errorMessage == nil, "Ignored renames show no error")
    }

    @MainActor
    private static func renameFailureKeepsOldTitle() async {
        let harness = Harness()
        let (older, _) = renameFixtures()
        try? harness.store.save(older)
        let recorder = harness.recorder
        TestSupport.expectEqual(recorder.meetings, [older])

        try? FileManager.default.removeItem(at: harness.directory)
        FileManager.default.createFile(atPath: harness.directory.path, contents: Data())
        recorder.rename(older, to: "Unsaved title")

        TestSupport.expectEqual(recorder.meetings, [older])
        TestSupport.expectEqual(recorder.errorMessage, "Couldn't rename this meeting.")
    }
}
