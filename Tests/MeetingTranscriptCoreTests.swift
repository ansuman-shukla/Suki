import Foundation
import NaturalLanguage

enum MeetingTranscriptCoreTests {
    private static let rate = Int(MeetingTranscriptCore.sampleRate)
    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        return calendar
    }

    private static func date(_ day: Int, hour: Int, minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    static func tone(seconds: Double, amplitude: Float = 0.2) -> [Float] {
        (0..<Int(seconds * MeetingTranscriptCore.sampleRate)).map { amplitude * sin(Float($0) * 0.3) }
    }

    static func silence(seconds: Double) -> [Float] {
        Array(repeating: 0, count: Int(seconds * MeetingTranscriptCore.sampleRate))
    }

    private static func segment(_ speaker: MeetingSpeaker, _ start: TimeInterval, _ text: String) -> MeetingSegment {
        MeetingSegment(speaker: speaker, start: start, text: text)
    }

    static func run() {
        rmsMatchesDefinition()
        windowLevelsSplitIntoHundredMillisecondWindows()
        silenceNeedsEnoughVoicedWindows()
        mergeOrdersByStartAndFoldsSameSpeaker()
        mergeDropsBlankTextAndKeepsTieOrder()
        clipboardTextFormatsSpeakersAndOptionalTimestamps()
        turnsSplitSentencesAndFoldSameSpeaker()
        turnsDropBlankTextAndKeepFailedChunkAsOneLine()
        sentencesReuseOneTokenizerAcrossTexts()
        speakerDisplayNamesDifferFromCopiedLabels()
        transcriptSummaryCountsSpeakersWithText()
        timeLabelUsesLowercaseMeridiem()
        clockFormatsMinutesAndHours()
        defaultTitleUsesShortDateAndLowercaseMeridiem()
        renamedTitleTrimsCapsAndIgnoresNoOps()
        dayLabelsUseTodayYesterdayThenWeekday()
        groupsMeetingsByDayNewestFirst()
        displayLevelMapsDecibelRange()
        waveformBarsAreMirroredFromCenter()
        wavDataHasValidHeaderAndClampedSamples()
        chunkBufferWaitsForTargetThenQuietMoment()
        chunkBufferCutsAtMaxEvenWhileTalking()
        chunkBufferTracksStartTimesAcrossChunks()
        chunkBufferFlushReturnsRemainderOnce()
        chunkBufferStartsAtSpeechOnset()
        chunkBufferCutsWhenSpeakerGoesQuiet()
        chunkBufferDropsBlipsButKeepsThemBeforeSpeech()
        chunkBufferCapsLongSpeechAfterSilence()
        chunkBufferFlushKeepsTailAndTrimsSilence()
        chunkBufferEndsLineWhenOtherSideSpeaks()
        chunkBufferReportsLastSpeechButNotBlips()
        chunkBufferClockSkipsAheadAfterDroppedAudio()
    }

    private static func rmsMatchesDefinition() {
        TestSupport.expectEqual(MeetingTranscriptCore.rms([Float]()), 0)
        TestSupport.expectApproximatelyEqual(Double(MeetingTranscriptCore.rms([3, -4])), (12.5).squareRoot(), accuracy: 0.0001)
        TestSupport.expectApproximatelyEqual(Double(MeetingTranscriptCore.rms([0.5, 0.5, 0.5])), 0.5, accuracy: 0.0001)
    }

    private static func windowLevelsSplitIntoHundredMillisecondWindows() {
        let samples = silence(seconds: 0.1) + Array(repeating: Float(0.5), count: rate / 10) + [1]
        let levels = MeetingTranscriptCore.windowLevels(samples)
        TestSupport.expectEqual(levels.count, 3)
        TestSupport.expectEqual(levels[0], 0)
        TestSupport.expectApproximatelyEqual(Double(levels[1]), 0.5, accuracy: 0.0001)
        TestSupport.expectApproximatelyEqual(Double(levels[2]), 1, accuracy: 0.0001)
    }

    private static func silenceNeedsEnoughVoicedWindows() {
        let threshold = MeetingTranscriptCore.silenceRMS
        TestSupport.expect(MeetingTranscriptCore.isSilent([]), "No windows is silent")
        TestSupport.expect(MeetingTranscriptCore.isSilent([threshold, threshold, 0.0079, 0]), "Two voiced windows is silent")
        TestSupport.expect(!MeetingTranscriptCore.isSilent([threshold, threshold, threshold, 0]), "Three voiced windows at threshold is speech")
        TestSupport.expect(MeetingTranscriptCore.isSilent(MeetingTranscriptCore.windowLevels(silence(seconds: 5))), "Zeros are silent")
        TestSupport.expect(!MeetingTranscriptCore.isSilent(MeetingTranscriptCore.windowLevels(tone(seconds: 0.3))), "300 ms of tone is speech")
        TestSupport.expect(
            MeetingTranscriptCore.isSilent(MeetingTranscriptCore.windowLevels(tone(seconds: 2, amplitude: 0.005))),
            "A faint hum stays below threshold"
        )
    }

    private static func mergeOrdersByStartAndFoldsSameSpeaker() {
        let merged = MeetingTranscriptCore.merged([
            segment(.them, 20.4, "Sounds good."),
            segment(.me, 0, " Hi there "),
            segment(.them, 0.2, "Hello!"),
            segment(.them, 40.3, "See you Friday."),
            segment(.me, 21, "Great, thanks."),
            segment(.me, 41, "Bye.")
        ])
        TestSupport.expectEqual(merged.map(\.speaker), [.me, .them, .me, .them, .me])
        TestSupport.expectEqual(merged.map(\.text), ["Hi there", "Hello! Sounds good.", "Great, thanks.", "See you Friday.", "Bye."])
        TestSupport.expectEqual(merged.map(\.start), [0, 0.2, 21, 40.3, 41])
    }

    private static func mergeDropsBlankTextAndKeepsTieOrder() {
        let first = segment(.them, 5, "First")
        let merged = MeetingTranscriptCore.merged([
            first,
            segment(.me, 5, "Second"),
            segment(.them, 6, "  \n"),
            segment(.me, 7, "Third")
        ])
        TestSupport.expectEqual(merged.map(\.text), ["First", "Second Third"])
        TestSupport.expectEqual(merged.first?.id, first.id)
        TestSupport.expectEqual(MeetingTranscriptCore.merged([segment(.me, 1, " ")]), [])
    }

    private static func clipboardTextFormatsSpeakersAndOptionalTimestamps() {
        let segments = [segment(.them, 65, "Next slide."), segment(.me, 3, "Can you hear me?"), segment(.me, 9, "Okay.")]
        TestSupport.expectEqual(
            MeetingTranscriptCore.clipboardText(segments),
            "Me: Can you hear me? Okay.\nThem: Next slide."
        )
        TestSupport.expectEqual(
            MeetingTranscriptCore.clipboardText(segments, timestamps: true),
            "[00:03] Me: Can you hear me? Okay.\n[01:05] Them: Next slide."
        )
        TestSupport.expectEqual(MeetingTranscriptCore.clipboardText([]), "")
        let record = MeetingRecord(title: "t", date: Date(timeIntervalSince1970: 0), duration: 1, segments: segments)
        TestSupport.expectEqual(record.transcript, "Me: Can you hear me? Okay.\nThem: Next slide.")
    }

    private static func turnsSplitSentencesAndFoldSameSpeaker() {
        let opening = segment(.me, 0, " Hi. What is going on here? ")
        let turns = MeetingTranscriptCore.turns([
            segment(.them, 30, "Sounds good. See you Friday."),
            opening,
            segment(.me, 12, "Hey, hey."),
            segment(.me, 50, "Bye!")
        ])
        TestSupport.expectEqual(turns.map(\.speaker), [.me, .them, .me])
        TestSupport.expectEqual(turns.map(\.sentences), [
            ["Hi.", "What is going on here?", "Hey, hey."],
            ["Sounds good.", "See you Friday."],
            ["Bye!"]
        ])
        TestSupport.expectEqual(turns.map(\.start), [0, 30, 50])
        TestSupport.expectEqual(turns.first?.id, opening.id)
    }

    private static func turnsDropBlankTextAndKeepFailedChunkAsOneLine() {
        let turns = MeetingTranscriptCore.turns([
            segment(.them, 0, "  \n"),
            segment(.me, 1, MeetingTranscriptCore.failedChunkText),
            segment(.them, 2, " "),
            segment(.me, 3, "Okay.")
        ])
        TestSupport.expectEqual(turns.map(\.sentences), [[MeetingTranscriptCore.failedChunkText, "Okay."]])
        TestSupport.expectEqual(MeetingTranscriptCore.turns([]), [])
        TestSupport.expectEqual(MeetingTranscriptCore.sentences(in: "No ending punctuation"), ["No ending punctuation"])
    }

    /// `turns` shares one tokenizer across segments, so a shorter text must not pick up the previous one.
    private static func sentencesReuseOneTokenizerAcrossTexts() {
        let tokenizer = NLTokenizer(unit: .sentence)
        TestSupport.expectEqual(
            MeetingTranscriptCore.sentences(in: "A longer synthetic opening line. Then a second one.", using: tokenizer),
            ["A longer synthetic opening line.", "Then a second one."]
        )
        TestSupport.expectEqual(MeetingTranscriptCore.sentences(in: "Short.", using: tokenizer), ["Short."])
        TestSupport.expectEqual(MeetingTranscriptCore.sentences(in: " ", using: tokenizer), [])
        TestSupport.expectEqual(
            MeetingTranscriptCore.turns([
                segment(.me, 0, "First synthetic thought here. And more."),
                segment(.them, 5, "Yes."),
                segment(.them, 6, "Agreed. Ship it.")
            ]).map(\.sentences),
            [["First synthetic thought here.", "And more."], ["Yes.", "Agreed.", "Ship it."]]
        )
    }

    private static func speakerDisplayNamesDifferFromCopiedLabels() {
        TestSupport.expectEqual(MeetingSpeaker.me.displayName, "You")
        TestSupport.expectEqual(MeetingSpeaker.them.displayName, "Them")
        TestSupport.expectEqual(MeetingSpeaker.me.label, "Me")
    }

    private static func transcriptSummaryCountsSpeakersWithText() {
        TestSupport.expectEqual(
            MeetingTranscriptCore.transcriptSummary([segment(.me, 0, "Hi."), segment(.them, 2, "  ")], duration: 98),
            "1 speaker · 01:38"
        )
        TestSupport.expectEqual(
            MeetingTranscriptCore.transcriptSummary([segment(.me, 0, "Hi."), segment(.them, 2, "Hey.")], duration: 3723),
            "2 speakers · 1:02:03"
        )
    }

    private static func timeLabelUsesLowercaseMeridiem() {
        let locale = Locale(identifier: "en_US")
        TestSupport.expectEqual(
            MeetingTranscriptCore.timeLabel(for: date(21, hour: 4, minute: 28), locale: locale, timeZone: calendar.timeZone),
            "4:28am"
        )
        TestSupport.expectEqual(
            MeetingTranscriptCore.timeLabel(for: date(21, hour: 15, minute: 4), locale: locale, timeZone: calendar.timeZone),
            "3:04pm"
        )
    }

    private static func clockFormatsMinutesAndHours() {
        TestSupport.expectEqual(MeetingTranscriptCore.clock(0), "00:00")
        TestSupport.expectEqual(MeetingTranscriptCore.clock(59.9), "00:59")
        TestSupport.expectEqual(MeetingTranscriptCore.clock(754), "12:34")
        TestSupport.expectEqual(MeetingTranscriptCore.clock(3599), "59:59")
        TestSupport.expectEqual(MeetingTranscriptCore.clock(3723), "1:02:03")
        TestSupport.expectEqual(MeetingTranscriptCore.clock(-5), "00:00")
    }

    private static func defaultTitleUsesShortDateAndLowercaseMeridiem() {
        let locale = Locale(identifier: "en_US")
        TestSupport.expectEqual(
            MeetingTranscriptCore.defaultTitle(for: date(21, hour: 15, minute: 4), locale: locale, timeZone: calendar.timeZone),
            "Meeting · Oct 21, 3:04pm"
        )
        TestSupport.expectEqual(
            MeetingTranscriptCore.defaultTitle(for: date(2, hour: 9, minute: 30), locale: locale, timeZone: calendar.timeZone),
            "Meeting · Oct 2, 9:30am"
        )
    }

    private static func renamedTitleTrimsCapsAndIgnoresNoOps() {
        TestSupport.expectEqual(MeetingTranscriptCore.renamedTitle("  Design sync \n", current: "Old"), "Design sync")
        TestSupport.expectEqual(MeetingTranscriptCore.renamedTitle("Old", current: "Old"), nil)
        TestSupport.expectEqual(MeetingTranscriptCore.renamedTitle("  Old\t", current: "Old"), nil)
        TestSupport.expectEqual(MeetingTranscriptCore.renamedTitle("", current: "Old"), nil)
        TestSupport.expectEqual(MeetingTranscriptCore.renamedTitle(" \n\t ", current: "Old"), nil)
        TestSupport.expectEqual(MeetingTranscriptCore.renamedTitle("old", current: "Old"), "old")

        let long = String(repeating: "a", count: MeetingTranscriptCore.maxTitleLength) + "overflow"
        TestSupport.expectEqual(MeetingTranscriptCore.renamedTitle(long, current: "Old"), String(repeating: "a", count: 120))
        TestSupport.expectEqual(MeetingTranscriptCore.renamedTitle("   " + long, current: "Old"), String(repeating: "a", count: 120))
        let cutAtSpace = String(repeating: "b", count: MeetingTranscriptCore.maxTitleLength - 1) + " tail"
        TestSupport.expectEqual(MeetingTranscriptCore.renamedTitle(cutAtSpace, current: "Old"), String(repeating: "b", count: 119))
    }

    private static func dayLabelsUseTodayYesterdayThenWeekday() {
        let now = date(21, hour: 0, minute: 30)
        let locale = Locale(identifier: "en_US")
        TestSupport.expectEqual(MeetingTranscriptCore.dayLabel(for: date(21, hour: 23), now: now, calendar: calendar, locale: locale), "Today")
        TestSupport.expectEqual(MeetingTranscriptCore.dayLabel(for: date(20, hour: 1), now: now, calendar: calendar, locale: locale), "Yesterday")
        TestSupport.expectEqual(MeetingTranscriptCore.dayLabel(for: date(19, hour: 23, minute: 59), now: now, calendar: calendar, locale: locale), "Monday, Oct 19")
    }

    private static func groupsMeetingsByDayNewestFirst() {
        func record(_ day: Int, _ hour: Int) -> MeetingRecord {
            MeetingRecord(title: "\(day)-\(hour)", date: date(day, hour: hour), duration: 60, segments: [])
        }
        let groups = MeetingTranscriptCore.groupedByDay(
            [record(20, 9), record(21, 8), record(20, 17), record(21, 23), record(18, 12)],
            calendar: calendar
        )
        TestSupport.expectEqual(groups.map(\.day), [date(21, hour: 0), date(20, hour: 0), date(18, hour: 0)])
        TestSupport.expectEqual(groups.map { $0.meetings.map(\.title) }, [["21-23", "21-8"], ["20-17", "20-9"], ["18-12"]])
        TestSupport.expect(MeetingTranscriptCore.groupedByDay([], calendar: calendar).isEmpty, "No meetings, no groups")
    }

    private static func displayLevelMapsDecibelRange() {
        TestSupport.expectEqual(MeetingTranscriptCore.displayLevel(rms: 0), 0)
        TestSupport.expectEqual(MeetingTranscriptCore.displayLevel(rms: 0.001), 0)
        TestSupport.expectApproximatelyEqual(Double(MeetingTranscriptCore.displayLevel(rms: 0.01)), 0.25, accuracy: 0.001)
        TestSupport.expectApproximatelyEqual(Double(MeetingTranscriptCore.displayLevel(rms: 0.1)), 0.75, accuracy: 0.001)
        TestSupport.expectEqual(MeetingTranscriptCore.displayLevel(rms: 0.5), 1)
    }

    private static func waveformBarsAreMirroredFromCenter() {
        let scales = (0..<5).map { MeetingTranscriptCore.waveformScale(index: $0, count: 5) }
        let expectedOuter = 1 - 18.0 / 48.0
        let expectedInner = 1 - 0.25 * 18.0 / 48.0
        for (actual, expected) in zip(scales, [expectedOuter, expectedInner, 1, expectedInner, expectedOuter]) {
            TestSupport.expectApproximatelyEqual(actual, expected)
        }
        TestSupport.expectEqual((0..<5).map { MeetingTranscriptCore.waveformDelay(index: $0, count: 5) }, [0.2, 0.1, 0, 0.1, 0.2])
        TestSupport.expectEqual(MeetingTranscriptCore.waveformScale(index: 0, count: 1), 1)
    }

    private static func wavDataHasValidHeaderAndClampedSamples() {
        let data = MeetingTranscriptCore.wavData([0, 1, -1, 2, 0.5], sampleRate: 16_000)
        func u32(_ offset: Int) -> UInt32 { data.subdata(in: offset..<offset + 4).withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) } }
        func u16(_ offset: Int) -> UInt16 { data.subdata(in: offset..<offset + 2).withUnsafeBytes { $0.loadUnaligned(as: UInt16.self) } }
        func i16(_ offset: Int) -> Int16 { Int16(bitPattern: u16(offset)) }
        TestSupport.expectEqual(data.count, 54)
        TestSupport.expectEqual(String(decoding: data.prefix(4), as: UTF8.self), "RIFF")
        TestSupport.expectEqual(u32(4), 46)
        TestSupport.expectEqual(String(decoding: data.subdata(in: 8..<16), as: UTF8.self), "WAVEfmt ")
        TestSupport.expectEqual(u32(16), 16)
        TestSupport.expectEqual(u16(20), 1)
        TestSupport.expectEqual(u16(22), 1)
        TestSupport.expectEqual(u32(24), 16_000)
        TestSupport.expectEqual(u32(28), 32_000)
        TestSupport.expectEqual(u16(32), 2)
        TestSupport.expectEqual(u16(34), 16)
        TestSupport.expectEqual(String(decoding: data.subdata(in: 36..<40), as: UTF8.self), "data")
        TestSupport.expectEqual(u32(40), 10)
        TestSupport.expectEqual([i16(44), i16(46), i16(48), i16(50), i16(52)], [0, 32767, -32767, 32767, 16384])
    }

    private static func chunkBufferWaitsForTargetThenQuietMoment() {
        var buffer = MeetingChunkBuffer(speaker: .me)
        TestSupport.expect(buffer.append(tone(seconds: 9.9), arrival: 9.9).isEmpty, "Below target keeps buffering")
        TestSupport.expect(buffer.append(tone(seconds: 0.5), arrival: 10.4).isEmpty, "Past target but still talking keeps buffering")
        let chunks = buffer.append(silence(seconds: 0.1), arrival: 10.5)
        TestSupport.expectEqual(chunks.count, 1)
        TestSupport.expectEqual(chunks.first?.speaker, .me)
        TestSupport.expectEqual(chunks.first?.samples.count, Int(10.5 * Double(rate)))
        TestSupport.expectEqual(chunks.first?.start, 0)
        TestSupport.expectEqual(buffer.pendingSeconds, 0)
        TestSupport.expect(buffer.append([], arrival: 11).isEmpty, "Empty input is ignored")
    }

    private static func chunkBufferCutsAtMaxEvenWhileTalking() {
        var buffer = MeetingChunkBuffer(speaker: .them)
        TestSupport.expect(buffer.append(tone(seconds: 14.9), arrival: 14.9).isEmpty, "Talking under max keeps buffering")
        let chunks = buffer.append(tone(seconds: 0.1), arrival: 15)
        TestSupport.expectEqual(chunks.count, 1)
        TestSupport.expectEqual(chunks.first?.samples.count, 15 * rate)
        TestSupport.expectApproximatelyEqual(chunks.first?.duration ?? 0, 15)
        TestSupport.expectEqual(chunks.first?.speaker, .them)
    }

    private static func chunkBufferTracksStartTimesAcrossChunks() {
        var buffer = MeetingChunkBuffer(speaker: .them)
        buffer.targetSeconds = 1
        buffer.maxSeconds = 2
        TestSupport.expect(buffer.append(tone(seconds: 0.5), arrival: 3.5).isEmpty, "First half second buffers")
        let first = buffer.append(silence(seconds: 0.5), arrival: 4.0).first
        TestSupport.expectApproximatelyEqual(first?.start ?? -1, 3.0)
        TestSupport.expect(buffer.append(silence(seconds: 1), arrival: 5).isEmpty, "Silence between lines is not a chunk")
        TestSupport.expect(buffer.append(tone(seconds: 1.5), arrival: 6.5).isEmpty, "Talking past the target keeps buffering")
        let second = buffer.append(silence(seconds: 0.1), arrival: 6.6).first
        TestSupport.expectApproximatelyEqual(second?.start ?? -1, 5.0)
        TestSupport.expectEqual(second?.samples.count, Int(1.8 * Double(rate)))

        var early = MeetingChunkBuffer(speaker: .me)
        _ = early.append(tone(seconds: 0.5), arrival: 0.2)
        TestSupport.expectEqual(early.flush()?.start, 0)
    }

    private static func chunkBufferFlushReturnsRemainderOnce() {
        var buffer = MeetingChunkBuffer(speaker: .me)
        TestSupport.expect(buffer.flush() == nil, "Nothing to flush before audio")
        _ = buffer.append(tone(seconds: 3), arrival: 13)
        let chunk = buffer.flush()
        TestSupport.expectEqual(chunk?.samples.count, 3 * rate)
        TestSupport.expectApproximatelyEqual(chunk?.start ?? -1, 10)
        TestSupport.expect(buffer.flush() == nil, "Second flush is empty")
    }

    private static func chunkBufferStartsAtSpeechOnset() {
        var buffer = MeetingChunkBuffer(speaker: .me)
        TestSupport.expect(buffer.append(silence(seconds: 8), arrival: 8).isEmpty, "Silence alone cuts nothing")
        TestSupport.expect(buffer.append(tone(seconds: 2), arrival: 10).isEmpty, "Speech under the target keeps buffering")
        let chunk = buffer.flush()
        TestSupport.expectApproximatelyEqual(chunk?.start ?? -1, 8)
        TestSupport.expectApproximatelyEqual(chunk?.audioStart ?? -1, 7.8)
        // 200 ms of quiet lead-in, then the speech; the rest of the silence is not uploaded.
        TestSupport.expectEqual(chunk?.samples.count, Int(2.2 * Double(rate)))
        TestSupport.expectEqual(Array(chunk?.samples.suffix(2 * rate) ?? []), tone(seconds: 2))
    }

    private static func chunkBufferCutsWhenSpeakerGoesQuiet() {
        var buffer = MeetingChunkBuffer(speaker: .them)
        TestSupport.expect(buffer.append(tone(seconds: 1), arrival: 1).isEmpty, "Still talking")
        TestSupport.expect(buffer.append(silence(seconds: 1.9), arrival: 2.9).isEmpty, "A short pause keeps the line open")
        let first = buffer.append(silence(seconds: 0.1), arrival: 3)
        TestSupport.expectEqual(first.count, 1)
        TestSupport.expectEqual(first.first?.start, 0)
        // The speech plus 600 ms of its trailing pause; the rest of the pause is dropped.
        TestSupport.expectEqual(first.first?.samples.count, Int(1.6 * Double(rate)))
        TestSupport.expect(buffer.append(silence(seconds: 1), arrival: 4).isEmpty, "Silence after a cut stays out")
        TestSupport.expect(buffer.append(tone(seconds: 1), arrival: 5).isEmpty, "Next line buffers")
        let second = buffer.flush()
        TestSupport.expectApproximatelyEqual(second?.start ?? -1, 4)
        TestSupport.expectEqual(second?.samples.count, Int(1.2 * Double(rate)))
    }

    private static func chunkBufferDropsBlipsButKeepsThemBeforeSpeech() {
        var lone = MeetingChunkBuffer(speaker: .me)
        TestSupport.expect(lone.append(tone(seconds: 0.2) + silence(seconds: 3), arrival: 3.2).isEmpty, "A lone blip is not uploaded")
        TestSupport.expect(lone.flush() == nil, "A dropped blip leaves nothing to flush")

        var unflushed = MeetingChunkBuffer(speaker: .me)
        _ = unflushed.append(silence(seconds: 1) + tone(seconds: 0.2), arrival: 1.2)
        TestSupport.expect(unflushed.flush() == nil, "A blip at stop is not uploaded")

        var shortest = MeetingChunkBuffer(speaker: .me)
        let word = shortest.append(tone(seconds: 0.3) + silence(seconds: 2), arrival: 2.3)
        TestSupport.expectEqual(word.map(\.start), [0])

        var merged = MeetingChunkBuffer(speaker: .them)
        _ = merged.append(silence(seconds: 2) + tone(seconds: 0.2) + silence(seconds: 1) + tone(seconds: 1), arrival: 4.2)
        let chunk = merged.flush()
        TestSupport.expectApproximatelyEqual(chunk?.start ?? -1, 2)
        TestSupport.expectEqual(chunk?.samples.count, Int(2.4 * Double(rate)))
    }

    private static func chunkBufferCapsLongSpeechAfterSilence() {
        var buffer = MeetingChunkBuffer(speaker: .them)
        let chunks = buffer.append(silence(seconds: 3) + tone(seconds: 20), arrival: 23)
        TestSupport.expectEqual(chunks.count, 1)
        TestSupport.expectApproximatelyEqual(chunks.first?.start ?? -1, 3)
        TestSupport.expectApproximatelyEqual(chunks.first?.duration ?? 0, 15)
        TestSupport.expectApproximatelyEqual(chunks.first?.audioStart ?? -1, 2.8)
        let rest = buffer.flush()
        TestSupport.expectApproximatelyEqual(rest?.start ?? -1, 17.8)
        // Cut mid-speech, so the rest has no quiet lead-in.
        TestSupport.expectApproximatelyEqual(rest?.audioStart ?? -1, 17.8)
        TestSupport.expectApproximatelyEqual(rest?.duration ?? 0, 5.2)

        var marathon = MeetingChunkBuffer(speaker: .me)
        let cuts = marathon.append(tone(seconds: 31), arrival: 31)
        TestSupport.expectEqual(cuts.map(\.start), [0, 15])
        TestSupport.expectEqual(cuts.map(\.samples.count), [15 * rate, 15 * rate])
        TestSupport.expectApproximatelyEqual(marathon.flush()?.start ?? -1, 30)
    }

    private static func chunkBufferFlushKeepsTailAndTrimsSilence() {
        var talking = MeetingChunkBuffer(speaker: .me)
        _ = talking.append(silence(seconds: 1) + tone(seconds: 2.05), arrival: 3.05)
        let tail = talking.flush()
        TestSupport.expectApproximatelyEqual(tail?.start ?? -1, 1)
        TestSupport.expectEqual(tail?.samples.count, Int(2.25 * Double(rate)))
        TestSupport.expect(talking.flush() == nil, "Second flush is empty")

        var paused = MeetingChunkBuffer(speaker: .them)
        _ = paused.append(tone(seconds: 1) + silence(seconds: 1.55), arrival: 2.55)
        TestSupport.expectEqual(paused.flush()?.samples.count, Int(1.6 * Double(rate)))
    }

    private static func chunkBufferEndsLineWhenOtherSideSpeaks() {
        var buffer = MeetingChunkBuffer(speaker: .them)
        _ = buffer.append(silence(seconds: 1) + tone(seconds: 1), arrival: 2)
        TestSupport.expect(
            buffer.append(silence(seconds: 1), arrival: 3, otherSpeechTime: 0.9).isEmpty,
            "Speech from the other side before this line began doesn't end it"
        )
        let cut = buffer.append(silence(seconds: 0.1), arrival: 3.1, otherSpeechTime: 2.5)
        TestSupport.expectEqual(cut.count, 1)
        TestSupport.expectApproximatelyEqual(cut.first?.start ?? -1, 1)
        TestSupport.expectApproximatelyEqual(cut.first?.audioStart ?? -1, 0.8)
        TestSupport.expectEqual(cut.first?.samples.count, Int(1.8 * Double(rate)))

        var reply = MeetingChunkBuffer(speaker: .me)
        _ = reply.append(tone(seconds: 1), arrival: 1)
        TestSupport.expect(
            reply.append(silence(seconds: 0.5), arrival: 1.5, otherSpeechTime: 1.2).isEmpty,
            "A breath shorter than the turn pause keeps the line open"
        )
        TestSupport.expectEqual(reply.append(silence(seconds: 0.1), arrival: 1.6, otherSpeechTime: 1.2).map(\.start), [0])

        var talking = MeetingChunkBuffer(speaker: .me)
        TestSupport.expect(
            talking.append(tone(seconds: 3), arrival: 3, otherSpeechTime: 2).isEmpty,
            "The other side talking over this one doesn't cut mid-speech"
        )
    }

    private static func chunkBufferReportsLastSpeechButNotBlips() {
        var buffer = MeetingChunkBuffer(speaker: .me)
        _ = buffer.append(silence(seconds: 1) + tone(seconds: 0.2), arrival: 1.2)
        TestSupport.expect(buffer.lastSpeechTime == nil, "Two voiced windows are a blip, not speech")
        _ = buffer.append(tone(seconds: 0.1), arrival: 1.3)
        TestSupport.expectApproximatelyEqual(buffer.lastSpeechTime ?? -1, 1.3)
        _ = buffer.append(tone(seconds: 0.5) + silence(seconds: 3), arrival: 4.8)
        TestSupport.expectApproximatelyEqual(buffer.lastSpeechTime ?? -1, 1.8)
        _ = buffer.append(tone(seconds: 0.2) + silence(seconds: 3), arrival: 8)
        TestSupport.expectApproximatelyEqual(buffer.lastSpeechTime ?? -1, 1.8)
    }

    private static func chunkBufferClockSkipsAheadAfterDroppedAudio() {
        var stalled = MeetingChunkBuffer(speaker: .me)
        TestSupport.expectEqual(stalled.append(tone(seconds: 1) + silence(seconds: 2), arrival: 3).map(\.start), [0])
        // The source delivers nothing from 3 s to 8 s, then resumes.
        _ = stalled.append(silence(seconds: 0.5), arrival: 8.5)
        _ = stalled.append(tone(seconds: 1), arrival: 9.5)
        TestSupport.expectApproximatelyEqual(stalled.flush()?.start ?? -1, 8.5, accuracy: 0.0001)

        var late = MeetingChunkBuffer(speaker: .them)
        _ = late.append(silence(seconds: 1), arrival: 1)
        _ = late.append(silence(seconds: 0.1), arrival: 1.6)
        _ = late.append(tone(seconds: 1), arrival: 2.6)
        TestSupport.expectApproximatelyEqual(late.flush()?.start ?? -1, 1.1, accuracy: 0.0001)

        var early = MeetingChunkBuffer(speaker: .them)
        _ = early.append(silence(seconds: 5), arrival: 1)
        _ = early.append(tone(seconds: 1), arrival: 1.1)
        TestSupport.expectApproximatelyEqual(early.flush()?.start ?? -1, 5, accuracy: 0.0001)
    }
}
