import Foundation
import NaturalLanguage

enum MeetingSpeaker: String, Codable, CaseIterable {
    case me
    case them

    var label: String {
        switch self {
        case .me: return "Me"
        case .them: return "Them"
        }
    }

    /// Name shown above transcript bubbles. Copied text keeps `label`.
    var displayName: String {
        switch self {
        case .me: return "You"
        case .them: return "Them"
        }
    }
}

enum MeetingPhase: Equatable {
    case idle, starting, recording, finishing
}

/// One transcribed stretch of a meeting. `start` is seconds since the meeting began.
struct MeetingSegment: Codable, Equatable, Identifiable {
    var id = UUID()
    let speaker: MeetingSpeaker
    let start: TimeInterval
    var text: String
}

/// One speaker's uninterrupted stretch of a meeting, split into sentences for display.
struct MeetingTurn: Equatable, Identifiable {
    let id: UUID
    let speaker: MeetingSpeaker
    let start: TimeInterval
    var sentences: [String]
}

struct MeetingRecord: Codable, Equatable, Identifiable {
    var id = UUID()
    var title: String
    let date: Date
    let duration: TimeInterval
    let segments: [MeetingSegment]

    var transcript: String { MeetingTranscriptCore.clipboardText(segments) }
}

/// A mono 16 kHz slice of one speaker's audio, cut from the live stream.
/// `start` is when the speech in it begins; `samples` may open with a short quiet lead-in,
/// so `audioStart` is when the first sample was heard. Both are seconds since the meeting began.
struct MeetingAudioChunk: Equatable {
    let speaker: MeetingSpeaker
    let start: TimeInterval
    let audioStart: TimeInterval
    let samples: [Float]

    var duration: TimeInterval { Double(samples.count) / MeetingTranscriptCore.sampleRate }
}

enum MeetingTranscriptCore {
    static let sampleRate: Double = 16_000
    static let targetChunkSeconds: TimeInterval = 10
    static let maxChunkSeconds: TimeInterval = 15
    static let failedChunkText = "[couldn't transcribe]"
    /// RMS below this (about -42 dBFS) counts as silence.
    static let silenceRMS: Float = 0.008
    static let levelWindowSeconds: TimeInterval = 0.1
    /// A chunk needs this many voiced 100 ms windows before it is worth uploading.
    static let minVoicedWindows = 3
    /// Quiet audio kept in front of an utterance so soft first sounds aren't clipped.
    static let leadInSeconds: TimeInterval = 0.2
    /// A pause this long ends an utterance once the other side has spoken since it began.
    /// It is also the most trailing pause a chunk keeps; longer pauses are trimmed.
    static let turnPauseSeconds: TimeInterval = 0.6
    /// A pause this long ends an utterance even when nobody else spoke.
    static let longPauseSeconds: TimeInterval = 2
    /// Samples arriving this much later than their count predicts mean the source dropped audio.
    static let clockResyncSeconds: TimeInterval = 1

    static func windows(_ seconds: TimeInterval) -> Int {
        Int((seconds / levelWindowSeconds).rounded())
    }

    static func rms<C: Collection>(_ samples: C) -> Float where C.Element == Float {
        guard !samples.isEmpty else { return 0 }
        let sum = samples.reduce(Float(0)) { $0 + $1 * $1 }
        return (sum / Float(samples.count)).squareRoot()
    }

    static func windowLevels(_ samples: [Float], windowSize: Int = Int(sampleRate * levelWindowSeconds)) -> [Float] {
        stride(from: 0, to: samples.count, by: windowSize).map {
            rms(samples[$0..<min($0 + windowSize, samples.count)])
        }
    }

    static func isSilent(_ levels: [Float], threshold: Float = silenceRMS, minVoiced: Int = minVoicedWindows) -> Bool {
        levels.filter { $0 >= threshold }.count < minVoiced
    }

    /// Orders segments by start time and folds consecutive lines from the same speaker together.
    static func merged(_ segments: [MeetingSegment]) -> [MeetingSegment] {
        var result: [MeetingSegment] = []
        for segment in ordered(segments) {
            let text = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            if let last = result.last, last.speaker == segment.speaker {
                result[result.count - 1].text = last.text + " " + text
            } else {
                result.append(MeetingSegment(id: segment.id, speaker: segment.speaker, start: segment.start, text: text))
            }
        }
        return result
    }

