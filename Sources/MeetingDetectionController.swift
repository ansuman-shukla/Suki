import Foundation

/// Polls which call apps use the microphone and offers a meeting recording once per call.
@MainActor
final class MeetingDetectionController {
    private var detector = MeetingCallDetector()
    private var timer: Timer?
    private let prompt = MeetingPromptPanel()
    private let isRecordingMeeting: () -> Bool
    private let onAccept: () -> Void
    private let pollInterval: TimeInterval = 2

    init(isRecordingMeeting: @escaping () -> Bool, onAccept: @escaping () -> Void) {
        self.isRecordingMeeting = isRecordingMeeting
        self.onAccept = onAccept
    }

    func start() {
        guard #available(macOS 14.2, *), timer == nil else { return }
        let timer = Timer(timeInterval: pollInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func tick() {
        guard #available(macOS 14.2, *), MeetingDetectionMode.load(from: .standard) == .notify else { return }
        let canPrompt = !isRecordingMeeting() && !prompt.isShown
        guard let app = detector.update(
            activeApps: MicUsageMonitor.callAppsUsingMicrophone(),
            now: Date(),
            canPrompt: canPrompt
        ) else { return }
        prompt.show(appName: app, onAccept: onAccept)
    }
}
