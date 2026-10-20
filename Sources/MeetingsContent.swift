import SwiftUI

/// Everything the Meetings screen shows, as plain data.
struct MeetingsScreen {
    var phase: MeetingPhase = .idle
    var startedAt: Date?
    var level: Float = 0
    var liveSegments: [MeetingSegment] = []
    var meetings: [MeetingRecord] = []
    var toast: String?
    var errorMessage: String?
    /// Why recording can't start right now, e.g. an old macOS or no API key.
    var unavailableReason: String?
}

struct MeetingsContent: View {
    let screen: MeetingsScreen
    var onRecord: () -> Void = {}
    var onStop: () -> Void = {}
    var onCopy: (MeetingRecord) -> Void = { _ in }
    var onDelete: (MeetingRecord) -> Void = { _ in }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Meetings")
                        .font(SukiFont.display(34))
                    Text("Record a call. Suki writes down what you and they said.")
                        .font(SukiFont.ui(14))
                        .foregroundStyle(Theme.textSecondary)
                }

                if screen.phase == .idle || screen.phase == .starting {
                    VStack(alignment: .leading, spacing: 10) {
                        RecordMeetingButton(
                            isStarting: screen.phase == .starting,
                            isEnabled: screen.unavailableReason == nil,
                            action: onRecord
                        )
                        if let reason = screen.unavailableReason {
                            Text(reason)
                                .font(SukiFont.ui(13))
                                .foregroundStyle(Theme.textSecondary)
                        } else if let errorMessage = screen.errorMessage {
                            Text(errorMessage)
                                .font(SukiFont.ui(13))
                                .foregroundStyle(Theme.destructive)
                        }
                    }
                } else {
                    LiveMeetingCard(screen: screen, onStop: onStop)
                        .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
                }

                PastMeetingsList(meetings: screen.meetings, onCopy: onCopy, onDelete: onDelete)
            }
            .padding(.horizontal, 40)
            .padding(.vertical, 36)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .overlay(alignment: .bottom) {
            if let toast = screen.toast {
                MeetingToast(text: toast)
                    .padding(.bottom, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.suki, value: screen.phase)
        .animation(.sukiPop, value: screen.toast)
    }
}

private struct RecordMeetingButton: View {
    let isStarting: Bool
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Circle()
                    .fill(Theme.destructive)
                    .frame(width: 10, height: 10)
                Text(isStarting ? "Starting…" : "Record meeting")
                    .font(SukiFont.ui(16, .semibold))
            }
            .foregroundStyle(Theme.primaryButtonText)
            .padding(.horizontal, 28)
            .frame(height: 52)
            .background(Capsule().fill(Theme.primaryButton))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(isStarting || !isEnabled)
        .opacity(isEnabled ? 1 : 0.4)
    }
}

private struct LiveMeetingCard: View {
    let screen: MeetingsScreen
    let onStop: () -> Void

    private var isFinishing: Bool { screen.phase == .finishing }
    private var lines: [MeetingSegment] { MeetingTranscriptCore.merged(screen.liveSegments) }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 14) {
                PulsingDot(isActive: !isFinishing)
                ElapsedClock(startedAt: screen.startedAt, isRunning: !isFinishing)
                MeetingWaveform(level: isFinishing ? 0 : screen.level)
                Spacer()
                Button(action: onStop) {
                    Text(isFinishing ? "Finishing…" : "Stop & copy")
                        .font(SukiFont.ui(14, .semibold))
                        .foregroundStyle(Theme.primaryButtonText)
                        .padding(.horizontal, 20)
                        .frame(height: 38)
                        .background(Capsule().fill(Theme.primaryButton))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(isFinishing)
                .opacity(isFinishing ? 0.6 : 1)
            }

            Rectangle()
                .fill(Theme.divider)
                .frame(height: 1)

            if lines.isEmpty {
                Text(isFinishing ? "Writing up the last few seconds…" : "Listening. Lines show up here every 20 seconds or so.")
                    .font(SukiFont.ui(14))
                    .foregroundStyle(Theme.textTertiary)
            } else {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(lines) { MeetingLine(segment: $0) }
                }
            }
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .fill(Theme.card)
        )
    }
}

private struct PulsingDot: View {
    let isActive: Bool
    @State private var pulsing = false

    var body: some View {
        Circle()
            .fill(isActive ? Theme.destructive : Theme.textTertiary)
            .frame(width: 10, height: 10)
            .opacity(isActive && pulsing ? 0.3 : 1)
            .animation(isActive ? .easeInOut(duration: 0.9).repeatForever(autoreverses: true) : .suki, value: pulsing)
            .onAppear { pulsing = true }
    }
}

private struct ElapsedClock: View {
    let startedAt: Date?
    let isRunning: Bool

