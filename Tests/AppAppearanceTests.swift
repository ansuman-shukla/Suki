import Foundation

enum AppAppearanceTests {
    static func run() {
        defaultsToLightWhenUnset()
        loadsSavedChoice()
        fallsBackToLightForUnknownValue()
        mapsToAppKitAppearanceNames()
    }

    private static func makeDefaults() -> UserDefaults {
        let suite = "AppAppearanceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    private static func defaultsToLightWhenUnset() {
        TestSupport.expectEqual(AppAppearance.load(from: makeDefaults()), .light)
    }

    private static func loadsSavedChoice() {
        let defaults = makeDefaults()
        for appearance in AppAppearance.allCases {
            defaults.set(appearance.rawValue, forKey: "appearance_mode")
            TestSupport.expectEqual(AppAppearance.load(from: defaults), appearance)
        }
    }

    private static func fallsBackToLightForUnknownValue() {
        let defaults = makeDefaults()
        defaults.set("sepia", forKey: "appearance_mode")
        TestSupport.expectEqual(AppAppearance.load(from: defaults), .light)
    }

    private static func mapsToAppKitAppearanceNames() {
        TestSupport.expectEqual(AppAppearance.system.appearanceName, nil)
        TestSupport.expectEqual(AppAppearance.light.appearanceName, .aqua)
        TestSupport.expectEqual(AppAppearance.dark.appearanceName, .darkAqua)
    }
}
