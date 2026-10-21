import SwiftUI

/// One saved meeting: serif title, date chip, and the transcript as per-speaker sentence bubbles.
struct MeetingDetailContent: View {
    let meeting: MeetingRecord
    let onBack: () -> Void
    let onCopy: () -> Void
    let onDelete: () -> Void

    private var turns: [MeetingTurn] { MeetingTranscriptCore.turns(meeting.segments) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HubIconButton(systemName: "chevron.left", help: "Back to meetings", action: onBack)
                .background(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous).fill(Theme.card))
                .padding(14)

            VStack(alignment: .leading, spacing: 12) {
                Text(meeting.title)
                    .font(SukiFont.display(30))
                    .tracking(-0.4)
                    .textSelection(.enabled)
                MeetingChip(text: MeetingTranscriptCore.dayLabel(for: meeting.date, now: Date())
                    + " · " + MeetingTranscriptCore.timeLabel(for: meeting.date))
                MeetingTab(title: "Transcript")
                    .padding(.top, 6)
            }
            .meetingColumn()

            Rectangle()
                .fill(Theme.divider)
                .frame(height: 1)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    TranscriptInfoBar(
                        summary: MeetingTranscriptCore.transcriptSummary(meeting.segments, duration: meeting.duration),
                        onCopy: onCopy,
                        onDelete: onDelete
                    )
                    ForEach(turns) { MeetingTurnView(turn: $0) }
                }
                .padding(.top, 16)
                .padding(.bottom, 40)
                .meetingColumn()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// Underlined single tab label sitting on the divider below it, like a one-tab tab strip.
struct MeetingTab: View {
    let title: String

    var body: some View {
        Text(title)
            .font(SukiFont.ui(13, .medium))
            .foregroundStyle(Theme.textPrimary)
            .padding(.bottom, 8)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(Theme.textPrimary)
                    .frame(height: 2)
            }
    }
}

private struct MeetingChip: View {
    let text: String

    var body: some View {
        Text(text)
            .font(SukiFont.ui(11, .medium))
            .foregroundStyle(Theme.textSecondary)
            .padding(.horizontal, 8)
            .frame(height: 22)
            .overlay(
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .stroke(Theme.border, lineWidth: 1)
            )
    }
}

private struct TranscriptInfoBar: View {
    let summary: String
    let onCopy: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "clock")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
            Text(summary)
                .sectionLabelStyle()
            Spacer(minLength: 0)
            HubIconButton(systemName: "doc.on.doc", help: "Copy transcript", action: onCopy)
            HubIconButton(systemName: "trash", help: "Delete meeting", isDestructive: true, action: onDelete)
        }
        .padding(.leading, 12)
        .padding(.trailing, 4)
        .frame(height: 34)
        .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(Theme.card))
    }
}

private struct MeetingTurnView: View {
    let turn: MeetingTurn

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(turn.speaker.displayName)
                .font(SukiFont.ui(12, .medium))
                .foregroundStyle(turn.speaker == .me ? Theme.micActive : Theme.chart)
            ForEach(Array(turn.sentences.enumerated()), id: \.offset) { _, sentence in
                Text(sentence)
                    .font(SukiFont.ui(13))
                    .foregroundStyle(sentence == MeetingTranscriptCore.failedChunkText ? Theme.textTertiary : Theme.textPrimary)
                    .lineSpacing(2)
                    .textSelection(.enabled)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).fill(Theme.card))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private extension View {
    /// Narrow centered reading column used by the meeting page.
    func meetingColumn() -> some View {
        frame(maxWidth: 560, alignment: .leading)
            .padding(.horizontal, 40)
            .frame(maxWidth: .infinity)
    }
}
