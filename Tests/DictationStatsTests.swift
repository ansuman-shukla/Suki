import Foundation

enum DictationStatsTests {
    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Kolkata")!
        return calendar
    }

    private static func date(_ day: Int, hour: Int = 12, minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 3, day: day, hour: hour, minute: minute))!
    }

    static func run() {
        wordCountSplitsOnAnyWhitespace()
        recordingAccumulatesPerLocalDay()
        emptyDictationsAreIgnored()
        wordsPerMinuteIgnoresUntimedDays()
        streakCountsConsecutiveDaysEndingTodayOrYesterday()
        roundTripsThroughDefaults()
    }

    private static func wordCountSplitsOnAnyWhitespace() {
        TestSupport.expectEqual(DictationStatsLog.wordCount("  hello   brave\nnew\tworld "), 4)
        TestSupport.expectEqual(DictationStatsLog.wordCount(""), 0)
        TestSupport.expectEqual(DictationStatsLog.wordCount(" \n\t "), 0)
    }

    private static func recordingAccumulatesPerLocalDay() {
        var log = DictationStatsLog()
        log.record(words: 10, seconds: 6, at: date(4, hour: 0, minute: 5), calendar: calendar)
        log.record(words: 5, seconds: 3, at: date(4, hour: 23, minute: 55), calendar: calendar)
        log.record(words: 7, seconds: -2, at: date(5), calendar: calendar)

        TestSupport.expectEqual(log.days["2026-03-04"], DailyDictationStats(words: 15, seconds: 9, count: 2))
        TestSupport.expectEqual(log.days["2026-03-05"], DailyDictationStats(words: 7, seconds: 0, count: 1))
        TestSupport.expectEqual(log.days.count, 2)
    }

    private static func emptyDictationsAreIgnored() {
        var log = DictationStatsLog()
        log.record(words: 0, seconds: 4, at: date(4), calendar: calendar)
        TestSupport.expect(log.days.isEmpty, "A dictation with no words must not count toward stats or streaks")
    }

    private static func wordsPerMinuteIgnoresUntimedDays() {
        var log = DictationStatsLog()
        log.record(words: 90, seconds: 30, at: date(4), calendar: calendar)
        log.record(words: 50, seconds: 0, at: date(5), calendar: calendar)
        let summary = log.summary(today: date(5), calendar: calendar)

        TestSupport.expectEqual(summary.totalWords, 140)
        TestSupport.expectEqual(summary.wordsPerMinute, 180)
        TestSupport.expectEqual(DictationStatsLog().summary(today: date(5), calendar: calendar).wordsPerMinute, 0)
    }

    private static func streakCountsConsecutiveDaysEndingTodayOrYesterday() {
        var log = DictationStatsLog()
        for day in [1, 3, 4, 5] {
            log.record(words: 1, seconds: 1, at: date(day), calendar: calendar)
        }

        TestSupport.expectEqual(log.summary(today: date(5), calendar: calendar).currentStreakDays, 3)
        TestSupport.expectEqual(log.summary(today: date(6), calendar: calendar).currentStreakDays, 3)
        TestSupport.expectEqual(log.summary(today: date(7), calendar: calendar).currentStreakDays, 0)
        TestSupport.expectEqual(log.summary(today: date(3), calendar: calendar).currentStreakDays, 1)
        TestSupport.expectEqual(log.summary(today: date(2), calendar: calendar).currentStreakDays, 1)
    }

    private static func roundTripsThroughDefaults() {
        let suite = "SukiTests.DictationStats.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        TestSupport.expectEqual(DictationStatsLog.load(from: defaults), DictationStatsLog())
        var log = DictationStatsLog()
        log.record(words: 12, seconds: 5, at: date(4), calendar: calendar)
        log.save(to: defaults)
        TestSupport.expectEqual(DictationStatsLog.load(from: UserDefaults(suiteName: suite)!), log)

        defaults.set(Data("not json".utf8), forKey: DictationStatsLog.storageKey)
        TestSupport.expectEqual(DictationStatsLog.load(from: defaults), DictationStatsLog())
    }
}
