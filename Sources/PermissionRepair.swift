import Foundation

/// Privacy permissions whose system prompt cannot fix a stale grant on its own.
/// macOS pins each grant to the app's code signature; after the signature changes,
/// System Settings keeps showing the old row as enabled while the app is denied.
enum PrivacyPermission: String, CaseIterable {
    case accessibility = "Accessibility"
    case screenRecording = "ScreenCapture"

    var displayName: String {
        switch self {
        case .accessibility: return "Accessibility"
        case .screenRecording: return "Screen Recording"
        }
    }
}

/// Remembers which permissions this install has held, so a later denial can be
/// recognised as a lost grant rather than one the user never gave.
struct PermissionGrantHistory {
    static let storageKeyPrefix = "permission_previously_granted_"

    let defaults: UserDefaults

    func record(_ permission: PrivacyPermission, granted: Bool) {
        guard granted else { return }
        defaults.set(true, forKey: Self.storageKey(for: permission))
    }

    func wasLost(_ permission: PrivacyPermission, currentlyGranted: Bool) -> Bool {
        !currentlyGranted && defaults.bool(forKey: Self.storageKey(for: permission))
    }

    func forget(_ permission: PrivacyPermission) {
        defaults.removeObject(forKey: Self.storageKey(for: permission))
    }

    static func storageKey(for permission: PrivacyPermission) -> String {
        storageKeyPrefix + permission.rawValue
    }
}

enum PermissionResetError: LocalizedError, Equatable {
    case missingBundleIdentifier
    case toolFailed(exitCode: Int32)

    var errorDescription: String? {
        switch self {
        case .missingBundleIdentifier:
            return "\(AppName.displayName) could not determine its own bundle identifier."
        case .toolFailed(let exitCode):
            return "Resetting the permission failed (tccutil exit code \(exitCode))."
        }
    }
}

/// Clears this app's stored grant so the next request creates a fresh record that
/// matches the running signature.
enum PermissionReset {
    typealias ToolRunner = (_ executable: URL, _ arguments: [String]) throws -> Int32

    static let toolURL = URL(fileURLWithPath: "/usr/bin/tccutil")

    static func arguments(for permission: PrivacyPermission, bundleIdentifier: String) -> [String] {
        ["reset", permission.rawValue, bundleIdentifier]
    }

    static func reset(
        _ permission: PrivacyPermission,
        bundleIdentifier: String?,
        history: PermissionGrantHistory,
        runTool: ToolRunner = runProcess
    ) throws {
        // Without a bundle identifier tccutil resets the permission for every app on the Mac.
        guard let bundleIdentifier, !bundleIdentifier.isEmpty else {
            throw PermissionResetError.missingBundleIdentifier
        }
        let exitCode = try runTool(toolURL, arguments(for: permission, bundleIdentifier: bundleIdentifier))
        guard exitCode == 0 else { throw PermissionResetError.toolFailed(exitCode: exitCode) }
        history.forget(permission)
    }

    static func runProcess(_ executable: URL, _ arguments: [String]) throws -> Int32 {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus
    }
}
