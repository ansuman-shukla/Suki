import Foundation

extension MeetingRecorder {
    /// Uses the dictation transcription settings and microphone; system audio needs macOS 14.2.
    static func live(appState: AppState) -> MeetingRecorder {
        MeetingRecorder(
            makeTranscriber: { [weak appState] in
                guard let appState else { throw MeetingRecorderError.missingAPIKey }
                return try MeetingTranscriber.make(appState.transcriptionConfiguration)
            },
            makeSources: { [weak appState] in
                guard #available(macOS 14.2, *) else { throw MeetingRecorderError.unsupportedSystem }
                return [
                    MeetingMicrophoneSource(deviceUID: appState?.selectedMicrophoneID),
                    SystemAudioTapSource(),
                ]
            },
            callAppsUsingMicrophone: MeetingRecorder.callAppsUsingMicrophone
        )
    }

    /// Call apps holding the mic, for the call-ended auto-stop. Never logged or stored.
    nonisolated static func callAppsUsingMicrophone() -> Set<String> {
        guard #available(macOS 14.2, *) else { return [] }
        return MicUsageMonitor.callAppsUsingMicrophone()
    }
}
