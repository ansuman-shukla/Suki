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

/// "Me": the microphone, captured with AVAudioEngine in voice processing mode.
///
/// Voice processing matters for calls: call apps like WhatsApp put the mic in voice processing mode,
/// and macOS then hands plain (non voice processing) taps exact digital silence. It also cancels the
/// call audio coming out of the speakers, which would otherwise be transcribed a second time as "Me".
final class MeetingMicrophoneSource: MeetingAudioSource {
    let speaker = MeetingSpeaker.me
    private var engine = AVAudioEngine()
    private var configurationObserver: NSObjectProtocol?
    private let deviceUID: String?

    init(deviceUID: String?) {
        self.deviceUID = deviceUID
    }

    /// Builds a fresh engine every time, so a restart also recovers from a wedged audio unit.
    func start(onSamples: @escaping ([Float]) -> Void) throws {
        let engine = AVAudioEngine()
        self.engine = engine
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
        do {
            try input.setVoiceProcessingEnabled(true)
        } catch {
            throw MeetingRecorderError.audioSetupFailed("microphone voice processing unavailable")
        }
        if #available(macOS 14.0, *) {
            input.voiceProcessingOtherAudioDuckingConfiguration = .init(enableAdvancedDucking: false, duckingLevel: .min)
        }
        // Voice processing is a duplex unit: without a rendered mono output path the engine fails to
        // initialize (-10875), and the input's own multichannel format yields silence.
        guard let format = AVAudioFormat(standardFormatWithSampleRate: input.outputFormat(forBus: 0).sampleRate, channels: 1),
              let converter = MeetingSampleConverter(inputFormat: format)
        else { throw MeetingRecorderError.audioSetupFailed("no microphone input") }
        engine.connect(engine.mainMixerNode, to: engine.outputNode, format: format)
        input.installTap(onBus: 0, bufferSize: 4096, format: format) { buffer, _ in
            let samples = converter.convert(buffer)
            if !samples.isEmpty { onSamples(samples) }
        }
        // Enabling voice processing reconfigures the device, which can stop the engine right after it starts.
        configurationObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { [weak engine] _ in
            guard let engine, !engine.isRunning else { return }
            try? engine.start()
        }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            stop()
            throw MeetingRecorderError.audioSetupFailed("microphone unavailable")
        }
    }

    func stop() {
        configurationObserver.map(NotificationCenter.default.removeObserver)
        configurationObserver = nil
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
