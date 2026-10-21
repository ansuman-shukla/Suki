import AppKit
import AVFoundation
import SwiftUI

struct HomeView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var player = HomeAudioPlayer()

    var body: some View {
        ScrollView {
            HomeContent(
                firstName: HomeCopy.firstName(fromFullName: NSFullUserName()),
                shortcut: HomeCopy.dictationShortcut(hold: appState.holdShortcut, toggle: appState.toggleShortcut),
                stats: appState.dictationStats.summary(today: Date()),
                groups: HomeHistoryGrouping.groups(
                    appState.pipelineHistory.compactMap(HomeHistoryGrouping.entry(from:)),
                    now: Date()
                ),
                retryingIDs: appState.retryingItemIDs,
                playingID: player.playingID,
                actions: actions
            )
        }
        .onDisappear { player.stop() }
    }

    private var actions: HomeRowActions {
        HomeRowActions(
            copy: { entry in
                guard let text = entry.text else { return }
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
            },
            togglePlayback: { entry in
                guard let audioFileName = item(for: entry)?.audioFileName else { return }
                player.toggle(id: entry.id, url: AppState.audioStorageDirectory().appendingPathComponent(audioFileName))
            },
            retry: { entry in
                guard let item = item(for: entry) else { return }
                appState.retryTranscription(item: item)
            },
            delete: { entry in
                if player.playingID == entry.id { player.stop() }
                appState.deleteHistoryEntry(id: entry.id)
            }
        )
    }

    private func item(for entry: HomeHistoryEntry) -> PipelineHistoryItem? {
        appState.pipelineHistory.first { $0.id == entry.id }
    }
}

/// Plays one history recording at a time.
final class HomeAudioPlayer: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published private(set) var playingID: UUID?
    private var player: AVAudioPlayer?

    func toggle(id: UUID, url: URL) {
        let wasPlaying = playingID == id
        stop()
        guard !wasPlaying, let player = try? AVAudioPlayer(contentsOf: url) else { return }
        player.delegate = self
        player.play()
        self.player = player
        playingID = id
    }

    func stop() {
        player?.stop()
        player = nil
        playingID = nil
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async { [weak self] in
            guard self?.player === player else { return }
            self?.stop()
        }
    }
}
