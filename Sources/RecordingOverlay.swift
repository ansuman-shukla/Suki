import SwiftUI
import AppKit

// MARK: - State

final class RecordingOverlayState: ObservableObject {
    @Published var phase: OverlayPhase = .recording
    @Published var recordingStartedAt: ContinuousClock.Instant?
    @Published var showsRecordingTimer = RecordingTimerPreference.defaultEnabled
    @Published var audioLevel: Float = 0.0
    @Published var recordingTriggerMode: RecordingTriggerMode = .hold
    @Published var isCommandMode = false
    @Published var updateVersion: String = ""
    @Published var errorMessage: String?
    @Published var toastID: UUID?
}

final class LiveTranscriptPreviewState: ObservableObject {
    @Published var text = ""
}

enum OverlayPhase {
    case initializing
    case recording
    case transcribing
    case feedback
    case updateAvailable
}

// MARK: - NSScreen Helpers

extension NSScreen {
    /// CoreGraphics display identifier for this screen, or nil if the
    /// device description is missing the key (vanishingly rare). Stable
    /// across screen-arrangement changes for as long as the display is
    /// connected, which is what the overlay picker stores in UserDefaults.
    var displayID: CGDirectDisplayID? {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }
}

// MARK: - Panel Helpers

private func makeOverlayPanel(width: CGFloat, height: CGFloat) -> NSPanel {
    let panel = NSPanel(
        contentRect: NSRect(x: 0, y: 0, width: width, height: height),
        styleMask: [.borderless, .nonactivatingPanel],
        backing: .buffered,
        defer: false
    )
    panel.backgroundColor = .clear
    panel.isOpaque = false
    panel.hasShadow = true
    panel.level = .screenSaver
    panel.ignoresMouseEvents = true
    panel.collectionBehavior = [.canJoinAllSpaces]
    panel.isReleasedWhenClosed = false
    panel.hidesOnDeactivate = false
    return panel
}

private func makeNotchContent<V: View>(
    width: CGFloat,
    height: CGFloat,
    cornerRadius: CGFloat,
    rootView: V
) -> NSView {
    let shaped = rootView
        .frame(width: width, height: height)
        .background(Color.black)
        .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: cornerRadius, bottomTrailingRadius: cornerRadius))

    let hosting = NSHostingView(rootView: shaped)
    hosting.frame = NSRect(x: 0, y: 0, width: width, height: height)
    hosting.autoresizingMask = [.width, .height]
    return hosting
}

// MARK: - Manager

final class RecordingOverlayManager {
    private var overlayWindow: NSPanel?
    private let overlayState = RecordingOverlayState()
    private var lockedOverlayWidth: CGFloat?
    private var previewWindow: NSPanel?
    private let previewState = LiveTranscriptPreviewState()

    var onStopButtonPressed: (() -> Void)?
    var onUpdateOverlayPressed: (() -> Void)?

    /// The screen the overlay should drop down on. The user picks one of
    /// three modes in Settings, stored in UserDefaults under
    /// `overlay_display_id`:
    ///
    /// - `0` (default) — Active window: follows focus across monitors via
    ///   NSScreen.main. Default for backward compatibility — the original
    ///   behavior on a single-display setup is unchanged.
    /// - `-1` — Primary display: always NSScreen.screens.first (the display
    ///   designated as primary in System Settings → Displays).
    /// - any positive integer — specific NSScreen displayID. Falls back to
    ///   primary if that display is unplugged.
    private var targetScreen: NSScreen? {
        let savedID = UserDefaults.standard.integer(forKey: "overlay_display_id")
        switch savedID {
        case 0:
            return NSScreen.main ?? NSScreen.screens.first
        case -1:
            return NSScreen.screens.first ?? NSScreen.main
        default:
            if let match = NSScreen.screens.first(where: { Int($0.displayID ?? 0) == savedID }) {
                return match
            }
            return NSScreen.screens.first ?? NSScreen.main
        }
    }

    private var screenHasNotch: Bool {
        guard let screen = targetScreen else { return false }
        return screen.safeAreaInsets.top > 0
    }

