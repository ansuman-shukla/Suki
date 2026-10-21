import SwiftUI

enum HubSection: String, CaseIterable, Identifiable {
    case home
    case meetings
    case dictionary
    case snippets

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: return "Home"
        case .meetings: return "Meetings"
        case .dictionary: return "Dictionary"
        case .snippets: return "Snippets"
        }
    }

    var icon: String {
        switch self {
        case .home: return "mic"
        case .meetings: return "record.circle"
        case .dictionary: return "book.closed"
        case .snippets: return "scissors"
        }
    }
}

final class HubRouter: ObservableObject {
    @Published var section: HubSection = .home
    @Published var isSettingsPresented = false
}

/// Beige sidebar "desk" with the floating rounded content "paper" next to it.
struct HubShell<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing: 0) {
            HubSidebar()
                .frame(width: 208)

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.panel)
                .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                        .stroke(Theme.border, lineWidth: 1)
                )
                .padding(.top, 44)
                .padding([.trailing, .bottom], 8)
        }
        .background(Theme.windowBackground)
        .foregroundStyle(Theme.textPrimary)
    }
}

struct HubSidebar: View {
    @EnvironmentObject var router: HubRouter

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HubLogo()
                .padding(.horizontal, 12)
                .padding(.top, 52)
                .padding(.bottom, 20)

            ForEach(HubSection.allCases) { section in
                HubSidebarRow(
                    title: section.title,
                    icon: section.icon,
                    isSelected: router.section == section
                ) {
                    router.section = section
                }
            }

            Spacer()

            HubSidebarRow(title: "Settings", icon: "gearshape", isSelected: false) {
                router.isSettingsPresented = true
            }
            .padding(.bottom, 12)
        }
        .padding(.horizontal, 10)
    }
}

struct HubLogo: View {
    var body: some View {
        HStack(spacing: 7) {
            HStack(alignment: .center, spacing: 2) {
                ForEach(Array([8.0, 14.0, 18.0, 12.0].enumerated()), id: \.offset) { _, height in
                    Capsule().frame(width: 3, height: height)
                }
            }
            Text(AppName.displayName)
                .font(SukiFont.ui(20, .bold))
                .tracking(-0.3)
        }
        .foregroundStyle(Theme.textPrimary)
    }
}

struct HubSidebarRow: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .regular))
                    .frame(width: 18)
                Text(title)
                    .font(SukiFont.ui(14, .medium))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .frame(height: 32)
            .background(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(isSelected ? Theme.selection : (isHovered ? Theme.selection.opacity(0.5) : .clear))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(Theme.textPrimary)
        .onHover { isHovered = $0 }
        .animation(.suki, value: isHovered)
    }
}

/// Centered modal over a dimmed hub, like a sheet but dismissible by clicking outside or pressing Escape.
struct HubModal<Content: View>: View {
    let onClose: () -> Void
    @ViewBuilder let content: Content
    @State private var isShown = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.28)
                .ignoresSafeArea()
                .onTapGesture(perform: onClose)

            content
                .frame(minWidth: 760, idealWidth: 860, maxWidth: 940, minHeight: 500, idealHeight: 580, maxHeight: 640)
                .background(Theme.panel)
                .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
                .shadow(color: .black.opacity(0.25), radius: 40, y: 20)
                .padding(40)
                .scaleEffect(isShown ? 1 : 0.97)
                .opacity(isShown ? 1 : 0)

            Button("", action: onClose)
                .keyboardShortcut(.cancelAction)
                .opacity(0)
                .frame(width: 0, height: 0)
        }
        .onAppear { withAnimation(.suki) { isShown = true } }
    }
}

/// Serif page title with a one-line subtitle and optional trailing actions.
struct HubPageHeader<Actions: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let actions: Actions

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(SukiFont.display(34))
                    .tracking(-0.4)
                Text(subtitle)
                    .font(SukiFont.ui(14))
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer(minLength: 0)
            actions
        }
    }
}

struct HubButtonStyle: ButtonStyle {
    var isPrimary = true
    var isCompact = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(SukiFont.ui(isCompact ? 12 : 13, .semibold))
            .padding(.horizontal, isCompact ? 10 : 14)
            .frame(height: isCompact ? 28 : 32)
            .foregroundStyle(isPrimary ? Theme.primaryButtonText : Theme.textPrimary)
            .background(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(isPrimary ? Theme.primaryButton : Theme.secondaryButton)
            )
            .opacity(configuration.isPressed ? 0.8 : 1)
            .contentShape(Rectangle())
    }
}

