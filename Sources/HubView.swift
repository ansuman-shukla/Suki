import SwiftUI

struct HubView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var router: HubRouter

    var body: some View {
        ZStack {
            HubShell { sectionContent }

            if router.isSettingsPresented {
                HubModal(onClose: { router.isSettingsPresented = false }) {
                    SettingsView()
                }
                .transition(.opacity)
                .zIndex(1)
            }
        }
        .animation(.suki, value: router.isSettingsPresented)
        .animation(.suki, value: router.section)
    }

    @ViewBuilder
    private var sectionContent: some View {
        switch router.section {
        case .home:
            HomeView()
        case .meetings:
            MeetingsView()
        case .dictionary:
            DictionaryView()
        case .snippets:
            SnippetsView()
        }
    }
}