    private var notchWidth: CGFloat {
        guard let screen = targetScreen, screenHasNotch else { return 0 }
        guard let leftArea = screen.auxiliaryTopLeftArea,
              let rightArea = screen.auxiliaryTopRightArea else { return 0 }
        return screen.frame.width - leftArea.width - rightArea.width
    }

    private var notchOverlap: CGFloat {
        guard let screen = targetScreen else { return 0 }
        return screen.frame.maxY - screen.visibleFrame.maxY
    }

    private var overlayAcceptsMouseEvents: Bool {
        (overlayState.phase == .recording && overlayState.recordingTriggerMode == .toggle)
            || overlayState.phase == .updateAvailable
    }

    func showInitializing(mode: RecordingTriggerMode = .hold, isCommandMode: Bool = false) {
        DispatchQueue.main.async {
            self.hideLiveTranscriptPreviewNow()
            self.lockedOverlayWidth = nil
            self.overlayState.recordingTriggerMode = mode
            self.overlayState.isCommandMode = isCommandMode
            self.overlayState.recordingStartedAt = nil
            self.overlayState.phase = .initializing
            self.overlayState.audioLevel = 0
            self.showOverlayPanel(animatedResize: false)
        }
    }

    func showRecording(
        mode: RecordingTriggerMode = .hold,
        isCommandMode: Bool = false,
        startedAt: ContinuousClock.Instant = .now,
        showsRecordingTimer: Bool
    ) {
        DispatchQueue.main.async {
            self.lockedOverlayWidth = nil
            self.overlayState.recordingTriggerMode = mode
            self.overlayState.isCommandMode = isCommandMode
            self.beginRecordingTimer(startedAt: startedAt, showsRecordingTimer: showsRecordingTimer)
            self.overlayState.phase = .recording
            self.overlayState.audioLevel = 0
            self.showOverlayPanel(animatedResize: true)
        }
    }

    func transitionToRecording(
        mode: RecordingTriggerMode = .hold,
        isCommandMode: Bool = false,
        startedAt: ContinuousClock.Instant = .now,
        showsRecordingTimer: Bool
    ) {
        DispatchQueue.main.async {
            self.lockedOverlayWidth = nil
            self.overlayState.recordingTriggerMode = mode
            self.overlayState.isCommandMode = isCommandMode
            self.beginRecordingTimer(startedAt: startedAt, showsRecordingTimer: showsRecordingTimer)
            self.overlayState.phase = .recording
            self.updateOverlayLayout(animated: true)
        }
    }

    private func beginRecordingTimer(startedAt: ContinuousClock.Instant, showsRecordingTimer: Bool) {
        overlayState.showsRecordingTimer = showsRecordingTimer
        overlayState.recordingStartedAt = startedAt
    }

    func setRecordingTriggerMode(_ mode: RecordingTriggerMode, animated: Bool) {
        DispatchQueue.main.async {
            self.overlayState.recordingTriggerMode = mode
            self.updateOverlayLayout(animated: animated)
        }
    }

    func updateAudioLevel(_ level: Float) {
        DispatchQueue.main.async {
            self.overlayState.audioLevel = level
        }
    }

    func showTranscribing() {
        DispatchQueue.main.async {
            self.setTranscribingPhase()
        }
    }

    func showFailureIndicator() {
        DispatchQueue.main.async {
            self.showFeedbackPanel()
        }
    }

    /// Maximum length of an in-pill error message. Anything longer is
    /// truncated with an ellipsis to keep the pill from stretching across
    /// the menu bar; the full text remains available in `os_log` for
    /// forensic review.
    private static let maxToastMessageLength = 90

