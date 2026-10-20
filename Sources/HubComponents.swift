import SwiftUI

enum HubSection: String, CaseIterable, Identifiable {
    case home

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: return "Home"
        }
    }

    var icon: String {
        switch self {
        case .home: return "mic"
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
