import Foundation

/// Per-day dictation totals. Holds counts only, never transcript text.
struct DailyDictationStats: Codable, Equatable {
    var words: Int = 0
    var seconds: Double = 0
    var count: Int = 0
}

struct DictationStatsSummary: Equatable {
    let totalWords: Int
    let wordsPerMinute: Int
    let currentStreakDays: Int
}

/// Lifetime dictation stats keyed by local calendar day ("yyyy-MM-dd").
struct DictationStatsLog: Codable, Equatable {
    static let storageKey = "dictation_stats_log"

    private(set) var days: [String: DailyDictationStats] = [:]

    static func wordCount(_ text: String) -> Int {
        text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
    }

    mutating func record(words: Int, seconds: Double, at date: Date, calendar: Calendar = .current) {
        guard words > 0 else { return }
        let key = Self.dayKey(for: date, calendar: calendar)
        var day = days[key] ?? DailyDictationStats()
        day.words += words
        day.seconds += max(0, seconds)
        day.count += 1
        days[key] = day
    }

    func summary(today: Date, calendar: Calendar = .current) -> DictationStatsSummary {
        let totalWords = days.values.reduce(0) { $0 + $1.words }
        let timedDays = days.values.filter { $0.seconds > 0 }
        let timedWords = timedDays.reduce(0) { $0 + $1.words }
        let timedMinutes = timedDays.reduce(0) { $0 + $1.seconds } / 60
        let wordsPerMinute = timedMinutes > 0 ? Int((Double(timedWords) / timedMinutes).rounded()) : 0
        return DictationStatsSummary(
            totalWords: totalWords,
            wordsPerMinute: wordsPerMinute,
            currentStreakDays: currentStreak(today: today, calendar: calendar)
        )
    }

    /// Consecutive dictation days ending today. A streak stays alive through today
    /// if the last dictation was yesterday, so it doesn't reset first thing in the morning.
    private func currentStreak(today: Date, calendar: Calendar) -> Int {
        var day = calendar.startOfDay(for: today)
        if days[Self.dayKey(for: day, calendar: calendar)] == nil {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: day) else { return 0 }
            day = yesterday
        }
        var streak = 0
        while days[Self.dayKey(for: day, calendar: calendar)] != nil {
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }
        return streak
    }

    static func dayKey(for date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    static func load(from defaults: UserDefaults) -> DictationStatsLog {
        guard let data = defaults.data(forKey: storageKey),
              let log = try? JSONDecoder().decode(DictationStatsLog.self, from: data) else {
            return DictationStatsLog()
        }
        return log
    }

    func save(to defaults: UserDefaults) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }
}