    /// Surface a transient error in the menu-bar pill. The pill resizes to
    /// fit the message (subject to the truncation cap), holds for a few
    /// seconds, then dismisses. Intended for non-fatal user-facing errors
    /// that previously only landed in `os_log` — rate limits, network
    /// failures, permission gaps, etc.
    func showError(_ message: String) {
        let truncated: String = {
            if message.count <= Self.maxToastMessageLength { return message }
            let cutoff = message.index(message.startIndex, offsetBy: Self.maxToastMessageLength - 1)
            return String(message[..<cutoff]) + "…"
        }()
        DispatchQueue.main.async { [self] in
            self.hideLiveTranscriptPreviewNow()
            let toastID = UUID()
            self.overlayState.errorMessage = truncated
            self.overlayState.toastID = toastID
            self.lockedOverlayWidth = nil
            self.overlayState.phase = .feedback
            self.showOverlayPanel(animatedResize: true)
            DispatchQueue.main.asyncAfter(deadline: .now() + 6.0) { [weak self] in
                guard let self else { return }
                guard self.overlayState.phase == .feedback,
                      self.overlayState.errorMessage == truncated,
                      self.overlayState.toastID == toastID else {
                    return
                }
                self.overlayState.errorMessage = nil
                self.overlayState.toastID = nil
                self.dismissAll()
            }
        }
    }

    func showUpdateAvailable(version: String) {
        DispatchQueue.main.async {
            self.lockedOverlayWidth = nil
            self.overlayState.isCommandMode = false
            self.overlayState.updateVersion = version
            self.overlayState.phase = .updateAvailable
            self.showOverlayPanel(animatedResize: true)
        }
    }

    func dismiss() {
        DispatchQueue.main.async {
            self.dismissAll()
        }
    }

    /// Caption under the menu bar with the tail of the live transcript, kept
    /// separate from the notch overlay so its tight layout stays untouched.
    func showLiveTranscriptPreview(_ text: String) {
        DispatchQueue.main.async {
            guard !text.isEmpty, let frame = self.previewFrame else { return }
            self.previewState.text = text
            if let panel = self.previewWindow {
                panel.setFrame(frame, display: true)
                return
            }
            let panel = makeOverlayPanel(width: frame.width, height: frame.height)
            let hosting = NSHostingView(rootView: LiveTranscriptPreviewView(state: self.previewState))
            hosting.frame = NSRect(origin: .zero, size: frame.size)
            hosting.autoresizingMask = [.width, .height]
            panel.contentView = hosting
            panel.setFrame(frame, display: true)
            panel.orderFrontRegardless()
            self.previewWindow = panel
        }
    }

    func hideLiveTranscriptPreview() {
        DispatchQueue.main.async {
            self.hideLiveTranscriptPreviewNow()
        }
    }

    private func hideLiveTranscriptPreviewNow() {
        previewState.text = ""
        guard let panel = previewWindow else { return }
        panel.orderOut(nil)
        panel.contentView = nil
        panel.close()
        previewWindow = nil
    }

    private var previewFrame: NSRect? {
        guard let screen = targetScreen else { return nil }
        let width = min(560, screen.frame.width * 0.6)
        let height: CGFloat = 54
        // Clear the drop-down pill, which hangs up to 38pt below the menu bar.
        let top = screen.visibleFrame.maxY - 44
        return NSRect(x: screen.frame.midX - width / 2, y: top - height, width: width, height: height)
    }

