import SwiftUI

struct MeetingsView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var recorder: MeetingRecorder

    private var unavailableReason: String? {
        guard #available(macOS 14.2, *) else { return MeetingRecorderError.unsupportedSystem.errorDescription }
        return MeetingTranscriber.hasAPIKey(appState.transcriptionConfiguration) ? nil : MeetingRecorderError.missingAPIKey.errorDescription
    }

    var body: some View {
        MeetingsContent(
            screen: MeetingsScreen(
                phase: recorder.phase,
                startedAt: recorder.startedAt,
                level: recorder.level,
                liveSegments: recorder.liveSegments,
                meetings: recorder.meetings,
                toast: recorder.toast,
                errorMessage: recorder.errorMessage,
                micBlocked: recorder.micBlocked,
                unavailableReason: unavailableReason
            ),
            onRecord: { Task { await recorder.start() } },
            onStop: { Task { await recorder.stop() } },
            onCopy: recorder.copy,
            onDelete: recorder.delete
        )
    }
}
