import Foundation

struct HomeHistoryEntry: Equatable, Identifiable {
    let id: UUID
    let timestamp: Date
    /// Nil when the run produced no transcript, e.g. a failed transcription that can still be retried.
    let text: String?
    let hasAudio: Bool
}

struct HomeHistoryGroup: Equatable, Identifiable {
    let day: Date
    let title: String
    let entries: [HomeHistoryEntry]

    var id: Date { day }
}

enum HomeHistoryGrouping {
    /// Skips runs that have neither a transcript nor audio, since there is nothing to show or retry.
    static func entry(from item: PipelineHistoryItem) -> HomeHistoryEntry? {
        let text = displayText(postProcessed: item.postProcessedTranscript, raw: item.rawTranscript)
        let hasAudio = item.audioFileName != nil
        guard text != nil || hasAudio else { return nil }
        return HomeHistoryEntry(id: item.id, timestamp: item.timestamp, text: text, hasAudio: hasAudio)
    }

    static func displayText(postProcessed: String, raw: String) -> String? {
        let cleaned = postProcessed.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleaned.isEmpty { return cleaned }
        let fallback = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return fallback.isEmpty ? nil : fallback
    }

    /// Newest day first, newest entry first within each day.
    static func groups(
        _ entries: [HomeHistoryEntry],
        now: Date,
        calendar: Calendar = .current,
        locale: Locale = .current
    ) -> [HomeHistoryGroup] {
        let byDay = Dictionary(grouping: entries) { calendar.startOfDay(for: $0.timestamp) }
        return byDay.keys.sorted(by: >).map { day in
            HomeHistoryGroup(
                day: day,
                title: sectionTitle(for: day, now: now, calendar: calendar, locale: locale),
                entries: byDay[day, default: []].sorted { $0.timestamp > $1.timestamp }
            )
        }
    }

    static func sectionTitle(for date: Date, now: Date, calendar: Calendar = .current, locale: Locale = .current) -> String {
        let day = calendar.startOfDay(for: date)
        let today = calendar.startOfDay(for: now)
        if day == today { return "Today" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: today), day == yesterday {
            return "Yesterday"
        }
        let sameYear = calendar.component(.year, from: day) == calendar.component(.year, from: today)
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = locale
        formatter.setLocalizedDateFormatFromTemplate(sameYear ? "EEEEMMMMd" : "EEEEMMMMdy")
        return formatter.string(from: day)
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "h:mma"
        formatter.amSymbol = "am"
        formatter.pmSymbol = "pm"
        return formatter
    }()

    /// Compact 12-hour time such as "11:07pm".
    static func timeLabel(for date: Date, calendar: Calendar = .current) -> String {
        timeFormatter.calendar = calendar
        timeFormatter.timeZone = calendar.timeZone
        return timeFormatter.string(from: date)
    }
}