    /// Like `merged`, but keeps each speaker's sentences apart so they can render as separate bubbles.
    static func turns(_ segments: [MeetingSegment]) -> [MeetingTurn] {
        var result: [MeetingTurn] = []
        for segment in ordered(segments) {
            let parts = sentences(in: segment.text)
            guard !parts.isEmpty else { continue }
            if let last = result.last, last.speaker == segment.speaker {
                result[result.count - 1].sentences += parts
            } else {
                result.append(MeetingTurn(id: segment.id, speaker: segment.speaker, start: segment.start, sentences: parts))
            }
        }
        return result
    }

    static func sentences(in text: String) -> [String] {
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        return tokenizer.tokens(for: text.startIndex..<text.endIndex)
            .map { text[$0].trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// "2 speakers · 01:38"
    static func transcriptSummary(_ segments: [MeetingSegment], duration: TimeInterval) -> String {
        let speakers = Set(merged(segments).map(\.speaker)).count
        return "\(speakers) speaker\(speakers == 1 ? "" : "s") · \(clock(duration))"
    }

    /// "4:28am"
    static func timeLabel(for date: Date, locale: Locale = .current, timeZone: TimeZone = .current) -> String {
        meridiemFormatter("h:mma", locale: locale, timeZone: timeZone).string(from: date)
    }

    private static func meridiemFormatter(_ format: String, locale: Locale, timeZone: TimeZone) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.amSymbol = "am"
        formatter.pmSymbol = "pm"
        formatter.dateFormat = format
        return formatter
    }

    private static func ordered(_ segments: [MeetingSegment]) -> [MeetingSegment] {
        segments
            .enumerated()
            .sorted { ($0.element.start, $0.offset) < ($1.element.start, $1.offset) }
            .map(\.element)
    }

    static func clipboardText(_ segments: [MeetingSegment], timestamps: Bool = false) -> String {
        merged(segments)
            .map { (timestamps ? "[\(clock($0.start))] " : "") + "\($0.speaker.label): \($0.text)" }
            .joined(separator: "\n")
    }

    /// "04:05", "12:00", or "1:02:03" once past an hour.
    static func clock(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        let hours = total / 3600, minutes = (total % 3600) / 60, secs = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, secs)
            : String(format: "%02d:%02d", minutes, secs)
    }

    /// "Meeting · Oct 21, 3:04pm"
    static func defaultTitle(for date: Date, locale: Locale = .current, timeZone: TimeZone = .current) -> String {
        "Meeting · " + meridiemFormatter("MMM d, h:mma", locale: locale, timeZone: timeZone).string(from: date)
    }

    static let maxTitleLength = 120

    /// The cleaned-up title to save, or nil when the proposal is blank or would not change `current`.
    static func renamedTitle(_ proposed: String, current: String) -> String? {
        let title = String(proposed.trimmingCharacters(in: .whitespacesAndNewlines).prefix(maxTitleLength))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, title != current else { return nil }
        return title
    }

