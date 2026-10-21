import SwiftUI

struct DictionaryView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        Text("Dictionary")
            .font(SukiFont.display(28))
    }
}
