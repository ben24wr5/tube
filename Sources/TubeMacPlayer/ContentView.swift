import SwiftUI
import AppKit

struct ContentView: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var p: PlayerController
    @EnvironmentObject var yt: YouTubePlayer
    @EnvironmentObject var downloads: DownloadManager
    @State private var lastVideo: VideoItem?

    var body: some View {
        let theme = store.theme
        Group {
            if p.isFullscreen {
                PlayerSurface()
                    .ignoresSafeArea()
                    .toolbar(.hidden, for: .windowToolbar)
            } else {
                NavigationSplitView {
                    Sidebar()
                        .navigationSplitViewColumnWidth(min: 200, ideal: 230, max: 300)
                } detail: {
                    DetailRoot()
                }
            }
        }
        .environment(\.theme, theme)
        .tint(theme.accent)
        .preferredColorScheme(theme.isDark ? .dark : .light)
        .sheet(isPresented: $store.showSettings) {
            SettingsView(showsDone: true)
                .environmentObject(store)
                .environment(\.theme, theme)
                .preferredColorScheme(theme.isDark ? .dark : .light)
        }
        .sheet(isPresented: $store.showUpload) {
            UploadView()
                .environmentObject(store)
                .environment(\.theme, theme)
                .preferredColorScheme(theme.isDark ? .dark : .light)
        }
        .sheet(isPresented: $store.showGoLive) {
            GoLiveView()
                .environmentObject(store)
                .environment(\.theme, theme)
                .preferredColorScheme(theme.isDark ? .dark : .light)
        }
        .overlay(alignment: .top) {
            if let t = store.toast {
                Text(t)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme.onAccent)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(theme.accent).shadow(radius: 10))
                    .padding(.top, 14)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .onAppear {
            let s = store
            p.keysEnabled = { [weak s] in s?.watchOpen == true }
            p.installKeyMonitor()
        }
        // Start the right video whenever something new is chosen
        .onChange(of: store.nowPlaying) { v in
            saveCurrentPosition()
            lastVideo = v
            guard let v else { p.stop(); yt.stop(); return }
            if let id = v.youtubeID {
                p.stop()
                yt.load(id, startAt: store.resumePosition(for: v))
                store.loadComments(for: v)
            } else {
                yt.stop()
                p.load(v, startAt: store.resumePosition(for: v),
                       quality: store.data.playbackQuality, speed: store.data.defaultSpeed)
            }
        }
        // When a video ends, count down to the next one
        .onChange(of: p.finishedCount) { _ in
            if let v = p.video { store.savePosition(v.id, 0) }
            store.startCountdown()
        }
        .onChange(of: yt.finishedCount) { _ in
            if let v = lastVideo { store.savePosition(v.id, 0) }
            store.startCountdown()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
            saveCurrentPosition()
        }
    }
}

extension ContentView {
    /// Remembers where you stopped so the video resumes there next time.
    func saveCurrentPosition() {
        guard let old = lastVideo, !old.isLive else { return }
        let t = old.isYouTube ? yt.currentTime : p.currentTime
        if t > 0 { store.savePosition(old.id, t) }
    }
}

// MARK: - Sidebar

struct Sidebar: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.theme) var theme

    private var selection: Binding<SidebarItem?> {
        Binding(
            get: { (store.watchOpen || store.openChannel != nil || !store.search.isEmpty) ? nil : store.section },
            set: { if let v = $0 { store.goTo(v) } }
        )
    }

    var body: some View {
        List(selection: selection) {
            HStack(spacing: 8) {
                AppLogo(size: 30)
                Text("Tube Mac Player").font(.system(size: 15, weight: .heavy)).foregroundStyle(theme.text)
            }
            .padding(.vertical, 6)

            Section {
                ForEach([SidebarItem.home, .subscriptions, .live]) { item in
                    Label(item.title, systemImage: item.icon).tag(item)
                }
            }
            Section("You") {
                ForEach([SidebarItem.yourVideos, .history, .liked, .watchLater, .downloads]) { item in
                    Label(item.title, systemImage: item.icon).tag(item)
                }
            }
            if !store.subscribedChannels.isEmpty {
                Section("Subscriptions") {
                    ForEach(store.subscribedChannels) { c in
                        Button { store.showChannel(c.id) } label: {
                            HStack(spacing: 8) {
                                ChannelAvatar(channel: c, size: 22)
                                Text(c.name).lineLimit(1)
                                Spacer()
                                if store.data.notifications.contains(c.id) {
                                    Image(systemName: "bell.fill").font(.system(size: 9)).foregroundStyle(theme.secondaryText)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(theme.sidebar)
        .safeAreaInset(edge: .bottom) {
            Button { store.showSettings = true } label: {
                Label("Settings", systemImage: "gearshape.fill")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(RoundedRectangle(cornerRadius: 8).fill(theme.surfaceHigh))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(theme.text)
            .padding(10)
        }
    }
}

// MARK: - Detail area

struct DetailRoot: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var p: PlayerController
    @Environment(\.theme) var theme

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            theme.gradient.ignoresSafeArea()
            if theme.sparkle { SparkleLayer().ignoresSafeArea() }

            Group {
                if store.watchOpen, let v = store.nowPlaying {
                    WatchView(video: v)
                } else if !store.search.isEmpty {
                    SearchResultsView()
                } else if let c = store.openChannel {
                    ChannelView(channel: c)
                } else {
                    page
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if !store.watchOpen, let v = store.nowPlaying {
                MiniPlayer(video: v)
                    .padding(18)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.35), value: store.watchOpen)
        .searchable(text: $store.search, placement: .toolbar,
                    prompt: store.hasYouTube ? "Search YouTube" : "Search Tube Mac Player")
        .onSubmit(of: .search) { store.searchYouTube() }
        .navigationTitle("")
        .toolbar {
            ToolbarItem(placement: .navigation) {
                if store.watchOpen || store.openChannel != nil {
                    Button {
                        if store.watchOpen { store.watchOpen = false } else { store.openChannel = nil }
                    } label: { Image(systemName: "chevron.left") }
                    .help("Back")
                }
            }
            ToolbarItemGroup(placement: .primaryAction) {
                Button { store.showUpload = true } label: { Label("Upload", systemImage: "video.badge.plus") }
                    .help("Upload a video")
                Button { store.showGoLive = true } label: { Label("Go live", systemImage: "dot.radiowaves.left.and.right") }
                    .help("Go live")
            }
        }
    }

    @ViewBuilder private var page: some View {
        switch store.section {
        case .home: HomeView()
        case .subscriptions: SubscriptionsView()
        case .live: LiveView()
        case .history:
            VideoListPage(title: "History", subtitle: "Everything you've watched.", ids: store.data.history,
                          emptyIcon: "clock.arrow.circlepath", emptyMessage: "Videos you watch will show up here.",
                          clearLabel: "Clear history", onClear: { store.data.history.removeAll(); store.data.positions.removeAll() })
        case .liked:
            VideoListPage(title: "Liked videos", subtitle: "Videos you gave a thumbs up.",
                          ids: Array(store.data.liked).sorted(), emptyIcon: "hand.thumbsup",
                          emptyMessage: "Tap the thumbs up on any video to keep it here.")
        case .watchLater:
            VideoListPage(title: "Watch later", subtitle: "Saved for when you've got time.", ids: store.data.watchLater,
                          emptyIcon: "clock", emptyMessage: "Press Save under any video to add it.",
                          clearLabel: "Clear all", onClear: { store.data.watchLater.removeAll() })
        case .yourVideos: YourVideosView()
        case .downloads: DownloadsView()
        }
    }
}
