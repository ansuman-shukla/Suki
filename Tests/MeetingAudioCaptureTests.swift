import AVFoundation

enum MeetingAudioCaptureTests {
    static func run() {
        stereo48kBecomesMono16k()
        eitherChannelIsHeardAfterDownmix()
        mono16kPassesThrough()
        emptyOrInvalidInputYieldsNothing()
    }

    private static func buffer(rate: Double, channels: AVAudioChannelCount, seconds: Double, amplitudes: [Float]) -> AVAudioPCMBuffer {
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: rate, channels: channels, interleaved: false)!
        let frames = AVAudioFrameCount(rate * seconds)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        for channel in 0..<Int(channels) {
            for frame in 0..<Int(frames) {
                buffer.floatChannelData![channel][frame] = amplitudes[channel] * sin(2 * .pi * 440 * Float(frame) / Float(rate))
            }
        }
        return buffer
    }

    private static func convertInSlices(_ source: AVAudioPCMBuffer, slices: Int) -> [Float] {
        let converter = MeetingSampleConverter(inputFormat: source.format)!
        let sliceFrames = Int(source.frameLength) / slices
        var output: [Float] = []
        for slice in 0..<slices {
            let part = AVAudioPCMBuffer(pcmFormat: source.format, frameCapacity: AVAudioFrameCount(sliceFrames))!
            part.frameLength = AVAudioFrameCount(sliceFrames)
            for channel in 0..<Int(source.format.channelCount) {
                for frame in 0..<sliceFrames {
                    part.floatChannelData![channel][frame] = source.floatChannelData![channel][slice * sliceFrames + frame]
                }
            }
            output += converter.convert(part)
        }
        return output
    }

    private static func stereo48kBecomesMono16k() {
        let samples = convertInSlices(buffer(rate: 48_000, channels: 2, seconds: 1, amplitudes: [0.5, 0.5]), slices: 10)
        // The resampler holds back a few hundred frames of latency while streaming.
        TestSupport.expect((15_500...16_064).contains(samples.count), "One second at 48 kHz yields about 16k samples, got \(samples.count)")
        let rms = Double(MeetingTranscriptCore.rms(samples.dropFirst(200)))
        TestSupport.expectApproximatelyEqual(rms, 0.5 / 2.0.squareRoot(), accuracy: 0.05)
    }

    private static func eitherChannelIsHeardAfterDownmix() {
        for amplitudes: [Float] in [[0.5, 0], [0, 0.5]] {
            let samples = convertInSlices(buffer(rate: 48_000, channels: 2, seconds: 0.5, amplitudes: amplitudes), slices: 5)
            TestSupport.expect(MeetingTranscriptCore.rms(samples) > 0.1, "Audio on channel \(amplitudes) survives the downmix")
        }
    }

    private static func mono16kPassesThrough() {
        let source = buffer(rate: 16_000, channels: 1, seconds: 0.25, amplitudes: [0.3])
        let samples = MeetingSampleConverter(inputFormat: source.format)!.convert(source)
        TestSupport.expectEqual(samples.count, 4_000)
        TestSupport.expectApproximatelyEqual(Double(samples[100]), Double(source.floatChannelData![0][100]), accuracy: 0.001)
    }

    private static func emptyOrInvalidInputYieldsNothing() {
        let source = buffer(rate: 44_100, channels: 1, seconds: 0.1, amplitudes: [0.3])
        source.frameLength = 0
        TestSupport.expect(MeetingSampleConverter(inputFormat: source.format)!.convert(source).isEmpty, "Empty buffer converts to nothing")
        let invalid = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 0, channels: 1, interleaved: false)
        TestSupport.expect(invalid.flatMap(MeetingSampleConverter.init(inputFormat:)) == nil, "A zero-rate input has no converter")
    }
}
