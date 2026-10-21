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
struct MeetingAudioChunk: Equatable {
    let speaker: MeetingSpeaker
    let start: TimeInterval
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

/// Accumulates one speaker's 16 kHz samples and cuts a chunk once it is long enough,
/// preferring a quiet moment after the target length so words aren't split.
struct MeetingChunkBuffer {
    let speaker: MeetingSpeaker
    var targetSeconds = MeetingTranscriptCore.targetChunkSeconds
    var maxSeconds = MeetingTranscriptCore.maxChunkSeconds
    private var streamOffset: TimeInterval?
    private var consumedSamples = 0
    private var pending: [Float] = []

    init(speaker: MeetingSpeaker) {
        self.speaker = speaker
    }

    var pendingSeconds: TimeInterval { Double(pending.count) / MeetingTranscriptCore.sampleRate }

    /// `arrival` is seconds since the meeting began when these samples were delivered.
    mutating func append(_ samples: [Float], arrival: TimeInterval) -> MeetingAudioChunk? {
        guard !samples.isEmpty else { return nil }
        if streamOffset == nil {
            streamOffset = max(0, arrival - Double(samples.count) / MeetingTranscriptCore.sampleRate)
        }
        pending.append(contentsOf: samples)
        guard pendingSeconds >= targetSeconds else { return nil }
        let window = Int(MeetingTranscriptCore.sampleRate * MeetingTranscriptCore.levelWindowSeconds)
        let isQuiet = MeetingTranscriptCore.rms(pending.suffix(window)) < MeetingTranscriptCore.silenceRMS
        return isQuiet || pendingSeconds >= maxSeconds ? flush() : nil
    }

    mutating func flush() -> MeetingAudioChunk? {
        guard !pending.isEmpty, let streamOffset else { return nil }
        let start = streamOffset + Double(consumedSamples) / MeetingTranscriptCore.sampleRate
        let chunk = MeetingAudioChunk(speaker: speaker, start: start, samples: pending)
        consumedSamples += pending.count
        pending.removeAll(keepingCapacity: true)
        return chunk
    }
}
