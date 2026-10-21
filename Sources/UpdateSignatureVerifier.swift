import Foundation
import Security

/// Refuses a downloaded update unless it is signed by the same identity as the running app.
/// The updater writes the download itself, so it is never quarantined and Gatekeeper never looks at it.
enum UpdateSignatureVerifier {
    enum Failure: LocalizedError, Equatable {
        case unsigned
        case differentSigner
        case invalidSignature(OSStatus)
        case ownSignatureUnreadable(OSStatus)

        var errorDescription: String? {
            switch self {
            case .unsigned, .differentSigner:
                return "This update isn't signed by Suki's developer, so it wasn't installed."
            case .invalidSignature:
                return "This update's signature is damaged, so it wasn't installed."
            case .ownSignatureUnreadable:
                return "Suki couldn't read its own signature to check this update, so it wasn't installed."
            }
        }
    }

    /// The running app's designated requirement: its bundle identifier plus its signing certificate.
    static func currentRequirement() throws -> SecRequirement {
        var code: SecCode?
        var staticCode: SecStaticCode?
        var status = SecCodeCopySelf([], &code)
        if status == errSecSuccess, let code { status = SecCodeCopyStaticCode(code, [], &staticCode) }
        guard status == errSecSuccess, let staticCode else { throw Failure.ownSignatureUnreadable(status) }
        return try designatedRequirement(of: staticCode)
    }

    /// The designated requirement of the app bundle at `url`.
    static func requirement(ofAppAt url: URL) throws -> SecRequirement {
        try designatedRequirement(of: staticCode(at: url))
    }

    /// Checks every architecture and nested code of the bundle at `url` against `requirement`.
    static func verify(appAt url: URL, satisfies requirement: SecRequirement) throws {
        let flags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSStrictValidate | kSecCSCheckNestedCode)
        let status = SecStaticCodeCheckValidity(try staticCode(at: url), flags, requirement)
        switch status {
        case errSecSuccess: return
        case errSecCSUnsigned: throw Failure.unsigned
        case errSecCSReqFailed: throw Failure.differentSigner
        default: throw Failure.invalidSignature(status)
        }
    }

    private static func staticCode(at url: URL) throws -> SecStaticCode {
        var code: SecStaticCode?
        let status = SecStaticCodeCreateWithPath(url as CFURL, [], &code)
        guard status == errSecSuccess, let code else { throw Failure.invalidSignature(status) }
        return code
    }

    private static func designatedRequirement(of code: SecStaticCode) throws -> SecRequirement {
        var requirement: SecRequirement?
        let status = SecCodeCopyDesignatedRequirement(code, [], &requirement)
        switch status {
        case errSecSuccess:
            guard let requirement else { throw Failure.ownSignatureUnreadable(status) }
            return requirement
        case errSecCSUnsigned:
            throw Failure.unsigned
        default:
            throw Failure.invalidSignature(status)
        }
    }
}
