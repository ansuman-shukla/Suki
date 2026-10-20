import Foundation

/// Text shown on the hub home page.
enum HomeCopy {
    static func firstName(fromFullName fullName: String) -> String? {
        fullName.split(whereSeparator: { $0.isWhitespace }).first.map(String.init)
    }

    static func greeting(firstName: String?) -> String {
        guard let firstName, !firstName.isEmpty else { return "Welcome back" }
        return "Hey \(firstName)"
    }

    /// The shortcut to advertise, preferring hold-to-talk. Nil when both are disabled.
    static func shortcutLabel(hold: ShortcutBinding, toggle: ShortcutBinding) -> String? {
        if !hold.isDisabled { return hold.displayName }
        if !toggle.isDisabled { return toggle.displayName }
        return nil
    }

    static func streakMessage(days: Int) -> String {
        switch days {
        case ..<1: return "Start a streak today"
        case 1: return "Day one — momentum begins."
        case 2: return "Two days running. Keep it going."
        case 3...4: return "On a roll — don't break the chain."
        case 5...6: return "Almost a full week!"
        case 7..<30: return "A full week and counting."
        default: return "A month strong. Unstoppable."
        }
    }

    static func formattedCount(_ value: Int, locale: Locale = .current) -> String {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = true
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }
}
