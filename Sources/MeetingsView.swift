import SwiftUI

struct MeetingsView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        Text("Meetings")
            .font(SukiFont.display(28))
    }
}
