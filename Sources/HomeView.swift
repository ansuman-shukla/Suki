import SwiftUI

struct HomeView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        Text("Home")
            .font(SukiFont.display(28))
    }
}
