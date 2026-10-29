import AVFoundation
import Foundation

enum SukiSoundTests {
    private static let shippedSounds = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Resources/Sounds")

    static func run() {
        testNames()
        testShippedFilesAreShortSoftMonoClips()
        testLoadsBundledSound()
        testFallsBackToSystemSoundWhenFileIsMissing()
    }

    private static func testNames() {
        TestSupport.expectEqual(SukiSound.allCases, [.start, .stop, .paste, .error])
        TestSupport.expectEqual(
            SukiSound.allCases.map(\.resourceName),
            ["dictation-start", "dictation-stop", "paste", "error"]
        )
        TestSupport.expectEqual(SukiSound.allCases.map(\.fallbackSystemSoundName), ["Tink", "Pop", "Pop", "Basso"])
    }

    private static func testShippedFilesAreShortSoftMonoClips() {
        var durations: [SukiSound: Double] = [:]
        for sound in SukiSound.allCases {
            let url = shippedSounds.appendingPathComponent("\(sound.resourceName).caf")
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            TestSupport.expect(size > 0 && size < 30_000, "\(sound.resourceName) is \(size) bytes")

            let samples = readSamples(url)
            durations[sound] = Double(samples.count) / 44_100
            let peak = samples.map(abs).max() ?? 0
            TestSupport.expect(peak > 0.2 && peak < 0.6, "\(sound.resourceName) peak \(peak)")
            TestSupport.expect(abs(samples.first ?? 1) < 0.01, "\(sound.resourceName) starts with a click")
            TestSupport.expect(abs(samples.last ?? 1) < 0.01, "\(sound.resourceName) ends with a click")
        }
        TestSupport.expectApproximatelyEqual(durations[.start] ?? 0, 0.18, accuracy: 0.02)
        TestSupport.expectApproximatelyEqual(durations[.stop] ?? 0, 0.22, accuracy: 0.02)
        TestSupport.expect((durations[.paste] ?? 1) < 0.1, "paste should be a short pop")
        TestSupport.expect((durations[.error] ?? 1) <= 0.3, "error should stay short")
    }

    private static func testLoadsBundledSound() {
        let bundle = makeBundle(with: [.stop])
        TestSupport.expectEqual(
            SukiSound.stop.url(in: bundle)?.resolvingSymlinksInPath(),
            bundle.bundleURL.appendingPathComponent("Contents/Resources/Sounds/dictation-stop.caf").resolvingSymlinksInPath()
        )
        TestSupport.expect(SukiSound.start.url(in: bundle) == nil, "start was not bundled")

        let sound = SukiSound.stop.makeSound(in: bundle)
        TestSupport.expect(sound != nil, "bundled stop sound should load")
        TestSupport.expect(sound?.name == nil, "bundled sound should not be a named system sound")
        TestSupport.expectApproximatelyEqual(sound?.duration ?? 0, 0.22, accuracy: 0.02)
    }

    private static func testFallsBackToSystemSoundWhenFileIsMissing() {
        let bundle = makeBundle(with: [])
        for sound in SukiSound.allCases {
            TestSupport.expectEqual(sound.makeSound(in: bundle)?.name, sound.fallbackSystemSoundName)
        }
    }

    private static func makeBundle(with sounds: [SukiSound]) -> Bundle {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("SukiSoundTests-\(UUID().uuidString).bundle")
        let soundsDirectory = root.appendingPathComponent("Contents/Resources/Sounds")
        do {
            try FileManager.default.createDirectory(at: soundsDirectory, withIntermediateDirectories: true)
            for sound in sounds {
                let name = "\(sound.resourceName).caf"
                try FileManager.default.copyItem(
                    at: shippedSounds.appendingPathComponent(name),
                    to: soundsDirectory.appendingPathComponent(name)
                )
            }
        } catch {
            fatalError("Could not build synthetic bundle: \(error)")
        }
        guard let bundle = Bundle(url: root) else { fatalError("Could not open synthetic bundle") }
        return bundle
    }

    private static func readSamples(_ url: URL) -> [Float] {
        guard let file = try? AVAudioFile(forReading: url),
              let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)),
              (try? file.read(into: buffer)) != nil,
              let channel = buffer.floatChannelData?[0] else {
            fatalError("Could not read \(url.lastPathComponent)")
        }
        TestSupport.expectEqual(file.fileFormat.sampleRate, 44_100)
        TestSupport.expectEqual(file.fileFormat.channelCount, 1)
        return Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
    }
}