    private func showOverlayPanel(animatedResize: Bool) {
        let frame = overlayFrame

        if let panel = overlayWindow {
            panel.ignoresMouseEvents = !overlayAcceptsMouseEvents
            panel.contentView = makeOverlayContent(frame: frame)
            resize(panel: panel, to: frame, animated: animatedResize)
            panel.alphaValue = 1
            panel.orderFrontRegardless()
            return
        }

        let panel = makeOverlayPanel(width: frame.width, height: frame.height)
        panel.hasShadow = false
        panel.ignoresMouseEvents = !overlayAcceptsMouseEvents
        panel.contentView = makeOverlayContent(frame: frame)

        guard let screen = targetScreen else { return }

        let hiddenFrame = NSRect(x: frame.origin.x, y: screen.frame.maxY, width: frame.width, height: frame.height)
        panel.setFrame(hiddenFrame, display: true)
        panel.alphaValue = 1
        panel.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.34, 1.56, 0.64, 1.0)
            panel.animator().setFrame(frame, display: true)
        }

        overlayWindow = panel
    }

    private func updateOverlayLayout(animated: Bool) {
        guard let panel = overlayWindow else { return }
        let frame = overlayFrame
        panel.ignoresMouseEvents = !overlayAcceptsMouseEvents
        panel.contentView = makeOverlayContent(frame: frame)
        resize(panel: panel, to: frame, animated: animated)
    }

    private func setTranscribingPhase() {
        lockedOverlayWidth = overlayWindow?.frame.width ?? overlayWidth
        overlayState.phase = .transcribing
        showOverlayPanel(animatedResize: true)
    }

    private func makeOverlayContent(frame: NSRect) -> NSView {
        if useWingedLayout {
            // Winged layout: notch x-range stays solid black so the cutout masks it.
            let rootView = WingedRecordingView(
                state: overlayState,
                leftWingWidth: activeWingWidth,
                notchWidth: notchWidth,
                rightWingWidth: activeWingWidth,
                height: frame.height,
                onStopButtonPressed: { [weak self] in
                    self?.onStopButtonPressed?()
                }
            )
            return makeNotchContent(
                width: frame.width,
                height: frame.height,
                cornerRadius: 14,
                rootView: AnyView(rootView)
            )
        }

        return makeNotchContent(
            width: frame.width,
            height: frame.height,
            cornerRadius: screenHasNotch ? 18 : 12,
            rootView: AnyView(
                RecordingOverlayView(
                    state: overlayState,
                    onStopButtonPressed: { [weak self] in
                        self?.onStopButtonPressed?()
                    },
                    onUpdateOverlayPressed: { [weak self] in
                        self?.onUpdateOverlayPressed?()
                    }
                )
                .padding(.top, screenHasNotch ? notchOverlap : 0)
            )
        )
    }

    private func resize(panel: NSPanel, to frame: NSRect, animated: Bool) {
        guard animated else {
            panel.setFrame(frame, display: true)
            return
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.22
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().setFrame(frame, display: true)
        }
    }

    /// True iff the overlay renders as wings flanking the notch (notched display
    /// + use_compact_overlay on). updateAvailable and error toasts still use
    /// the drop-down pill.
    private var useWingedLayout: Bool {
        guard screenHasNotch else { return false }
        let useCompact = (UserDefaults.standard.object(forKey: "use_compact_overlay") as? Bool) ?? true
        guard useCompact else { return false }
        switch overlayState.phase {
        case .recording, .initializing, .transcribing:
            return true
        case .feedback:
            return overlayState.errorMessage?.isEmpty ?? true
        case .updateAvailable:
            return false
        }
    }

    /// Equal wings keep the overlay balanced around the camera cutout.
    /// Recording needs just enough room for the timer on the left.
    private var activeWingWidth: CGFloat {
        overlayState.phase == .recording && overlayState.showsRecordingTimer ? 48 : 36
    }

    private var overlayFrame: NSRect {
        guard let screen = targetScreen else { return .zero }

        if useWingedLayout {
            // Anchor to the screen's auxiliary-area boundaries of the notch;
            // panel height matches the menu-bar overlap so nothing protrudes below.
            let nWidth = notchWidth
            let nLeftX = screen.auxiliaryTopLeftArea?.maxX
                ?? (screen.frame.midX - nWidth / 2)
            let leftWing = activeWingWidth
            let rightWing = activeWingWidth
            let panelHeight = notchOverlap
            let panelWidth = leftWing + nWidth + rightWing
            let panelX = nLeftX - leftWing
            let panelY = screen.frame.maxY - panelHeight
            return NSRect(x: panelX, y: panelY, width: panelWidth, height: panelHeight)
        }

        let width = overlayWidth
        let useCompact = (UserDefaults.standard.object(forKey: "use_compact_overlay") as? Bool) ?? true
        let forceDropDownPill = overlayState.phase == .feedback
            && !(overlayState.errorMessage?.isEmpty ?? true)
        // Compact mode: overlay sits flush with the menu bar on every display.
        // notchOverlap equals the menu-bar height on non-notched screens too,
        // so zero protrusion is universal — not notch-only. The legacy
        // 38pt drop-down pill remains available when use_compact_overlay
        // is explicitly toggled off. Error toasts also force the drop-down
        // height so messages stay readable even when compact overlay is enabled.
        let height: CGFloat = (useCompact && !forceDropDownPill)
            ? notchOverlap
            : 38 + (screenHasNotch ? notchOverlap : 0)
        let x = screen.frame.midX - width / 2
        let y = screen.frame.maxY - height
        return NSRect(x: x, y: y, width: width, height: height)
    }

    private var overlayWidth: CGFloat {
        if let lockedOverlayWidth, overlayState.phase == .transcribing {
            return lockedOverlayWidth
        }

        if overlayState.phase == .feedback {
            // Error toasts size to the message length so short messages do
            // not get the same wide pill as long ones. ~6.8pt per character
            // plus 60pt of icon and padding chrome, clamped to 180-420pt so
            // very short messages stay readable and very long ones do not
            // stretch the pill across the menu bar. Bare failure-X marker
            // (no message) keeps the original 92pt.
            let feedbackWidth: CGFloat = {
                guard let msg = overlayState.errorMessage, !msg.isEmpty else {
                    return 92
                }
                let estimated = CGFloat(msg.count) * 6.8 + 60
                return min(420, max(180, estimated))
            }()
            guard screenHasNotch else { return feedbackWidth }
            return max(notchWidth, feedbackWidth)
        }

        if overlayState.phase == .updateAvailable {
            let updateWidth: CGFloat = 190
            guard screenHasNotch else { return updateWidth }
            return max(notchWidth, updateWidth)
        }

        let commandModeWidth: CGFloat = 180
        let toggleWidth: CGFloat = 150
        let defaultWidth: CGFloat = 92
        let baseWidth: CGFloat

        if overlayState.isCommandMode {
            baseWidth = commandModeWidth
        } else if overlayState.phase == .recording && overlayState.recordingTriggerMode == .toggle {
            baseWidth = toggleWidth
        } else {
            baseWidth = defaultWidth
        }

        // Reserve separate leading, center, and trailing slots while recording.
        let width = overlayState.phase == .recording && overlayState.showsRecordingTimer
            ? max(baseWidth, overlayState.isCommandMode ? 224 : 180)
            : baseWidth
        guard screenHasNotch else { return width }
        return max(notchWidth, width)
    }

    private func showFeedbackPanel() {
        lockedOverlayWidth = nil
        overlayState.phase = .feedback
        showOverlayPanel(animatedResize: true)
    }

    private func dismissAll() {
        hideLiveTranscriptPreviewNow()
        lockedOverlayWidth = nil
        overlayState.recordingStartedAt = nil
        overlayState.isCommandMode = false
        overlayState.updateVersion = ""
        if let panel = overlayWindow {
            panel.orderOut(nil)
            // orderOut alone leaves the panel retained in NSApp.windows with its
            // SwiftUI hierarchy mounted — repeatForever animations keep flushing
            // Core Animation forever. Unmount and close so the panel deallocates.
            panel.contentView = nil
            panel.close()
            overlayWindow = nil
        }
    }
}

