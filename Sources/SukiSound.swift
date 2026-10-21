import AppKit

/// Alert sounds bundled under `Contents/Resources/Sounds`.
enum SukiSound: CaseIterable {
    case start
    case stop
    case paste
    case error

    var resourceName: String {
        switch self {
        case .start: return "dictation-start"
        case .stop: return "dictation-stop"
        case .paste: return "paste"
        case .error: return "error"
        }
    }

    /// System sound used when the bundled file is missing.
    var fallbackSystemSoundName: String {
        switch self {
        case .start: return "Tink"
        case .stop, .paste: return "Pop"
        case .error: return "Basso"
        }
    }

    func url(in bundle: Bundle = .main) -> URL? {
        bundle.url(forResource: resourceName, withExtension: "caf", subdirectory: "Sounds")
    }

    func makeSound(in bundle: Bundle = .main) -> NSSound? {
        if let url = url(in: bundle), let sound = NSSound(contentsOf: url, byReference: true) {
            return sound
        }
        return NSSound(named: fallbackSystemSoundName)
    }
}
