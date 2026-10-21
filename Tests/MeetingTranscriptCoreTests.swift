import Foundation

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
        speakerDisplayNamesDifferFromCopiedLabels()
        transcriptSummaryCountsSpeakersWithText()
        timeLabelUsesLowercaseMeridiem()
        clockFormatsMinutesAndHours()
        defaultTitleUsesShortDateAndLowercaseMeridiem()
        dayLabelsUseTodayYesterdayThenWeekday()
        groupsMeetingsByDayNewestFirst()
        displayLevelMapsDecibelRange()
        waveformBarsAreMirroredFromCenter()
        wavDataHasValidHeaderAndClampedSamples()
        chunkBufferWaitsForTargetThenQuietMoment()
        chunkBufferCutsAtMaxEvenWhileTalking()
        chunkBufferTracksStartTimesAcrossChunks()
        chunkBufferFlushReturnsRemainderOnce()
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
        TestSupport.expect(buffer.append(tone(seconds: 9.9), arrival: 9.9) == nil, "Below target keeps buffering")
        TestSupport.expect(buffer.append(tone(seconds: 0.5), arrival: 10.4) == nil, "Past target but still talking keeps buffering")
        let chunk = buffer.append(silence(seconds: 0.1), arrival: 10.5)
        TestSupport.expectEqual(chunk?.speaker, .me)
        TestSupport.expectEqual(chunk?.samples.count, Int(10.5 * Double(rate)))
        TestSupport.expectEqual(chunk?.start, 0)
        TestSupport.expectEqual(buffer.pendingSeconds, 0)
        TestSupport.expect(buffer.append([], arrival: 11) == nil, "Empty input is ignored")
    }

    private static func chunkBufferCutsAtMaxEvenWhileTalking() {
        var buffer = MeetingChunkBuffer(speaker: .them)
        TestSupport.expect(buffer.append(tone(seconds: 14.9), arrival: 14.9) == nil, "Talking under max keeps buffering")
        let chunk = buffer.append(tone(seconds: 0.1), arrival: 15)
        TestSupport.expectEqual(chunk?.samples.count, 15 * rate)
        TestSupport.expectApproximatelyEqual(chunk?.duration ?? 0, 15)
        TestSupport.expectEqual(chunk?.speaker, .them)
    }

    private static func chunkBufferTracksStartTimesAcrossChunks() {
        var buffer = MeetingChunkBuffer(speaker: .them)
        buffer.targetSeconds = 1
        buffer.maxSeconds = 2
        TestSupport.expect(buffer.append(tone(seconds: 0.5), arrival: 3.5) == nil, "First half second buffers")
        let first = buffer.append(silence(seconds: 0.5), arrival: 4.0)
        TestSupport.expectApproximatelyEqual(first?.start ?? -1, 3.0)
        let second = buffer.append(silence(seconds: 1), arrival: 9)
        TestSupport.expectApproximatelyEqual(second?.start ?? -1, 4.0)
        TestSupport.expectEqual(second?.samples.count, rate)

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
}