    /// "Today", "Yesterday", or "Monday, Oct 20".
    static func dayLabel(for day: Date, now: Date, calendar: Calendar = .current, locale: Locale = .current) -> String {
        if calendar.isDate(day, inSameDayAs: now) { return "Today" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(day, inSameDayAs: yesterday) {
            return "Yesterday"
        }
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "EEEE, MMM d"
        return formatter.string(from: day)
    }

    /// Groups newest-first by calendar day; days and the meetings within them stay newest-first.
    static func groupedByDay(_ meetings: [MeetingRecord], calendar: Calendar = .current) -> [(day: Date, meetings: [MeetingRecord])] {
        let sorted = meetings.sorted { $0.date > $1.date }
        var groups: [(day: Date, meetings: [MeetingRecord])] = []
        for meeting in sorted {
            let day = calendar.startOfDay(for: meeting.date)
            if groups.last?.day == day {
                groups[groups.count - 1].meetings.append(meeting)
            } else {
                groups.append((day, [meeting]))
            }
        }
        return groups
    }

    /// Maps RMS to 0...1 on a -50 dB to -10 dB scale for the waveform.
    static func displayLevel(rms: Float) -> Float {
        guard rms > 0 else { return 0 }
        let decibels = 20 * log10(rms)
        return min(1, max(0, (decibels + 50) / 40))
    }

    /// Distance of a bar from the center bar in a mirrored, center-out waveform.
    static func waveformDistance(index: Int, count: Int) -> Int {
        abs(index - (count - 1) / 2)
    }

    /// Outer bars are shorter: 1 - d² · 18/48 with d normalized to 0...1.
    static func waveformScale(index: Int, count: Int) -> Double {
        let maxDistance = (count - 1) / 2
        guard maxDistance > 0 else { return 1 }
        let d = Double(waveformDistance(index: index, count: count)) / Double(maxDistance)
        return 1 - d * d * (18.0 / 48.0)
    }

    static func waveformDelay(index: Int, count: Int) -> Double {
        0.1 * Double(waveformDistance(index: index, count: count))
    }

    /// 16-bit mono PCM WAV for upload.
    static func wavData(_ samples: [Float], sampleRate: Int = Int(sampleRate)) -> Data {
        let dataSize = UInt32(samples.count * 2)
        var data = Data(capacity: 44 + Int(dataSize))
        func append<T: FixedWidthInteger>(_ value: T) {
            withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
        }
        data.append(contentsOf: Array("RIFF".utf8))
        append(UInt32(36) + dataSize)
        data.append(contentsOf: Array("WAVEfmt ".utf8))
        append(UInt32(16))
        append(UInt16(1))
        append(UInt16(1))
        append(UInt32(sampleRate))
        append(UInt32(sampleRate * 2))
        append(UInt16(2))
        append(UInt16(16))
        data.append(contentsOf: Array("data".utf8))
        append(dataSize)
        for sample in samples {
            append(Int16((max(-1, min(1, sample)) * Float(Int16.max)).rounded()))
        }
        return data
    }
}

/// Cuts one speaker's 16 kHz stream into utterances, judged in `levelWindowSeconds` windows
/// against `silenceRMS`. A chunk starts at the first voiced window, so silence never shifts
/// it earlier, and only a short lead-in of the silence before it is kept. A chunk ends when
/// the speaker pauses for `turnPauseSeconds` after the other side has spoken since it began
/// (a change of turn), after a `longPauseSeconds` pause, at the first quiet window past the
/// target length, or at the max length even mid-word. A speaker talking alone keeps long
/// chunks, which keeps context for the transcriber and the request count low. Utterances
/// with fewer than `minVoicedWindows` voiced windows are dropped as blips.
struct MeetingChunkBuffer {
    let speaker: MeetingSpeaker
    var targetSeconds = MeetingTranscriptCore.targetChunkSeconds
    var maxSeconds = MeetingTranscriptCore.maxChunkSeconds
    /// End of this speaker's latest voiced window, in seconds since the meeting began.
    /// Blips don't count. The other speaker's buffer reads it to notice a change of turn.
    private(set) var lastSpeechTime: TimeInterval?
    private let windowSize = Int(MeetingTranscriptCore.sampleRate * MeetingTranscriptCore.levelWindowSeconds)
    private let leadInWindows = MeetingTranscriptCore.windows(MeetingTranscriptCore.leadInSeconds)
    private let pauseWindows = MeetingTranscriptCore.windows(MeetingTranscriptCore.turnPauseSeconds)
    private let longPauseWindows = MeetingTranscriptCore.windows(MeetingTranscriptCore.longPauseSeconds)
    private var streamOffset: TimeInterval?
    private var judgedSamples = 0
    /// Received samples not yet a whole window.
    private var unjudged: [Float] = []
    /// Whole windows: the lead-in while idle, otherwise the current utterance.
    private var pending: [Float] = []
    private var onset: TimeInterval?
    /// When the first sample of `pending` was heard, set with `onset`.
    private var audioStart: TimeInterval?
    private var voicedWindows = 0
    private var quietRun = 0

    init(speaker: MeetingSpeaker) {
        self.speaker = speaker
    }

    var pendingSeconds: TimeInterval { Double(pending.count + unjudged.count) / MeetingTranscriptCore.sampleRate }