// MARK: - Live Transcript Preview

struct LiveTranscriptPreviewView: View {
    @ObservedObject var state: LiveTranscriptPreviewState

    var body: some View {
        Text(state.text)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.white.opacity(0.95))
            .lineLimit(2)
            .truncationMode(.head)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.black.opacity(0.85)))
            .accessibilityLabel("Live transcript")
    }
}

// MARK: - Winged Recording View

/// Wing layout: timer (or waveform) left, stop button right, black notch in the middle
/// (the camera cutout masks those pixels).
struct WingedRecordingView: View {
    @ObservedObject var state: RecordingOverlayState
    let leftWingWidth: CGFloat
    let notchWidth: CGFloat
    let rightWingWidth: CGFloat
    let height: CGFloat
    let onStopButtonPressed: () -> Void

    private var showsLiveRecordingContent: Bool {
        state.phase == .recording
    }

    private var showsStopButton: Bool {
        showsLiveRecordingContent && state.recordingTriggerMode == .toggle
    }

    var body: some View {
        wingsHStack
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(.spring(response: 0.28, dampingFraction: 1.0), value: state.phase)
    }

    private var wingsHStack: some View {
        HStack(spacing: 0) {
            // Left wing — empty during feedback so the right-wing X reads as the sole signal.
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                Group {
                    if state.phase == .feedback {
                        Color.clear
                    } else if state.phase == .initializing {
                        InitializingDotsView()
                            .transition(.opacity)
                    } else if showsLiveRecordingContent {
                        VStack(spacing: 1) {
                            if state.isCommandMode {
                                Image(systemName: "pencil")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(.white.opacity(0.92))
                                    .transition(.opacity)
                            }
                            if state.showsRecordingTimer, let start = state.recordingStartedAt {
                                RecordingElapsedTimeView(start: start)
                            } else {
                                WaveformView(
                                    audioLevel: state.audioLevel,
                                    showsActivityPulse: true,
                                    metrics: .compact
                                )
                            }
                        }
                        .transition(.opacity)
                    } else {
                        CompactProcessingIndicatorView()
                            .transition(.opacity)
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(width: leftWingWidth, height: height)

            // Notch spacer — solid black; camera cutout hides it.
            Color.black
                .frame(width: notchWidth, height: height)

            // Right wing — stop button or failure X, horizontally centered.
            HStack {
                Spacer(minLength: 0)
                Group {
                    if state.phase == .feedback {
                        Image(systemName: "xmark")
                            .font(.system(size: 7, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 14, height: 14)
                            .background(Circle().fill(Color.red.opacity(0.92)))
                            .transition(.opacity)
                    } else if showsStopButton {
                        Button(action: onStopButtonPressed) {
                            Image(systemName: "stop.fill")
                                .font(.system(size: 7, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 14, height: 14)
                                .background(Circle().fill(Color.red.opacity(0.92)))
                        }
                        .buttonStyle(.plain)
                        .transition(.opacity)
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(width: rightWingWidth, height: height)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.spring(response: 0.28, dampingFraction: 1.0), value: state.phase)
    }
}

// MARK: - Waveform Views

/// Bar sizing for one overlay slot; the lens shape and ripple come from `WaveformLayout`.
struct WaveformMetrics {
    let barWidth: CGFloat
    let spacing: CGFloat
    let minHeight: CGFloat
    let maxHeight: CGFloat
    let frameHeight: CGFloat

    static let regular = WaveformMetrics(barWidth: 3, spacing: 2, minHeight: 3, maxHeight: 22, frameHeight: 24)
    /// Fits ten bars inside the 36pt notch wing.
    static let compact = WaveformMetrics(barWidth: 1.5, spacing: 1.5, minHeight: 2, maxHeight: 14, frameHeight: 18)
}

struct WaveformView: View {
    let audioLevel: Float
    var showsActivityPulse = false
    var metrics = WaveformMetrics.regular
    var layout = WaveformLayout.dictation

    var body: some View {
        Group {
            if showsActivityPulse {
                TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: false)) { context in
                    bars(time: context.date.timeIntervalSinceReferenceDate)
                }
            } else {
                bars(time: nil)
            }
        }
        .frame(height: metrics.frameHeight)
    }

    private func bars(time: TimeInterval?) -> some View {
        HStack(spacing: metrics.spacing) {
            ForEach(0..<layout.barCount, id: \.self) { index in
                Capsule()
                    .fill(.white)
                    .frame(width: metrics.barWidth, height: height(ofBar: index, time: time))
                    .animation(.suki.delay(layout.rippleDelay(ofBar: index)), value: audioLevel)
            }
        }
    }

    private func height(ofBar index: Int, time: TimeInterval?) -> CGFloat {
        let level = Double(audioLevel)
        let animated = time.map { layout.breathingLevel(ofBar: index, level: level, time: $0) } ?? level
        return layout.barHeight(ofBar: index, level: animated, minHeight: metrics.minHeight, maxHeight: metrics.maxHeight)
    }
}

/// The recording bars at rest with a soft highlight sweeping across them.
struct ProcessingWaveformView: View {
    var metrics = WaveformMetrics.regular
    var layout = WaveformLayout.dictation

    private static let restingLevel = 0.18
    private static let highlightLift = 0.22

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: false)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: metrics.spacing) {
                ForEach(0..<layout.barCount, id: \.self) { index in
                    let highlight = layout.shimmer(ofBar: index, time: time)
                    Capsule()
                        .fill(.white)
                        .frame(width: metrics.barWidth, height: layout.barHeight(
                            ofBar: index,
                            level: Self.restingLevel + highlight * Self.highlightLift,
                            minHeight: metrics.minHeight,
                            maxHeight: metrics.maxHeight
                        ))
                        .opacity(0.4 + highlight * 0.55)
                }
            }
            .frame(height: metrics.frameHeight)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ProcessingIndicatorView: View {
    @State private var showsExtendedSpinner = false
    @State private var rotation: Double = 0

    var body: some View {
        ZStack {
            if showsExtendedSpinner {
                Circle()
                    .trim(from: 0.1, to: 0.9)
                    .stroke(Color.white, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .frame(width: 16, height: 16)
                    .rotationEffect(.degrees(rotation))
                    .frame(height: 20)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(.opacity)
                    .onAppear {
                        rotation = 0
                        withAnimation(.linear(duration: 0.8).repeatForever(autoreverses: false)) {
                            rotation = 360
                        }
                    }
            } else {
                ProcessingWaveformView()
                    .transition(.opacity)
            }
        }
        .task {
            showsExtendedSpinner = false
            do {
                try await Task.sleep(nanoseconds: 1_000_000_000)
                guard !Task.isCancelled else { return }
                withAnimation(.easeInOut(duration: 0.18)) {
                    showsExtendedSpinner = true
                }
            } catch {}
        }
    }
}

/// Same hybrid waveform-then-spinner as `ProcessingIndicatorView`, sized to
/// fit the 18pt winged menu-bar overlay. Uses tighter pills and a smaller
/// spinner so the indicator stays inside the wing without the jolt to
/// oversized capsules that the full-size indicator produced.
struct CompactProcessingIndicatorView: View {
    @State private var showsExtendedSpinner = false
    @State private var rotation: Double = 0

    var body: some View {
        ZStack {
            if showsExtendedSpinner {
                Circle()
                    .trim(from: 0.1, to: 0.9)
                    .stroke(Color.white, style: StrokeStyle(lineWidth: 2.0, lineCap: .round))
                    .frame(width: 12, height: 12)
                    .rotationEffect(.degrees(rotation))
                    .frame(height: 18)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(.opacity)
                    .onAppear {
                        rotation = 0
                        withAnimation(.linear(duration: 0.8).repeatForever(autoreverses: false)) {
                            rotation = 360
                        }
                    }
            } else {
                ProcessingWaveformView(metrics: .compact)
                    .transition(.opacity)
            }
        }
        .task {
            showsExtendedSpinner = false
            do {
                try await Task.sleep(nanoseconds: 1_000_000_000)
                guard !Task.isCancelled else { return }
                withAnimation(.easeInOut(duration: 0.18)) {
                    showsExtendedSpinner = true
                }
            } catch {}
        }
    }
}

struct InitializingDotsView: View {
    @State private var activeDot = 0
    @State private var timer: Timer?

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(.white.opacity(activeDot == index ? 0.9 : 0.25))
                    .frame(width: 4.5, height: 4.5)
                    .animation(.easeInOut(duration: 0.4), value: activeDot)
            }
        }
        .onAppear {
            timer?.invalidate()
            timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
                DispatchQueue.main.async {
                    activeDot = (activeDot + 1) % 3
                }
            }
        }
        .onDisappear {
            timer?.invalidate()
            timer = nil
        }
    }
}

struct RecordingOverlayView: View {
    @ObservedObject var state: RecordingOverlayState
    let onStopButtonPressed: () -> Void
    let onUpdateOverlayPressed: () -> Void

