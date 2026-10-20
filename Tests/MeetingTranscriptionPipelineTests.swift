import Foundation

private final class MockTranscriber: SpeechToTextService {
    private(set) var calls: [URL] = []
    private let handler: (URL) async throws -> String

    init(_ handler: @escaping (URL) async throws -> String) {
        self.handler = handler
    }

    func transcribe(fileURL: URL) async throws -> String {
        calls.append(fileURL)
        return try await handler(fileURL)
    }
}

private struct SyntheticFailure: Error {}

enum MeetingTranscriptionPipelineTests {
    private static func tempDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("MeetingPipelineTests-\(UUID().uuidString)", isDirectory: true)
    }

    private static func chunk(_ speaker: MeetingSpeaker, _ start: TimeInterval, seconds: Double = 1) -> MeetingAudioChunk {
        MeetingAudioChunk(speaker: speaker, start: start, samples: MeetingTranscriptCoreTests.tone(seconds: seconds))
    }

    private static func sampleCount(ofWAV url: URL) throws -> Int {
        (try Data(contentsOf: url).count - 44) / 2
    }

    @MainActor
    static func run() async {
        await silentChunkIsSkippedWithoutUpload()
        await voicedChunkUploadsWAVThenDeletesIt()
        await failureBecomesPlaceholderWithoutRetry()
        await blankOrCancelledResultsAreDropped()
        transcriberRequiresAPIKey()
        errorMessagesAreUserFacing()
        await queueCollectsSegmentsFromConcurrentChunks()
        await cancelAllDropsInFlightChunks()
    }

    private static func silentChunkIsSkippedWithoutUpload() async {
        let mock = MockTranscriber { _ in "should not happen" }
        let silent = MeetingAudioChunk(speaker: .me, start: 0, samples: MeetingTranscriptCoreTests.silence(seconds: 20))
        let segment = await MeetingTranscriptionQueue.transcribe(silent, using: mock, tempDirectory: tempDirectory())
        TestSupport.expect(segment == nil, "Silence produces no segment")
        TestSupport.expect(mock.calls.isEmpty, "Silence is never uploaded")
    }

    private static func voicedChunkUploadsWAVThenDeletesIt() async {
        let directory = tempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        var observedSamples = -1
        var observedHeader = ""
        let mock = MockTranscriber { url in
            observedSamples = try sampleCount(ofWAV: url)
            observedHeader = String(decoding: try Data(contentsOf: url).prefix(4), as: UTF8.self)
            return "  Synthetic words.\n"
        }
        let segment = await MeetingTranscriptionQueue.transcribe(chunk(.them, 42.5, seconds: 2), using: mock, tempDirectory: directory)
        TestSupport.expectEqual(segment?.speaker, .them)
        TestSupport.expectEqual(segment?.start, 42.5)
        TestSupport.expectEqual(segment?.text, "Synthetic words.")
        TestSupport.expectEqual(observedSamples, 32_000)
        TestSupport.expectEqual(observedHeader, "RIFF")
        TestSupport.expectEqual(mock.calls.count, 1)
        TestSupport.expectEqual(mock.calls.first?.deletingLastPathComponent().standardizedFileURL, directory.standardizedFileURL)
        TestSupport.expectEqual(mock.calls.first?.pathExtension, "wav")
        TestSupport.expect(!FileManager.default.fileExists(atPath: mock.calls[0].path), "Chunk audio is deleted after transcription")
    }

    private static func failureBecomesPlaceholderWithoutRetry() async {
        let mock = MockTranscriber { _ in throw SyntheticFailure() }
        let segment = await MeetingTranscriptionQueue.transcribe(chunk(.me, 3), using: mock, tempDirectory: tempDirectory())
        TestSupport.expectEqual(segment?.text, "[couldn't transcribe]")
        TestSupport.expectEqual(segment?.speaker, .me)
        TestSupport.expectEqual(segment?.start, 3)
        TestSupport.expectEqual(mock.calls.count, 1)
        TestSupport.expect(!FileManager.default.fileExists(atPath: mock.calls[0].path), "Chunk audio is deleted after a failure")
    }

    private static func blankOrCancelledResultsAreDropped() async {
        let blank = MockTranscriber { _ in " \n " }
        let blankSegment = await MeetingTranscriptionQueue.transcribe(chunk(.me, 0), using: blank, tempDirectory: tempDirectory())
        TestSupport.expect(blankSegment == nil, "Blank transcript adds nothing")
        let cancelled = MockTranscriber { _ in throw CancellationError() }
        let cancelledSegment = await MeetingTranscriptionQueue.transcribe(chunk(.me, 0), using: cancelled, tempDirectory: tempDirectory())
        TestSupport.expect(cancelledSegment == nil, "Cancellation is not a failed chunk")
    }

    private static func transcriberRequiresAPIKey() {
        func configuration(_ provider: TranscriptionProvider, key: String) -> TranscriptionConfiguration {
            TranscriptionConfiguration.resolve(
                provider: provider,
                providerAPIKey: key,
                standardBaseURL: "https://example.invalid/v1",
                standardAPIKey: key,
                model: "",
                language: nil
            )
        }
        for provider in TranscriptionProvider.allCases {
            for key in ["", "  \n"] {
                do {
                    _ = try MeetingTranscriber.make(configuration(provider, key: key))
                    TestSupport.expect(false, "\(provider) without a key must not start")
                } catch {
                    TestSupport.expectEqual(error as? MeetingRecorderError, .missingAPIKey)
                }
            }
        }
        TestSupport.expect((try? MeetingTranscriber.make(configuration(.standard, key: "synthetic"))) is TranscriptionService, "Standard uses upload service")
        TestSupport.expect((try? MeetingTranscriber.make(configuration(.openAI, key: "synthetic"))) is TranscriptionService, "OpenAI uses upload service")
        TestSupport.expect((try? MeetingTranscriber.make(configuration(.gemini, key: "synthetic"))) is GeminiTranscriptionService, "Gemini uses its service")
    }

    private static func errorMessagesAreUserFacing() {
        TestSupport.expectEqual(MeetingRecorderError.unsupportedSystem.localizedDescription, "Needs macOS 14.2 or later.")
        TestSupport.expectEqual(MeetingRecorderError.missingAPIKey.localizedDescription, "Add a transcription API key in Settings to record meetings.")
        TestSupport.expectEqual(MeetingRecorderError.audioSetupFailed("no device").localizedDescription, "Couldn't start recording: no device")
    }

    @MainActor
    private static func queueCollectsSegmentsFromConcurrentChunks() async {
        let directory = tempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let mock = MockTranscriber { url in
            let samples = try sampleCount(ofWAV: url)
            // Longer chunks finish first so completion order differs from start order.
            try await Task.sleep(nanoseconds: UInt64(40_000_000 / (samples / 16_000)))
            return "len \(samples / 16_000)"
        }
        let queue = MeetingTranscriptionQueue(transcriber: mock, tempDirectory: directory)
        var updates: [[MeetingSegment]] = []
        queue.onSegmentsChange = { updates.append($0) }
        queue.enqueue(chunk(.me, 0, seconds: 1))
        queue.enqueue(chunk(.them, 0.5, seconds: 2))
        queue.enqueue(MeetingAudioChunk(speaker: .them, start: 1, samples: MeetingTranscriptCoreTests.silence(seconds: 3)))
        queue.enqueue(chunk(.me, 20, seconds: 4))
        TestSupport.expectEqual(queue.pendingCount, 4)
        await queue.drain()
        TestSupport.expectEqual(queue.pendingCount, 0)
        TestSupport.expectEqual(queue.segments.count, 3)
        TestSupport.expectEqual(updates.count, 3)
        TestSupport.expectEqual(updates.last, queue.segments)
        TestSupport.expectEqual(MeetingTranscriptCore.clipboardText(queue.segments), "Me: len 1\nThem: len 2\nMe: len 4")
        let leftovers = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        TestSupport.expect(leftovers.isEmpty, "No chunk audio left behind")
    }

    @MainActor
    private static func cancelAllDropsInFlightChunks() async {
        let mock = MockTranscriber { _ in
            try? await Task.sleep(nanoseconds: 50_000_000)
            return "late"
        }
        let queue = MeetingTranscriptionQueue(transcriber: mock, tempDirectory: tempDirectory())
        queue.enqueue(chunk(.me, 0))
        queue.cancelAll()
        TestSupport.expectEqual(queue.pendingCount, 0)
        await queue.drain()
        try? await Task.sleep(nanoseconds: 120_000_000)
        TestSupport.expect(queue.segments.isEmpty, "Cancelled chunks never land in the transcript")
    }
}
