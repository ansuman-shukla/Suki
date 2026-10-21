import AppKit

/// App-wide theme. Defaults to light so the warm paper look shows regardless of the macOS setting.
enum AppAppearance: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    static let storageKey = "appearance_mode"
    static let defaultValue = AppAppearance.light

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    var appearanceName: NSAppearance.Name? {
        switch self {
        case .system: return nil
        case .light: return .aqua
        case .dark: return .darkAqua
        }
    }

    static func load(from defaults: UserDefaults) -> AppAppearance {
        defaults.string(forKey: storageKey).flatMap(AppAppearance.init(rawValue:)) ?? defaultValue
    }

    func apply() {
        NSApp.appearance = appearanceName.flatMap(NSAppearance.init(named:))
    }
}
