import Foundation

enum MeetingRecorderError: LocalizedError, Equatable {
    case missingAPIKey
    case unsupportedSystem
    case microphoneDenied
    case audioSetupFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey: return "Add a transcription API key in Settings to record meetings."
        case .unsupportedSystem: return "Needs macOS 14.2 or later."
        case .microphoneDenied: return "Allow microphone access for Suki in System Settings > Privacy & Security."
        case .audioSetupFailed(let reason): return "Couldn't start recording: \(reason)"
        }
    }
}

enum MeetingTranscriber {
    /// Same provider, key and model as dictation, but refuses to start without a key
    /// so a meeting never runs for minutes only to fail every chunk.
    static func make(_ configuration: TranscriptionConfiguration) throws -> SpeechToTextService {
        guard !configuration.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw MeetingRecorderError.missingAPIKey
        }
        return try SpeechToTextServiceFactory.make(configuration)
    }
}

/// Uploads chunks as they are cut and collects the resulting segments.
@MainActor
final class MeetingTranscriptionQueue {
    private(set) var segments: [MeetingSegment] = []
    var onSegmentsChange: (([MeetingSegment]) -> Void)?
    private let transcriber: SpeechToTextService
    private let tempDirectory: URL
    private var tasks: [UUID: Task<Void, Never>] = [:]

    init(transcriber: SpeechToTextService, tempDirectory: URL = MeetingTranscriptionQueue.defaultTempDirectory) {
        self.transcriber = transcriber
        self.tempDirectory = tempDirectory
    }

    nonisolated static var defaultTempDirectory: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("MeetingChunks", isDirectory: true)
    }

    var pendingCount: Int { tasks.count }

    func enqueue(_ chunk: MeetingAudioChunk) {
        let id = UUID()
        let transcriber = transcriber, tempDirectory = tempDirectory
        tasks[id] = Task { [weak self] in
            let segment = await Self.transcribe(chunk, using: transcriber, tempDirectory: tempDirectory)
            guard let self else { return }
            self.tasks[id] = nil
            guard let segment else { return }
            self.segments.append(segment)
            self.onSegmentsChange?(self.segments)
        }
    }

    /// Waits for every chunk already enqueued, including ones enqueued while waiting.
    func drain() async {
        while let task = tasks.values.first {
            await task.value
        }
    }

    func cancelAll() {
        tasks.values.forEach { $0.cancel() }
        tasks.removeAll()
    }

    /// Silent chunks are skipped without uploading. A failed chunk becomes a placeholder
    /// so the gap is visible; there is no retry. The temp WAV is always deleted.
    nonisolated static func transcribe(
        _ chunk: MeetingAudioChunk,
        using transcriber: SpeechToTextService,
        tempDirectory: URL
    ) async -> MeetingSegment? {
        guard !MeetingTranscriptCore.isSilent(MeetingTranscriptCore.windowLevels(chunk.samples)) else { return nil }
        let fileURL = tempDirectory.appendingPathComponent("\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let text: String
        do {
            try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
            try MeetingTranscriptCore.wavData(chunk.samples).write(to: fileURL, options: .atomic)
            text = try await transcriber.transcribe(fileURL: fileURL).trimmingCharacters(in: .whitespacesAndNewlines)
        } catch is CancellationError {
            return nil
        } catch {
            text = MeetingTranscriptCore.failedChunkText
        }
        guard !text.isEmpty, !Task.isCancelled else { return nil }
        return MeetingSegment(speaker: chunk.speaker, start: chunk.start, text: text)
    }
}
