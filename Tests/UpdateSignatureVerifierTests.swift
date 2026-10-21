import Foundation
import Security

enum UpdateSignatureVerifierTests {
    static func run() {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("UpdateSignatureVerifierTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        signedBundlePassesItsOwnRequirement(root)
        anotherSignerFailsTheRequirement(root)
        newBuildFromTheSameIdentityPasses(root)
        unsignedBundleIsRefused(root)
        tamperedBundleIsRefused(root)
        runningAppRequirementRejectsOtherCode(root)
    }

    /// A minimal app bundle around a copy of /usr/bin/true with its Apple signature removed.
    private static func makeBundle(
        _ root: URL,
        name: String,
        identifier: String = "com.example.synthetic",
        marker: String = "one",
        sign: Bool = true
    ) -> URL {
        let app = root.appendingPathComponent("\(name).app")
        let contents = app.appendingPathComponent("Contents")
        let macOS = contents.appendingPathComponent("MacOS")
        let resources = contents.appendingPathComponent("Resources")
        try! FileManager.default.createDirectory(at: macOS, withIntermediateDirectories: true)
        try! FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
        let executable = macOS.appendingPathComponent(name)
        try! FileManager.default.copyItem(at: URL(fileURLWithPath: "/usr/bin/true"), to: executable)
        run("/usr/bin/codesign", "--remove-signature", executable.path)
        let plist: [String: Any] = [
            "CFBundleIdentifier": identifier,
            "CFBundleExecutable": name,
            "CFBundlePackageType": "APPL",
            "CFBundleShortVersionString": "1.0.0",
        ]
        try! PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            .write(to: contents.appendingPathComponent("Info.plist"))
        try! Data(marker.utf8).write(to: resources.appendingPathComponent("marker.txt"))
        if sign { run("/usr/bin/codesign", "--force", "--sign", "-", app.path) }
        return app
    }

    private static func run(_ tool: String, _ arguments: String...) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try! process.run()
        process.waitUntilExit()
        TestSupport.expectEqual(process.terminationStatus, 0)
    }

    private static func failure(_ body: () throws -> Void) -> UpdateSignatureVerifier.Failure? {
        do {
            try body()
            return nil
        } catch {
            return error as? UpdateSignatureVerifier.Failure
        }
    }

    private static func requirement(_ text: String) -> SecRequirement {
        var requirement: SecRequirement?
        TestSupport.expectEqual(SecRequirementCreateWithString(text as CFString, [], &requirement), errSecSuccess)
        return requirement!
    }

    private static func signedBundlePassesItsOwnRequirement(_ root: URL) {
        let app = makeBundle(root, name: "Own")
        let failure = failure { try UpdateSignatureVerifier.verify(appAt: app, satisfies: UpdateSignatureVerifier.requirement(ofAppAt: app)) }
        TestSupport.expect(failure == nil, "A bundle satisfies its own designated requirement, got \(String(describing: failure))")
    }

    /// Ad-hoc requirements pin the exact code, so any other build stands in for a different signer.
    private static func anotherSignerFailsTheRequirement(_ root: URL) {
        let installed = makeBundle(root, name: "InstalledA")
        let download = makeBundle(root, name: "DownloadA", marker: "two")
        let required = try! UpdateSignatureVerifier.requirement(ofAppAt: installed)
        TestSupport.expectEqual(failure { try UpdateSignatureVerifier.verify(appAt: download, satisfies: required) }, .differentSigner)
    }

    private static func newBuildFromTheSameIdentityPasses(_ root: URL) {
        let required = requirement("identifier \"com.example.synthetic\"")
        let first = makeBundle(root, name: "BuildOne", marker: "one")
        let second = makeBundle(root, name: "BuildTwo", marker: "two")
        let otherApp = makeBundle(root, name: "OtherApp", identifier: "com.example.other")
        TestSupport.expect(failure { try UpdateSignatureVerifier.verify(appAt: first, satisfies: required) } == nil, "First build passes")
        TestSupport.expect(failure { try UpdateSignatureVerifier.verify(appAt: second, satisfies: required) } == nil, "A new build with the same identity passes")
        TestSupport.expectEqual(failure { try UpdateSignatureVerifier.verify(appAt: otherApp, satisfies: required) }, .differentSigner)
    }

    private static func unsignedBundleIsRefused(_ root: URL) {
        let app = makeBundle(root, name: "Unsigned", sign: false)
        let required = requirement("identifier \"com.example.synthetic\"")
        TestSupport.expectEqual(failure { try UpdateSignatureVerifier.verify(appAt: app, satisfies: required) }, .unsigned)
        TestSupport.expectEqual(failure { _ = try UpdateSignatureVerifier.requirement(ofAppAt: app) }, .unsigned)
    }

    private static func tamperedBundleIsRefused(_ root: URL) {
        let app = makeBundle(root, name: "Tampered")
        let required = try! UpdateSignatureVerifier.requirement(ofAppAt: app)
        try! Data("swapped".utf8).write(to: app.appendingPathComponent("Contents/Resources/marker.txt"))
        guard case .invalidSignature? = failure({ try UpdateSignatureVerifier.verify(appAt: app, satisfies: required) }) else {
            return TestSupport.expect(false, "A bundle changed after signing is refused as damaged")
        }
    }

    private static func runningAppRequirementRejectsOtherCode(_ root: URL) {
        let failure = failure {
            let own = try UpdateSignatureVerifier.currentRequirement()
            try UpdateSignatureVerifier.verify(appAt: makeBundle(root, name: "Stranger"), satisfies: own)
        }
        TestSupport.expectEqual(failure, .differentSigner)
    }
}
