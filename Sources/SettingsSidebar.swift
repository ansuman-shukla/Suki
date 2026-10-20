import SwiftUI

enum SettingsPage: String, Identifiable {
    case general
    case system
    case prompts
    case macros
    case runLog
    case debug

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "General"
        case .system: return "System"
        case .prompts: return "Prompts"
        case .macros: return "Voice Macros"
        case .runLog: return "Run Log"
        case .debug: return "Debug"
        }
    }

    var icon: String {
        switch self {
        case .general: return "gearshape"
        case .system: return "macwindow"
        case .prompts: return "text.bubble"
        case .macros: return "music.mic"
        case .runLog: return "clock.arrow.circlepath"
        case .debug: return "wrench.and.screwdriver"
        }
    }
}

struct SettingsSidebarGroup: Identifiable {
    let title: String
    let pages: [SettingsPage]

    var id: String { title }
}

/// Settings sheet layout: darker sand sidebar of grouped pages, the selected pane, and a close button.
struct SettingsShell<Content: View>: View {
    let groups: [SettingsSidebarGroup]
    @Binding var selection: SettingsPage
    var footer: String?
    let onClose: () -> Void
    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            ZStack {
                content
                    .id(selection)
                    .transition(.opacity.combined(with: .offset(y: 6)))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.panel)
        }
        .animation(.suki, value: selection)
        .overlay(alignment: .topTrailing) {
            SettingsCloseButton(action: onClose)
                .padding(14)
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 22) {
            ForEach(groups) { group in
                SettingsSidebarSection(title: group.title) {
                    ForEach(group.pages) { page in
                        HubSidebarRow(title: page.title, icon: page.icon, isSelected: selection == page) {
                            selection = page
                        }
                    }
                }
            }
            Spacer(minLength: 0)
            if let footer {
                Text(footer)
                    .font(SukiFont.ui(11.5))
                    .foregroundStyle(Theme.textTertiary)
                    .padding(.horizontal, 10)
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, 26)
        .padding(.bottom, 16)
        .frame(width: 196)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Theme.windowBackground)
    }
}
