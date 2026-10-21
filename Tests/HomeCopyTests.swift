import Foundation

enum HomeCopyTests {
    static func run() {
        firstNameIsTheFirstWord()
        greetingFallsBackWithoutAName()
        greetingLeadOnlyMentionsShortcutWhenPresent()
        dictationShortcutPrefersHoldThenToggle()
        wordsPerMinuteShowsDashUntilMeasured()
        streakMessageFollowsStreakLength()
        countsUseLocaleGrouping()
    }

    private static func firstNameIsTheFirstWord() {
        TestSupport.expectEqual(HomeCopy.firstName(fromFullName: "Ada Lovelace"), "Ada")
        TestSupport.expectEqual(HomeCopy.firstName(fromFullName: "  Grace\tBrewster Hopper "), "Grace")
        TestSupport.expectEqual(HomeCopy.firstName(fromFullName: "Linus"), "Linus")
        TestSupport.expectEqual(HomeCopy.firstName(fromFullName: ""), nil)
        TestSupport.expectEqual(HomeCopy.firstName(fromFullName: " \n "), nil)
    }

    private static func greetingFallsBackWithoutAName() {
        TestSupport.expectEqual(HomeCopy.greeting(firstName: "Ada"), "Hey Ada")
        TestSupport.expectEqual(HomeCopy.greeting(firstName: nil), "Welcome back")
        TestSupport.expectEqual(HomeCopy.greeting(firstName: ""), "Welcome back")
    }

    private static func greetingLeadOnlyMentionsShortcutWhenPresent() {
        TestSupport.expectEqual(HomeCopy.greetingLead(firstName: "Ada", hasShortcut: true), "Hey Ada, get back into it with")
        TestSupport.expectEqual(HomeCopy.greetingLead(firstName: nil, hasShortcut: true), "Welcome back, get back into it with")
        TestSupport.expectEqual(HomeCopy.greetingLead(firstName: "Ada", hasShortcut: false), "Hey Ada")
        TestSupport.expectEqual(HomeCopy.greetingLead(firstName: nil, hasShortcut: false), "Welcome back")
    }

    private static func dictationShortcutPrefersHoldThenToggle() {
        let hold = ShortcutBinding.defaultHold
        let toggle = ShortcutBinding.defaultToggle
        TestSupport.expect(hold.displayName != toggle.displayName, "Fixture shortcuts must be distinguishable")

        let both = HomeCopy.dictationShortcut(hold: hold, toggle: toggle)
        TestSupport.expectEqual(both, HomeShortcut(label: hold.displayName, isHold: true))
        TestSupport.expectEqual(both?.verb, "Hold")

        let toggleOnly = HomeCopy.dictationShortcut(hold: .disabled, toggle: toggle)
        TestSupport.expectEqual(toggleOnly, HomeShortcut(label: toggle.displayName, isHold: false))
        TestSupport.expectEqual(toggleOnly?.verb, "Tap")

        TestSupport.expectEqual(HomeCopy.dictationShortcut(hold: hold, toggle: .disabled), HomeShortcut(label: hold.displayName, isHold: true))
        TestSupport.expectEqual(HomeCopy.dictationShortcut(hold: .disabled, toggle: .disabled), nil)
    }

    private static func wordsPerMinuteShowsDashUntilMeasured() {
        let locale = Locale(identifier: "en_US")
        TestSupport.expectEqual(HomeCopy.wordsPerMinuteValue(0, locale: locale), "—")
        TestSupport.expectEqual(HomeCopy.wordsPerMinuteValue(-3, locale: locale), "—")
        TestSupport.expectEqual(HomeCopy.wordsPerMinuteValue(1, locale: locale), "1")
        TestSupport.expectEqual(HomeCopy.wordsPerMinuteValue(1_250, locale: locale), "1,250")
    }

    private static func streakMessageFollowsStreakLength() {
        let expected: [(Int, String)] = [
            (-1, "Start a streak today"),
            (0, "Start a streak today"),
            (1, "Day one — momentum begins."),
            (2, "Two days running. Keep it going."),
            (3, "On a roll — don't break the chain."),
            (4, "On a roll — don't break the chain."),
            (5, "Almost a full week!"),
            (6, "Almost a full week!"),
            (7, "A full week and counting."),
            (29, "A full week and counting."),
            (30, "A month strong. Unstoppable."),
            (365, "A month strong. Unstoppable.")
        ]
        for (days, message) in expected {
            TestSupport.expectEqual(HomeCopy.streakMessage(days: days), message)
        }
    }

    private static func countsUseLocaleGrouping() {
        let locale = Locale(identifier: "en_US_POSIX")
        TestSupport.expectEqual(HomeCopy.formattedCount(0, locale: locale), "0")
        TestSupport.expectEqual(HomeCopy.formattedCount(999, locale: locale), "999")
        TestSupport.expectEqual(HomeCopy.formattedCount(1_234_567, locale: Locale(identifier: "en_US")), "1,234,567")
        TestSupport.expectEqual(HomeCopy.formattedCount(12_480, locale: Locale(identifier: "de_DE")), "12.480")
    }
}