    private var leadingAccessoryWidth: CGFloat {
        guard showsLiveRecordingContent && state.showsRecordingTimer else { return 24 }
        return state.isCommandMode ? 72 : 48
    }
    private let trailingAccessoryWidth: CGFloat = 32

    private var showsLiveRecordingContent: Bool {
        state.phase == .recording
    }

    private var showsStopButton: Bool {
        showsLiveRecordingContent && state.recordingTriggerMode == .toggle
    }

    var body: some View {
        Group {
            if state.phase == .feedback, let message = state.errorMessage {
                ErrorOverlayView(message: message)
            } else if state.phase == .feedback {
                FailureIndicatorView()
            } else if state.phase == .updateAvailable {
                UpdateAvailableOverlayView(onPress: onUpdateOverlayPressed)
            } else {
                ZStack {
                    Group {
                        if state.phase == .initializing {
                            InitializingDotsView()
                                .transition(.opacity)
                        } else if showsLiveRecordingContent {
                            if state.showsRecordingTimer, let start = state.recordingStartedAt {
                                RecordingElapsedTimeView(start: start)
                                    .transition(.opacity)
                            } else {
                                WaveformView(audioLevel: state.audioLevel, showsActivityPulse: true)
                                    .transition(.opacity)
                            }
                        } else {
                            ProcessingIndicatorView()
                                .transition(.opacity)
                        }
                    }

                    HStack {
                        Group {
                            if showsLiveRecordingContent && state.showsRecordingTimer {
                                HStack(spacing: 6) {
                                    if state.isCommandMode {
                                        CommandModeIndicator()
                                    }
                                    WaveformView(
                                        audioLevel: state.audioLevel,
                                        showsActivityPulse: true
                                    )
                                }
                                .transition(.opacity)
                            } else if state.isCommandMode {
                                CommandModeIndicator()
                                    .transition(.opacity)
                            }
                        }
                        .frame(width: leadingAccessoryWidth, alignment: .center)
                        .frame(maxHeight: .infinity, alignment: .center)

                        Spacer(minLength: 0)

                        Group {
                            if showsStopButton {
                                Button(action: onStopButtonPressed) {
                                    Image(systemName: "stop.fill")
                                        .font(.system(size: 7, weight: .bold))
                                        .foregroundStyle(.white)
                                        .frame(width: 14, height: 14)
                                        .background(Circle().fill(Color.red.opacity(0.92)))
                                }
                                .buttonStyle(.plain)
                                .transition(.move(edge: .trailing).combined(with: .opacity))
                            }
                        }
                        .frame(width: trailingAccessoryWidth, alignment: .trailing)
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.spring(response: 0.28, dampingFraction: 1.0), value: state.phase)
        .animation(.spring(response: 0.28, dampingFraction: 1.0), value: state.recordingTriggerMode)
        .animation(.spring(response: 0.28, dampingFraction: 1.0), value: state.isCommandMode)
    }
}

/// The manager owns the start instant so rebuilding the overlay or switching
/// from hold to toggle mode cannot reset the elapsed time. A monotonic clock
/// also keeps system clock adjustments from changing the displayed duration.
private struct RecordingElapsedTimeView: View {
    let start: ContinuousClock.Instant

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            let seconds = max(0, start.duration(to: .now).components.seconds)
            Text(String(format: "%lld:%02lld", seconds / 60, seconds % 60))
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.9))
                .fixedSize()
                .frame(minWidth: 40)
                .accessibilityLabel("Recording duration")
                .accessibilityValue("\(seconds / 60) minutes, \(seconds % 60) seconds")
        }
    }
}

// MARK: - Transcribing Indicator

struct CommandModeIndicator: View {
    var body: some View {
        Image(systemName: "pencil")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white.opacity(0.92))
            .frame(width: 16, height: 16, alignment: .center)
    }
}

struct FailureIndicatorView: View {
    var body: some View {
        Image(systemName: "xmark")
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 20, height: 20)
            .background(Circle().fill(Color.red.opacity(0.92)))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// In-pill error toast. Red exclamation icon plus the message text,
/// rendered inside the standard menu-bar pill. Sized by the manager's
/// `overlayWidth` based on message length.
struct ErrorOverlayView: View {
    let message: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Color.red.opacity(0.92))
            Text(message)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
}

struct UpdateAvailableOverlayView: View {
    let onPress: () -> Void

    var body: some View {
        Button(action: onPress) {
            HStack(spacing: 7) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)

                Text("Update Available")
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .buttonStyle(.plain)
    }
}