    var body: some View {
        TimelineView(.periodic(from: startedAt ?? Date(), by: 1)) { context in
            Text(MeetingTranscriptCore.clock(startedAt.map { context.date.timeIntervalSince($0) } ?? 0))
                .font(SukiFont.display(28))
                .monospacedDigit()
                .foregroundStyle(isRunning ? Theme.textPrimary : Theme.textSecondary)
        }
    }
}

/// Five mirrored bars that grow from the center out; outer bars are shorter and lag slightly.
struct MeetingWaveform: View {
    let level: Float
    private let count = 5
    private let maxHeight: CGFloat = 28
    private let minHeight: CGFloat = 4

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<count, id: \.self) { index in
                let scale = MeetingTranscriptCore.waveformScale(index: index, count: count)
                Capsule()
                    .fill(Theme.textPrimary)
                    .frame(width: 3, height: minHeight + (maxHeight - minHeight) * CGFloat(level) * scale)
                    .animation(.suki.delay(MeetingTranscriptCore.waveformDelay(index: index, count: count)), value: level)
            }
        }
        .frame(height: maxHeight)
    }
}

private struct SpeakerLabel: View {
    let speaker: MeetingSpeaker

    var body: some View {
        Text(speaker.label)
            .font(SukiFont.ui(11, .semibold))
            .tracking(0.8)
            .textCase(.uppercase)
            .foregroundStyle(speaker == .me ? Theme.micActive : Theme.chart)
            .frame(width: 44, alignment: .leading)
    }
}

private struct MeetingLine: View {
    let segment: MeetingSegment

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            SpeakerLabel(speaker: segment.speaker)
            Text(segment.text)
                .font(SukiFont.ui(14))
                .foregroundStyle(segment.text == MeetingTranscriptCore.failedChunkText ? Theme.textTertiary : Theme.textPrimary)
                .lineSpacing(3)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct PastMeetingsList: View {
    let meetings: [MeetingRecord]
    let onCopy: (MeetingRecord) -> Void
    let onDelete: (MeetingRecord) -> Void
    @State private var expandedID: UUID?

    var body: some View {
        if meetings.isEmpty {
            Text("Your meetings will show up here.")
                .font(SukiFont.ui(14))
                .foregroundStyle(Theme.textTertiary)
        } else {
            VStack(alignment: .leading, spacing: 24) {
                ForEach(MeetingTranscriptCore.groupedByDay(meetings), id: \.day) { group in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(MeetingTranscriptCore.dayLabel(for: group.day, now: Date()))
                            .sectionLabelStyle()
                            .padding(.horizontal, 12)
                        ForEach(group.meetings) { meeting in
                            PastMeetingRow(
                                meeting: meeting,
                                isExpanded: expandedID == meeting.id,
                                onToggle: { expandedID = expandedID == meeting.id ? nil : meeting.id },
                                onCopy: { onCopy(meeting) },
                                onDelete: { onDelete(meeting) }
                            )
                        }
                    }
                }
            }
            .animation(.suki, value: expandedID)
            .animation(.suki, value: meetings.map(\.id))
        }
    }
}

private struct PastMeetingRow: View {
    let meeting: MeetingRecord
    let isExpanded: Bool
    let onToggle: () -> Void
    let onCopy: () -> Void
    let onDelete: () -> Void
    @State private var isHovered = false

    private var lines: [MeetingSegment] { MeetingTranscriptCore.merged(meeting.segments) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(meeting.title)
                        .font(SukiFont.ui(14, .medium))
                        .foregroundStyle(Theme.textPrimary)
                    Text(MeetingTranscriptCore.clock(meeting.duration))
                        .font(SukiFont.ui(12))
                        .foregroundStyle(Theme.textSecondary)
                    if !isExpanded, let first = lines.first {
                        Text("\(first.speaker.label): \(first.text)")
                            .font(SukiFont.ui(13))
                            .foregroundStyle(Theme.textTertiary)
                            .lineLimit(1)
                    }
                }
                Spacer()
                HStack(spacing: 4) {
                    RowIconButton(systemName: "doc.on.doc", help: "Copy transcript", action: onCopy)
                    RowIconButton(systemName: "trash", help: "Delete meeting", action: onDelete)
                }
                .opacity(isHovered || isExpanded ? 1 : 0)
            }

            if isExpanded {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(lines) { MeetingLine(segment: $0) }
                }
                .transition(.opacity)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(isHovered || isExpanded ? Theme.rowHover : Color.clear)
        )
        .contentShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        .onHover { isHovered = $0 }
        .onTapGesture(perform: onToggle)
        .animation(.suki, value: isHovered)
    }
}

private struct RowIconButton: View {
    let systemName: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 13))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

private struct MeetingToast: View {
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark")
                .font(.system(size: 12, weight: .semibold))
            Text(text)
                .font(SukiFont.ui(13, .medium))
        }
        .foregroundStyle(Theme.primaryButtonText)
        .padding(.horizontal, 16)
        .frame(height: 36)
        .background(Capsule().fill(Theme.primaryButton))
    }
}