struct HubSearchField: View {
    @Binding var text: String
    let prompt: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13))
                .foregroundStyle(Theme.textTertiary)
            TextField(prompt, text: $text)
                .textFieldStyle(.plain)
                .font(SukiFont.ui(14))
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Theme.textTertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 36)
        .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(Theme.card))
    }
}

/// Small borderless icon button for row actions such as edit and delete.
struct HubIconButton: View {
    let systemName: String
    let help: String
    var isDestructive = false
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(isHovered && isDestructive ? Theme.destructive : Theme.textSecondary)
                .frame(width: 26, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                        .fill(isHovered ? Theme.panel : .clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .onHover { isHovered = $0 }
        .animation(.suki, value: isHovered)
    }
}

/// Edit and delete buttons that fade in while their row is hovered.
struct HubRowActions: View {
    let isVisible: Bool
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 2) {
            HubIconButton(systemName: "pencil", help: "Edit", action: onEdit)
            HubIconButton(systemName: "trash", help: "Delete", isDestructive: true, action: onDelete)
        }
        .opacity(isVisible ? 1 : 0)
        .allowsHitTesting(isVisible)
        .animation(.suki, value: isVisible)
    }
}

/// Serif empty-state line with a short hint underneath.
struct HubEmptyState: View {
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 8) {
            Text(title)
                .font(SukiFont.displayItalic(22))
            Text(message)
                .font(SukiFont.ui(13))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 56)
    }
}

/// Rounded list row that reveals edit and delete actions on hover.
struct HubListRow<Content: View>: View {
    let onEdit: () -> Void
    let onDelete: () -> Void
    let content: Content
    @State private var isHovered: Bool

    init(
        isHovered: Bool = false,
        onEdit: @escaping () -> Void,
        onDelete: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.onEdit = onEdit
        self.onDelete = onDelete
        self.content = content()
        _isHovered = State(initialValue: isHovered)
    }

    var body: some View {
        HStack(spacing: 12) {
            content
                .frame(maxWidth: .infinity, alignment: .leading)
            HubRowActions(isVisible: isHovered, onEdit: onEdit, onDelete: onDelete)
        }
        .padding(.leading, 14)
        .padding(.trailing, 7)
        .frame(minHeight: 40)
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(isHovered ? Theme.rowHover : Theme.card)
        )
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .animation(.suki, value: isHovered)
    }
}

/// Plain bordered text field used inside inline editors.
struct HubTextInput: View {
    @Binding var text: String
    let placeholder: String
    var isMultiline = false
    var autoFocus = false
    var onSubmit: () -> Void = {}
    @FocusState private var isFocused: Bool

    var body: some View {
        TextField(placeholder, text: $text, axis: isMultiline ? .vertical : .horizontal)
            .textFieldStyle(.plain)
            .font(SukiFont.ui(14))
            .lineLimit(isMultiline ? 2...6 : 1...1)
            .focused($isFocused)
            .onSubmit(onSubmit)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous).fill(Theme.panel))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .stroke(isFocused ? Theme.textTertiary : Theme.border, lineWidth: 1)
            )
            .task { if autoFocus { isFocused = true } }
    }
}

/// Card wrapping an inline editor's fields with an error line and Cancel / Save buttons.
struct HubEditorCard<Fields: View>: View {
    let error: String?
    let onSave: () -> Void
    let onCancel: () -> Void
    @ViewBuilder let fields: Fields

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            fields
            HStack(spacing: 8) {
                if let error {
                    Text(error)
                        .font(SukiFont.ui(12))
                        .foregroundStyle(Theme.destructive)
                        .transition(.opacity)
                }
                Spacer(minLength: 0)
                Button("Cancel", action: onCancel)
                    .buttonStyle(HubButtonStyle(isPrimary: false, isCompact: true))
                    .keyboardShortcut(.cancelAction)
                Button("Save", action: onSave)
                    .buttonStyle(HubButtonStyle(isCompact: true))
                    .keyboardShortcut(.return, modifiers: .command)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).fill(Theme.card))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .stroke(Theme.border, lineWidth: 1)
        )
        .animation(.suki, value: error)
    }
}
