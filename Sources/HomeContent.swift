import SwiftUI

struct HomeRowActions {
    var copy: (HomeHistoryEntry) -> Void = { _ in }
    var togglePlayback: (HomeHistoryEntry) -> Void = { _ in }
    var retry: (HomeHistoryEntry) -> Void = { _ in }
    var delete: (HomeHistoryEntry) -> Void = { _ in }
}

/// The home page column rendered from plain values so it can be previewed without `AppState`.
/// `HomeView` places it in a scroll view.
struct HomeContent: View {
    let firstName: String?
    let shortcut: HomeShortcut?
    let stats: DictationStatsSummary
    let groups: [HomeHistoryGroup]
    var retryingIDs: Set<UUID> = []
    var playingID: UUID?
    var hoveredPreviewID: UUID?
    var actions = HomeRowActions()

    var body: some View {
        VStack(alignment: .leading, spacing: 36) {
            HomeGreeting(firstName: firstName, shortcut: shortcut)
            HomeStatsCard(stats: stats)
            if groups.isEmpty {
                HomeEmptyState(shortcut: shortcut)
            } else {
                history
            }
        }
        .frame(maxWidth: 720, alignment: .leading)
        .padding(40)
        .frame(maxWidth: .infinity)
    }

    private var history: some View {
        VStack(alignment: .leading, spacing: 28) {
            ForEach(groups) { group in
                VStack(alignment: .leading, spacing: 8) {
                    Text(group.title)
                        .sectionLabelStyle()
                        .padding(.horizontal, 12)
                    VStack(spacing: 0) {
                        ForEach(group.entries) { entry in
                            HomeHistoryRow(
                                entry: entry,
                                isRetrying: retryingIDs.contains(entry.id),
                                isPlaying: playingID == entry.id,
                                actions: actions,
                                isHovered: hoveredPreviewID == entry.id
                            )
                        }
                    }
                }
            }
        }
    }
}

struct HomeKeycap: View {
    let label: String
    var size: CGFloat = 13

    var body: some View {
        Text(label)
            .font(SukiFont.ui(size, .semibold))
            .foregroundStyle(Theme.keycapText)
            .padding(.horizontal, size * 0.6)
            .padding(.vertical, size * 0.2)
            .background(Capsule().fill(Theme.keycap))
            .fixedSize()
    }
}

private struct HomeGreeting: View {
    let firstName: String?
    let shortcut: HomeShortcut?

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                lead.fixedSize()
                keycap
            }
            VStack(alignment: .leading, spacing: 8) {
                lead
                keycap
            }
        }
        .foregroundStyle(Theme.textPrimary)
    }

    private var lead: some View {
        Text(HomeCopy.greetingLead(firstName: firstName, hasShortcut: shortcut != nil))
            .font(SukiFont.display(34))
            .tracking(-0.4)
    }

    @ViewBuilder
    private var keycap: some View {
        if let shortcut {
            HomeKeycap(label: shortcut.label, size: 17)
                .alignmentGuide(.firstTextBaseline) { $0[.firstTextBaseline] + 1 }
        }
    }
}

private struct HomeStatsCard: View {
    let stats: DictationStatsSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 0) {
                stat(HomeCopy.formattedCount(stats.totalWords), "Words dictated")
                divider
                stat(HomeCopy.wordsPerMinuteValue(stats.wordsPerMinute), "Words per minute")
                divider
                stat(HomeCopy.formattedCount(stats.currentStreakDays), "Day streak")
            }
            Rectangle().fill(Theme.divider).frame(height: 1)
            HStack(spacing: 8) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(stats.currentStreakDays > 0 ? Theme.keycap : Theme.textTertiary)
                Text(HomeCopy.streakMessage(days: stats.currentStreakDays))
                    .font(SukiFont.ui(13, .medium))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(24)
        .background(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).fill(Theme.card))
    }

    private var divider: some View {
        Rectangle().fill(Theme.divider).frame(width: 1, height: 52).padding(.horizontal, 24)
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(SukiFont.display(40))
                .tracking(-0.5)
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label)
                .font(SukiFont.ui(12, .medium))
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct HomeEmptyState: View {
    let shortcut: HomeShortcut?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Your words will gather here.")
                .font(SukiFont.displayItalic(24))
                .foregroundStyle(Theme.textPrimary)
            if let shortcut {
                HStack(spacing: 6) {
                    Text(shortcut.verb)
                    HomeKeycap(label: shortcut.label, size: 12)
                    Text("and start talking.")
                }
                .font(SukiFont.ui(14))
                .foregroundStyle(Theme.textSecondary)
            } else {
                Text("Set a dictation shortcut in Settings to get started.")
                    .font(SukiFont.ui(14))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
    }
}

