import AudioToolbox
import AVFoundation
import CoreAudio

/// One side of a meeting. `onSamples` may be called on any thread with mono 16 kHz samples.
protocol MeetingAudioSource: AnyObject {
    var speaker: MeetingSpeaker { get }
    func start(onSamples: @escaping ([Float]) -> Void) throws
    func stop()
}

/// Downmixes and resamples any PCM buffer to mono 16 kHz floats. Not thread-safe; use from one queue.
final class MeetingSampleConverter {
    private let converter: AVAudioConverter
    private let outputFormat: AVAudioFormat

    init?(inputFormat: AVAudioFormat) {
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0,
              let outputFormat = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: MeetingTranscriptCore.sampleRate,
                channels: 1,
                interleaved: false
              ),
              let converter = AVAudioConverter(from: inputFormat, to: outputFormat)
        else { return nil }
        converter.downmix = true
        self.converter = converter
        self.outputFormat = outputFormat
    }

    func convert(_ buffer: AVAudioPCMBuffer) -> [Float] {
        guard buffer.frameLength > 0 else { return [] }
        let ratio = outputFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 64
        guard let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else { return [] }
        var consumed = false
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, inputStatus in
            if consumed {
                inputStatus.pointee = .noDataNow
                return nil
            }
            consumed = true
            inputStatus.pointee = .haveData
            return buffer
        }
        guard status != .error, let channel = output.floatChannelData?[0] else { return [] }
        return Array(UnsafeBufferPointer(start: channel, count: Int(output.frameLength)))
    }
}

/// "Me": the microphone Suki already uses for dictation, captured with AVAudioEngine.
final class MeetingMicrophoneSource: MeetingAudioSource {
    let speaker = MeetingSpeaker.me
    private let engine = AVAudioEngine()
    private let deviceUID: String?

    init(deviceUID: String?) {
        self.deviceUID = deviceUID
    }

    func start(onSamples: @escaping ([Float]) -> Void) throws {
        let input = engine.inputNode
        if let deviceUID, var deviceID = Self.deviceID(forUID: deviceUID), let unit = input.audioUnit {
            AudioUnitSetProperty(
                unit,
                kAudioOutputUnitProperty_CurrentDevice,
                kAudioUnitScope_Global,
                0,
                &deviceID,
                UInt32(MemoryLayout<AudioDeviceID>.size)
            )
        }
        let format = input.outputFormat(forBus: 0)
        guard let converter = MeetingSampleConverter(inputFormat: format) else {
            throw MeetingRecorderError.audioSetupFailed("no microphone input")
        }
        input.installTap(onBus: 0, bufferSize: 4096, format: format) { buffer, _ in
            let samples = converter.convert(buffer)
            if !samples.isEmpty { onSamples(samples) }
        }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            throw MeetingRecorderError.audioSetupFailed("microphone unavailable")
        }
    }

    func stop() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
    }

    private static func deviceID(forUID uid: String) -> AudioDeviceID? {
        guard !uid.isEmpty, uid != "default" else { return nil }
        var deviceID = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var cfUID = uid as CFString
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyTranslateUIDToDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = withUnsafePointer(to: &cfUID) {
            AudioObjectGetPropertyData(
                AudioObjectID(kAudioObjectSystemObject),
                &address,
                UInt32(MemoryLayout<CFString>.size),
                $0,
                &size,
                &deviceID
            )
        }
        return status == noErr && deviceID != kAudioObjectUnknown ? deviceID : nil
    }
}
