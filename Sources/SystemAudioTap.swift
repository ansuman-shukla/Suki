import AVFoundation
import CoreAudio

/// "Them": everything other apps play, captured with a Core Audio process tap.
/// The tap feeds a private aggregate device whose IOProc delivers the audio.
@available(macOS 14.2, *)
final class SystemAudioTapSource: MeetingAudioSource {
    let speaker = MeetingSpeaker.them
    private let queue = DispatchQueue(label: "Suki.SystemAudioTap", qos: .userInitiated)
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var ioProcID: AudioDeviceIOProcID?
    /// Batches tiny IO buffers into ~100 ms so the main thread isn't woken every few milliseconds.
    private var pending: [Float] = []
    private let batchSize = Int(MeetingTranscriptCore.sampleRate * MeetingTranscriptCore.levelWindowSeconds)

    func start(onSamples: @escaping ([Float]) -> Void) throws {
        do {
            try startTap(onSamples: onSamples)
        } catch {
            stop()
            throw error
        }
    }

    func stop() {
        if aggregateID != kAudioObjectUnknown {
            if let ioProcID {
                AudioDeviceStop(aggregateID, ioProcID)
                AudioDeviceDestroyIOProcID(aggregateID, ioProcID)
            }
            AudioHardwareDestroyAggregateDevice(aggregateID)
        }
        if tapID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tapID)
        }
        ioProcID = nil
        aggregateID = AudioObjectID(kAudioObjectUnknown)
        tapID = AudioObjectID(kAudioObjectUnknown)
        queue.sync { pending.removeAll() }
    }

    private func startTap(onSamples: @escaping ([Float]) -> Void) throws {
        let description = CATapDescription(stereoGlobalTapButExcludeProcesses: Self.ownProcessObject().map { [$0] } ?? [])
        description.uuid = UUID()
        description.name = "\(AppName.displayName) Meeting"
        description.isPrivate = true
        try check(AudioHardwareCreateProcessTap(description, &tapID), "system audio")

        var streamDescription = try tapFormat()
        guard let format = AVAudioFormat(streamDescription: &streamDescription),
              let converter = MeetingSampleConverter(inputFormat: format)
        else { throw MeetingRecorderError.audioSetupFailed("unsupported system audio format") }

        let aggregate: [String: Any] = [
            kAudioAggregateDeviceNameKey: "\(AppName.displayName) Meeting",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceTapListKey: [[
                kAudioSubTapUIDKey: description.uuid.uuidString,
                kAudioSubTapDriftCompensationKey: true,
            ]],
        ]
        try check(AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &aggregateID), "system audio device")

        let batchSize = batchSize
        try check(AudioDeviceCreateIOProcIDWithBlock(&ioProcID, aggregateID, queue) { [weak self] _, inputData, _, _, _ in
            guard let self,
                  let buffer = AVAudioPCMBuffer(pcmFormat: format, bufferListNoCopy: inputData, deallocator: nil)
            else { return }
            self.pending += converter.convert(buffer)
            guard self.pending.count >= batchSize else { return }
            let batch = self.pending
            self.pending.removeAll(keepingCapacity: true)
            onSamples(batch)
        }, "system audio callback")
        try check(AudioDeviceStart(aggregateID, ioProcID), "system audio capture")
    }

    private func tapFormat() throws -> AudioStreamBasicDescription {
        var format = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyFormat,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        try check(AudioObjectGetPropertyData(tapID, &address, 0, nil, &size, &format), "system audio format")
        return format
    }

    /// Suki's own Core Audio process object, so its sounds stay out of "Them".
    private static func ownProcessObject() -> AudioObjectID? {
        var pid = getpid()
        var processObject = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyTranslatePIDToProcessObject,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            UInt32(MemoryLayout<pid_t>.size),
            &pid,
            &size,
            &processObject
        )
        return status == noErr && processObject != kAudioObjectUnknown ? processObject : nil
    }

    private func check(_ status: OSStatus, _ step: String) throws {
        guard status == noErr else {
            throw MeetingRecorderError.audioSetupFailed("\(step) unavailable (\(status))")
        }
    }
}