private struct HomeHistoryRow: View {
    let entry: HomeHistoryEntry
    let isRetrying: Bool
    let isPlaying: Bool
    let actions: HomeRowActions
    @State private var isHovered: Bool
    @State private var showsCopied = false

    init(entry: HomeHistoryEntry, isRetrying: Bool, isPlaying: Bool, actions: HomeRowActions, isHovered: Bool = false) {
        self.entry = entry
        self.isRetrying = isRetrying
        self.isPlaying = isPlaying
        self.actions = actions
        _isHovered = State(initialValue: isHovered)
    }

    private var showsActions: Bool { isHovered || isPlaying || showsCopied }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text(HomeHistoryGrouping.timeLabel(for: entry.timestamp))
                .font(SukiFont.ui(13))
                .monospacedDigit()
                .foregroundStyle(Theme.textTertiary)
                .frame(width: 56, alignment: .leading)
            transcript
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(isHovered ? Theme.rowHover : .clear)
        )
        .overlay(alignment: .topTrailing) {
            actionBar
                .padding(6)
                .opacity(showsActions ? 1 : 0)
                .allowsHitTesting(showsActions)
        }
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .animation(.suki, value: isHovered)
        .animation(.suki, value: showsCopied)
    }

    @ViewBuilder
    private var transcript: some View {
        if isRetrying {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small).scaleEffect(0.7).frame(width: 14, height: 14)
                Text("Transcribing again…")
            }
            .font(SukiFont.ui(14))
            .foregroundStyle(Theme.textSecondary)
        } else if let text = entry.text {
            Text(text)
                .font(SukiFont.ui(14))
                .lineSpacing(3)
                .foregroundStyle(Theme.textPrimary)
                .textSelection(.enabled)
        } else {
            Text("No transcript. Retry to transcribe the recording again.")
                .font(SukiFont.ui(14))
                .italic()
                .foregroundStyle(Theme.textTertiary)
        }
    }

    private var actionBar: some View {
        HStack(spacing: 2) {
            if entry.text != nil {
                if showsCopied {
                    Label("Copied", systemImage: "checkmark")
                        .font(SukiFont.ui(12, .medium))
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.horizontal, 8)
                        .frame(height: 26)
                        .transition(.opacity)
                } else {
                    HomeIconButton(systemImage: "doc.on.doc", help: "Copy") {
                        actions.copy(entry)
                        showsCopied = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { showsCopied = false }
                    }
                }
            }
            if entry.hasAudio {
                HomeIconButton(systemImage: isPlaying ? "stop.fill" : "play.fill", help: isPlaying ? "Stop" : "Play audio") {
                    actions.togglePlayback(entry)
                }
                HomeIconButton(systemImage: "arrow.clockwise", help: "Retry transcription") {
                    actions.retry(entry)
                }
                .disabled(isRetrying)
            }
            Menu {
                Button("Delete", role: .destructive) { actions.delete(entry) }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("More")
        }
        .foregroundStyle(Theme.textSecondary)
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .fill(Theme.panel)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .stroke(Theme.border, lineWidth: 1)
        )
    }
}

private struct HomeIconButton: View {
    let systemImage: String
    let help: String
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .medium))
                .frame(width: 26, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: Radius.xs, style: .continuous)
                        .fill(isHovered ? Theme.rowHover : .clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .onHover { isHovered = $0 }
    }
}
