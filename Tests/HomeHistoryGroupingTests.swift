import Foundation

enum HomeHistoryGroupingTests {
    private static let locale = Locale(identifier: "en_US_POSIX")

    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Kolkata")!
        calendar.locale = locale
        return calendar
    }

    private static func date(_ year: Int = 2026, _ month: Int = 3, day: Int, hour: Int = 12, minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    private static func entry(_ timestamp: Date, _ text: String) -> HomeHistoryEntry {
        HomeHistoryEntry(id: UUID(), timestamp: timestamp, text: text, hasAudio: false)
    }

    private static func item(raw: String, processed: String, audio: String?) -> PipelineHistoryItem {
        PipelineHistoryItem(
            timestamp: date(day: 5, hour: 9),
            rawTranscript: raw,
            postProcessedTranscript: processed,
            postProcessingPrompt: nil,
            contextSummary: "",
            contextScreenshotDataURL: nil,
            contextScreenshotStatus: "",
            postProcessingStatus: "",
            debugStatus: "",
            customVocabulary: "",
            audioFileName: audio
        )
    }

    static func run() {
        displayTextPrefersCleanedTranscript()
        entryKeepsRetryableRunsAndDropsEmptyOnes()
        groupsByLocalDayNewestFirst()
        sectionTitlesUseRelativeNamesThenWeekdayDates()
        timeLabelsAreCompactTwelveHourInCalendarTimeZone()
    }

    private static func displayTextPrefersCleanedTranscript() {
        TestSupport.expectEqual(HomeHistoryGrouping.displayText(postProcessed: "  Clean text.\n", raw: "clean text"), "Clean text.")
        TestSupport.expectEqual(HomeHistoryGrouping.displayText(postProcessed: " \n ", raw: "  raw words "), "raw words")
        TestSupport.expectEqual(HomeHistoryGrouping.displayText(postProcessed: "", raw: "\t"), nil)
    }

    private static func entryKeepsRetryableRunsAndDropsEmptyOnes() {
        let spoken = item(raw: "hello there", processed: "Hello there.", audio: nil)
        TestSupport.expectEqual(
            HomeHistoryGrouping.entry(from: spoken),
            HomeHistoryEntry(id: spoken.id, timestamp: spoken.timestamp, text: "Hello there.", hasAudio: false)
        )

        let failed = item(raw: "", processed: " ", audio: "run.wav")
        TestSupport.expectEqual(
            HomeHistoryGrouping.entry(from: failed),
            HomeHistoryEntry(id: failed.id, timestamp: failed.timestamp, text: nil, hasAudio: true)
        )

        TestSupport.expectEqual(HomeHistoryGrouping.entry(from: item(raw: " ", processed: "", audio: nil)), nil)
    }

    private static func groupsByLocalDayNewestFirst() {
        let now = date(day: 10, hour: 15)
        let earlyToday = entry(date(day: 10, hour: 0, minute: 30), "early today")
        let lateToday = entry(date(day: 10, hour: 14), "late today")
        let lateYesterday = entry(date(day: 9, hour: 23, minute: 59), "late yesterday")
        let lastWeek = entry(date(day: 5, hour: 8), "last week")
        let lastYear = entry(date(2025, 12, day: 31, hour: 22), "last year")

        let groups = HomeHistoryGrouping.groups(
            [lastWeek, earlyToday, lastYear, lateYesterday, lateToday],
            now: now,
            calendar: calendar,
            locale: locale
        )

        TestSupport.expectEqual(groups.map(\.title), ["Today", "Yesterday", "Thursday, March 5", "Wednesday, December 31, 2025"])
        TestSupport.expectEqual(groups.map(\.day), [date(day: 10, hour: 0), date(day: 9, hour: 0), date(day: 5, hour: 0), date(2025, 12, day: 31, hour: 0)])
        TestSupport.expectEqual(groups.map { $0.entries.map(\.text) }, [
            ["late today", "early today"],
            ["late yesterday"],
            ["last week"],
            ["last year"]
        ])
        TestSupport.expect(HomeHistoryGrouping.groups([], now: now, calendar: calendar, locale: locale).isEmpty, "No history means no groups")
    }

    private static func sectionTitlesUseRelativeNamesThenWeekdayDates() {
        let now = date(day: 1, hour: 0, minute: 10)
        func title(_ date: Date) -> String {
            HomeHistoryGrouping.sectionTitle(for: date, now: now, calendar: calendar, locale: locale)
        }

        TestSupport.expectEqual(title(date(day: 1, hour: 23, minute: 59)), "Today")
        TestSupport.expectEqual(title(date(2026, 2, day: 28, hour: 23, minute: 59)), "Yesterday")
        TestSupport.expectEqual(title(date(2026, 2, day: 28, hour: 0)), "Yesterday")
        TestSupport.expectEqual(title(date(2026, 2, day: 27, hour: 23, minute: 59)), "Friday, February 27")
        TestSupport.expectEqual(title(date(2026, 3, day: 2)), "Monday, March 2")
        TestSupport.expectEqual(title(date(2025, 3, day: 1)), "Saturday, March 1, 2025")
    }

    private static func timeLabelsAreCompactTwelveHourInCalendarTimeZone() {
        TestSupport.expectEqual(HomeHistoryGrouping.timeLabel(for: date(day: 4, hour: 23, minute: 7), calendar: calendar), "11:07pm")
        TestSupport.expectEqual(HomeHistoryGrouping.timeLabel(for: date(day: 4, hour: 9, minute: 5), calendar: calendar), "9:05am")
        TestSupport.expectEqual(HomeHistoryGrouping.timeLabel(for: date(day: 4, hour: 0), calendar: calendar), "12:00am")
        TestSupport.expectEqual(HomeHistoryGrouping.timeLabel(for: date(day: 4, hour: 12, minute: 30), calendar: calendar), "12:30pm")

        var utc = calendar
        utc.timeZone = TimeZone(identifier: "UTC")!
        TestSupport.expectEqual(HomeHistoryGrouping.timeLabel(for: date(day: 4, hour: 9, minute: 5), calendar: utc), "3:35am")
    }
}
