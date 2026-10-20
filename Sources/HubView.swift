import SwiftUI

struct HubView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var router: HubRouter

    var body: some View {
        ZStack {
            HStack(spacing: 0) {
                HubSidebar()
                    .frame(width: 208)

                sectionContent
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

            if router.isSettingsPresented {
                HubModal(onClose: { router.isSettingsPresented = false }) {
                    SettingsView()
                }
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .background(Theme.windowBackground)
        .foregroundStyle(Theme.textPrimary)
        .animation(.suki, value: router.isSettingsPresented)
        .animation(.suki, value: router.section)
    }

    @ViewBuilder
    private var sectionContent: some View {
        switch router.section {
        case .home:
            Text("Home")
                .font(SukiFont.display(28))
        }
    }
}
