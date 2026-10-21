import SwiftUI

struct TranscriptionSettingsPane: View {
    var body: some View {
        SettingsPane(title: "Transcription") {
            SettingsGroup("Transcription") {
                SettingsBlock { TranscriptionSettingsView() }
            }
            SettingsGroup("Live transcription") {
                SettingsBlock { LiveTranscriptionSettingsView() }
            }
        }
    }
}
