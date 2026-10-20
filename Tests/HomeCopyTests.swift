import Foundation

enum HomeCopyTests {
    static func run() {
        firstNameIsTheFirstWord()
        greetingFallsBackWithoutAName()
        shortcutLabelPrefersHoldThenToggle()
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

    private static func shortcutLabelPrefersHoldThenToggle() {
        let hold = ShortcutBinding.defaultHold
        let toggle = ShortcutBinding.defaultToggle
        TestSupport.expect(hold.displayName != toggle.displayName, "Fixture shortcuts must be distinguishable")

        TestSupport.expectEqual(HomeCopy.shortcutLabel(hold: hold, toggle: toggle), hold.displayName)
        TestSupport.expectEqual(HomeCopy.shortcutLabel(hold: .disabled, toggle: toggle), toggle.displayName)
        TestSupport.expectEqual(HomeCopy.shortcutLabel(hold: .disabled, toggle: .disabled), nil)
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
