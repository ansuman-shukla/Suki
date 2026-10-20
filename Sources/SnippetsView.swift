import SwiftUI

struct SnippetsView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        Text("Snippets")
            .font(SukiFont.display(28))
    }
}
