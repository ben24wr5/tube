import SwiftUI

@main
struct TubeMacPlayerApp: App {
    @StateObject private var store = AppStore()
    @StateObject private var downloads = DownloadManager()
    @StateObject private var playback = PlayerController()
    @StateObject private var youtubePlayer = YouTubePlayer()

    var body: some Scene {
        Window("Tube Mac Player", id: "main") {
            ContentView()
                .environmentObject(store)
                .environmentObject(downloads)
                .environmentObject(playback)
                .environmentObject(youtubePlayer)
                .frame(minWidth: 980, minHeight: 640)
        }
        .defaultSize(width: 1320, height: 840)
        .commands {
            CommandMenu("Playback") {
                Button("Play / Pause") {
                    if youtubePlayer.videoID != nil { youtubePlayer.togglePlay() } else { playback.togglePlay() }
                }
                .keyboardShortcut("k", modifiers: [.command])
                Button("Picture in Picture") {
                    if youtubePlayer.videoID != nil { youtubePlayer.togglePopOut() } else { playback.togglePiP() }
                }
                    .keyboardShortcut("p", modifiers: [.command, .shift])
                Button("Full Screen Video") { playback.toggleFullscreen() }
                    .keyboardShortcut("f", modifiers: [.command, .shift])
            }
        }
    }
}
