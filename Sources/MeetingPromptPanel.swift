import AppKit
import SwiftUI

/// Bottom-center nudge offering to record a detected call. Floats over the call without
/// taking focus and fades away on its own.
@MainActor
final class MeetingPromptPanel {
    private var panel: NSPanel?
    private var dismissTask: Task<Void, Never>?
    private let autoDismissSeconds: UInt64 = 20

    var isShown: Bool { panel != nil }

    func show(appName: String, onAccept: @escaping () -> Void) {
        hide()
        let hosting = NSHostingView(rootView: MeetingPromptView(
            appName: appName,
            onAccept: { [weak self] in
                self?.hide()
                onAccept()
            },
            onDismiss: { [weak self] in self?.hide() }
        ))
        let size = hosting.fittingSize
        hosting.frame = NSRect(origin: .zero, size: size)

        let panel = NSPanel(
            contentRect: hosting.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.contentView = hosting
        if let frame = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: frame.midX - size.width / 2, y: frame.minY + 96))
        }
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            panel.animator().alphaValue = 1
        }
        self.panel = panel

        let seconds = autoDismissSeconds
        dismissTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: seconds * 1_000_000_000)
            guard !Task.isCancelled else { return }
            self?.hide()
        }
    }

    func hide() {
        dismissTask?.cancel()
        dismissTask = nil
        guard let panel else { return }
        self.panel = nil
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2
            panel.animator().alphaValue = 0
        }, completionHandler: {
            panel.orderOut(nil)
        })
    }
}

struct MeetingPromptView: View {
    let appName: String
    var onAccept: () -> Void = {}
    var onDismiss: () -> Void = {}

    private let card = Color(hex: Palette.vast950)
    private let muted = Color(hex: Palette.vast400)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            MeetingNotesIllustration()
                .overlay(alignment: .topTrailing) {
                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Color(hex: Palette.vast800))
                            .frame(width: 22, height: 22)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(6)
                    .accessibilityLabel("Close")
                }

            VStack(alignment: .leading, spacing: 6) {
                Text("Want notes for this meeting?")
                    .font(SukiFont.ui(14, .semibold))
                    .foregroundStyle(.white)
                Text("\(AppName.displayName) can transcribe your call in \(appName) and copy the transcript when you stop.")
                    .font(SukiFont.ui(12))
                    .foregroundStyle(muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 12)
            .padding(.horizontal, 4)

            HStack(spacing: 8) {
                Spacer(minLength: 0)
                Button("Maybe later", action: onDismiss)
                    .buttonStyle(.plain)
                    .font(SukiFont.ui(12, .medium))
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(.horizontal, 8)
                Button(action: onAccept) {
                    Text("Yes, take notes for me")
                        .font(SukiFont.ui(12, .semibold))
                        .foregroundStyle(card)
                        .padding(.horizontal, 12)
                        .frame(height: 28)
                        .background(Capsule().fill(Color(hex: Palette.sand50)))
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 14)
        }
        .padding(10)
        .frame(width: 300)
        .background(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous).fill(card))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }
}

/// A tiny "notes window" drawn in code: paper backdrop, a mini window with traffic lights,
/// a serif title and a few lines of placeholder text.
private struct MeetingNotesIllustration: View {
    var body: some View {
        ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(Color(hex: Palette.sand600))

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 4) {
                    ForEach([Palette.red450, Palette.glow300, Palette.fathom500], id: \.self) {
                        Circle().fill(Color(hex: $0)).frame(width: 5, height: 5)
                    }
                }
                Text("Meeting Notes")
                    .font(SukiFont.display(14))
                    .foregroundStyle(Color(hex: Palette.vast950))
                    .padding(.top, 2)
                ForEach(Array([0.9, 0.75, 0.82, 0.6].enumerated()), id: \.offset) { _, width in
                    Capsule()
                        .fill(Color(hex: Palette.vast50))
                        .frame(width: 150 * width, height: 4)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .frame(width: 180, height: 84, alignment: .topLeading)
            .background(
                UnevenRoundedRectangle(topLeadingRadius: 6, topTrailingRadius: 6)
                    .fill(Color(hex: Palette.sand50))
            )
        }
        .frame(height: 104)
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }
}