    /// `arrival` is seconds since the meeting began when these samples were delivered.
    /// `otherSpeechTime` is the other speaker's `lastSpeechTime`.
    /// Returns every chunk completed by this batch, oldest first.
    mutating func append(
        _ samples: [Float],
        arrival: TimeInterval,
        otherSpeechTime: TimeInterval? = nil
    ) -> [MeetingAudioChunk] {
        guard !samples.isEmpty else { return [] }
        let batchStart = arrival - Double(samples.count) / MeetingTranscriptCore.sampleRate
        if let streamOffset {
            // A stalled source delivers nothing, so counting samples alone would fall behind the
            // other speaker's clock. Small delivery jitter is ignored; the clock never runs back.
            let counted = streamOffset + Double(judgedSamples + unjudged.count) / MeetingTranscriptCore.sampleRate
            if batchStart - counted > MeetingTranscriptCore.clockResyncSeconds {
                self.streamOffset = streamOffset + batchStart - counted
            }
        } else {
            streamOffset = max(0, batchStart)
        }
        unjudged.append(contentsOf: samples)
        var chunks: [MeetingAudioChunk] = []
        var index = 0
        while unjudged.count - index >= windowSize {
            if let chunk = judge(unjudged[index..<index + windowSize], otherSpeechTime: otherSpeechTime) {
                chunks.append(chunk)
            }
            index += windowSize
        }
        unjudged.removeFirst(index)
        return chunks
    }

    /// Hands over the utterance in progress, if it is more than a blip.
    mutating func flush() -> MeetingAudioChunk? {
        defer {
            unjudged.removeAll()
            endUtterance(keepingWindows: 0)
        }
        guard voicedWindows >= MeetingTranscriptCore.minVoicedWindows else { return nil }
        if quietRun <= pauseWindows { pending += unjudged }
        return cut()
    }

    private mutating func judge(_ window: ArraySlice<Float>, otherSpeechTime: TimeInterval?) -> MeetingAudioChunk? {
        guard let streamOffset else { return nil }
        let time = streamOffset + Double(judgedSamples) / MeetingTranscriptCore.sampleRate
        judgedSamples += window.count
        let isVoiced = MeetingTranscriptCore.rms(window) >= MeetingTranscriptCore.silenceRMS
        pending += window
        guard let onset = onset ?? (isVoiced ? time : nil) else {
            pending.removeFirst(max(0, pending.count - leadInWindows * windowSize))
            return nil
        }
        if self.onset == nil {
            audioStart = time - Double(pending.count - window.count) / MeetingTranscriptCore.sampleRate
        }
        self.onset = onset
        if isVoiced {
            voicedWindows += 1
            quietRun = 0
            if voicedWindows >= MeetingTranscriptCore.minVoicedWindows {
                lastSpeechTime = time + Double(window.count) / MeetingTranscriptCore.sampleRate
            }
        } else {
            quietRun += 1
        }
        let seconds = Double(pending.count) / MeetingTranscriptCore.sampleRate
        if seconds >= maxSeconds { return finishUtterance() }
        guard !isVoiced else { return nil }
        let otherSideSpoke = (otherSpeechTime ?? -.infinity) > onset
        if quietRun >= longPauseWindows || (quietRun >= pauseWindows && otherSideSpoke) {
            return finishUtterance()
        }
        return seconds >= targetSeconds ? finishUtterance() : nil
    }

    /// Cuts the utterance, or drops it if it is only a blip. Quiet windows that are not
    /// uploaded stay behind as the next lead-in.
    private mutating func finishUtterance() -> MeetingAudioChunk? {
        let chunk = voicedWindows >= MeetingTranscriptCore.minVoicedWindows ? cut() : nil
        let unsentQuiet = chunk == nil ? quietRun : max(0, quietRun - pauseWindows)
        endUtterance(keepingWindows: min(unsentQuiet, leadInWindows))
        return chunk
    }

    /// The utterance so far, keeping only `turnPauseSeconds` of any trailing pause.
    private func cut() -> MeetingAudioChunk? {
        guard let onset else { return nil }
        let trailingQuiet = max(0, quietRun - pauseWindows) * windowSize
        return MeetingAudioChunk(
            speaker: speaker,
            start: onset,
            audioStart: audioStart ?? onset,
            samples: Array(pending.dropLast(trailingQuiet))
        )
    }

    private mutating func endUtterance(keepingWindows windows: Int) {
        pending.removeFirst(max(0, pending.count - windows * windowSize))
        onset = nil
        audioStart = nil
        voicedWindows = 0
        quietRun = 0
    }
}
