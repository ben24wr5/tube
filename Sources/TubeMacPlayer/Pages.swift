import SwiftUI

// MARK: - Home

struct HomeView: View {
    @EnvironmentObject var store: AppStore
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                YouTubeStatus(retry: { store.loadFeed(force: true) })
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(store.categories, id: \.self) { c in
                            Chip(title: c, selected: store.category == c) { store.category = c }
                        }
                    }
                }
                if store.hasYouTube && store.category == "Your uploads" && store.data.uploads.isEmpty {
                    EmptyState(icon: "video.badge.plus", title: "No uploads yet",
                               message: "Press the upload button at the top to add a video from your Mac.")
                }
                VideoGrid(videos: store.feed)
            }
            .padding(24)
            .padding(.bottom, 120)
        }
        .onAppear { store.loadFeed() }
        .onChange(of: store.category) { _ in store.loadFeed() }
        .onChange(of: store.showSettings) { open in if !open { store.loadFeed() } }
    }
}

// MARK: - Subscriptions

struct SubscriptionsView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.theme) var theme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PageHeader(title: "Subscriptions", subtitle: "Every feature, free. No Premium, no paywalls.")
                if store.subscribedChannels.isEmpty {
                    EmptyState(icon: "play.rectangle.on.rectangle", title: "No subscriptions yet",
                               message: store.hasYouTube
                                ? "Open any YouTube video and press Subscribe. That channel's newest videos will show up here."
                                : "Subscribe to channels and their newest videos will show up here.")
                    if !store.hasYouTube {
                        Text("Channels you might like").font(.headline).foregroundStyle(theme.text)
                        channelStrip(Catalog.channels)
                    }
                } else {
                    channelStrip(store.subscribedChannels)
                    YouTubeStatus(retry: { store.loadSubscriptionsFeed() })
                    Text("Latest").font(.title3.bold()).foregroundStyle(theme.text)
                    VideoGrid(videos: latest)
                }
            }
            .padding(24)
            .padding(.bottom, 120)
        }
        .onAppear { store.loadSubscriptionsFeed() }
    }

    private var latest: [VideoItem] {
        (store.ytSubsFeed + store.allVideos.filter { store.isSubscribed($0.channelID) })
            .sorted { $0.published > $1.published }
    }

    private func channelStrip(_ list: [ChannelInfo]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 22) {
                ForEach(list) { c in
                    VStack(spacing: 8) {
                        Button { store.showChannel(c.id) } label: { ChannelAvatar(channel: c, size: 72) }
                            .buttonStyle(.plain)
                        Text(c.name).font(.system(size: 12, weight: .semibold)).foregroundStyle(theme.text).lineLimit(1)
                        SubscribeButton(channelID: c.id).controlSize(.small)
                    }
                    .frame(width: 150)
                }
            }
        }
    }
}

// MARK: - Live

struct LiveView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.theme) var theme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .center) {
                    PageHeader(title: "Live", subtitle: store.hasYouTube
                               ? "Live on YouTube right now, or go live yourself."
                               : "Watch streams as they happen, or go live yourself.")
                    Button { store.showGoLive = true } label: { Label("Go live", systemImage: "video.fill") }
                        .buttonStyle(PillButtonStyle(theme: theme, prominent: true))
                }
                YouTubeStatus(retry: { store.loadLive() })
                VideoGrid(videos: store.hasYouTube ? store.ytLive : store.liveStreams)
            }
            .padding(24)
            .padding(.bottom, 120)
        }
        .onAppear { if store.hasYouTube && store.ytLive.isEmpty { store.loadLive() } }
    }
}

// MARK: - Library pages

struct VideoListPage: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.theme) var theme
    let title: String
    let subtitle: String
    let ids: [String]
    let emptyIcon: String
    let emptyMessage: String
    var clearLabel: String? = nil
    var onClear: (() -> Void)? = nil

    var body: some View {
        let videos = ids.compactMap { store.video(id: $0) }
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    PageHeader(title: title, subtitle: subtitle)
                    if let clearLabel, let onClear, !videos.isEmpty {
                        Button(clearLabel, action: onClear).buttonStyle(PillButtonStyle(theme: theme))
                    }
                }
                if videos.isEmpty {
                    EmptyState(icon: emptyIcon, title: "Nothing here yet", message: emptyMessage)
                } else {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        ForEach(videos) { v in VideoRow(video: v, thumbWidth: 260, showDescription: true) }
                    }
                }
            }
            .padding(24)
            .padding(.bottom, 120)
        }
    }
}

struct YourVideosView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.theme) var theme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(spacing: 16) {
                    ChannelAvatar(channel: store.myChannel, size: 72)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(store.myChannel.name).font(.system(size: 26, weight: .bold)).foregroundStyle(theme.text)
                        Text("\(store.myChannel.handle) • \(store.data.uploads.count) videos")
                            .foregroundStyle(theme.secondaryText)
                    }
                    Spacer()
                    Button { store.showGoLive = true } label: { Label("Go live", systemImage: "video.fill") }
                        .buttonStyle(PillButtonStyle(theme: theme))
                    Button { store.showUpload = true } label: { Label("Upload video", systemImage: "square.and.arrow.up") }
                        .buttonStyle(PillButtonStyle(theme: theme, prominent: true))
                }
                if store.data.uploads.isEmpty {
                    EmptyState(icon: "video.badge.plus", title: "Upload your first video",
                               message: "Pick any video on your Mac. It shows up in the feed, can be searched, liked, commented on and downloaded.")
                } else {
                    VideoGrid(videos: store.data.uploads)
                }
            }
            .padding(24)
            .padding(.bottom, 120)
        }
    }
}

// MARK: - Downloads

struct DownloadsView: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var downloads: DownloadManager
    @Environment(\.theme) var theme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    PageHeader(title: "Downloads", subtitle: "Watch offline. Saved in Downloads ▸ Tube Mac Player.")
                    Button { downloads.openFolder() } label: { Label("Show in Finder", systemImage: "folder") }
                        .buttonStyle(PillButtonStyle(theme: theme))
                }

                if !downloads.jobs.isEmpty {
                    Text("In progress").font(.headline).foregroundStyle(theme.text)
                    ForEach(downloads.jobs) { job in
                        HStack(spacing: 14) {
                            Thumbnail(video: job.video, showProgress: false, cornerRadius: 8).frame(width: 140)
                            VStack(alignment: .leading, spacing: 6) {
                                Text(job.video.title).font(.system(size: 14, weight: .semibold)).foregroundStyle(theme.text)
                                switch job.state {
                                case .downloading:
                                    ProgressView(value: job.progress) { Text("Downloading • \(job.quality)") }
                                case .converting:
                                    ProgressView(value: job.progress) { Text("Converting to \(job.quality)") }
                                case .failed(let msg):
                                    Text("Failed: \(msg)").foregroundStyle(.red).font(.caption)
                                }
                            }
                            .foregroundStyle(theme.secondaryText)
                            .tint(theme.accent)
                            Spacer()
                            if job.isFailed {
                                Button("Retry") {
                                    downloads.dismiss(job)
                                    downloads.start(job.video, quality: job.quality)
                                }
                                .buttonStyle(PillButtonStyle(theme: theme))
                                Button("Dismiss") { downloads.dismiss(job) }.buttonStyle(PillButtonStyle(theme: theme))
                            } else {
                                Button("Cancel") { downloads.cancel(job) }.buttonStyle(PillButtonStyle(theme: theme))
                            }
                        }
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 12).fill(theme.surface))
                    }
                }

                if downloads.records.isEmpty && downloads.jobs.isEmpty {
                    EmptyState(icon: "arrow.down.circle", title: "No downloads yet",
                               message: "Open any video and press Download. Choose 4K, 1080p, 720p, 480p or audio only.")
                } else if !downloads.records.isEmpty {
                    Text("Saved").font(.headline).foregroundStyle(theme.text)
                    ForEach(downloads.records) { r in
                        HStack(spacing: 14) {
                            Thumbnail(video: r.asVideo, showProgress: false, cornerRadius: 8).frame(width: 180)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(r.title).font(.system(size: 15, weight: .semibold)).foregroundStyle(theme.text)
                                Text("\(store.channel(id: r.channelID).name) • \(r.quality) • \(Fmt.bytes(r.bytes))")
                                    .font(.system(size: 12)).foregroundStyle(theme.secondaryText)
                                Text("Downloaded \(Fmt.ago(r.date))").font(.system(size: 12)).foregroundStyle(theme.secondaryText)
                            }
                            Spacer()
                            Button { store.play(r.asVideo) } label: { Label("Play", systemImage: "play.fill") }
                                .buttonStyle(PillButtonStyle(theme: theme, prominent: true))
                            Button { downloads.reveal(r) } label: { Image(systemName: "folder") }
                                .buttonStyle(PillButtonStyle(theme: theme)).help("Show in Finder")
                            Button { downloads.delete(r) } label: { Image(systemName: "trash") }
                                .buttonStyle(PillButtonStyle(theme: theme)).help("Delete download")
                        }
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 12).fill(theme.surface))
                    }
                }
            }
            .padding(24)
            .padding(.bottom, 120)
        }
    }
}

// MARK: - Search results

struct SearchResultsView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.theme) var theme

    var body: some View {
        let q = store.search.trimmingCharacters(in: .whitespacesAndNewlines)
        let local = store.hasYouTube ? store.data.uploads.filter { $0.title.lowercased().contains(q.lowercased()) } : store.searchResults
        let matchedChannels = store.hasYouTube ? [] : store.channels.filter {
            $0.id != "me" && $0.name.lowercased().contains(q.lowercased())
        }
        let waiting = store.hasYouTube && store.searchedQuery != q
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(waiting ? "Press Return to search YouTube for “\(q)”" : "Results for “\(q)”")
                    .font(.title3.bold()).foregroundStyle(theme.text)

                if store.hasYouTube && !waiting {
                    YouTubeStatus(retry: { store.searchYouTube() })
                }

                ForEach(matchedChannels) { c in
                    HStack(spacing: 18) {
                        ChannelAvatar(channel: c, size: 96).frame(width: 260)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(c.name).font(.title3.bold()).foregroundStyle(theme.text)
                            Text("\(c.handle) • \(Fmt.count(store.subscriberCount(c))) subscribers")
                                .foregroundStyle(theme.secondaryText)
                            Text(c.about).foregroundStyle(theme.secondaryText).font(.caption)
                        }
                        Spacer()
                        SubscribeButton(channelID: c.id)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { store.showChannel(c.id) }
                }

                if !local.isEmpty {
                    if store.hasYouTube { Text("Your uploads").font(.headline).foregroundStyle(theme.text) }
                    LazyVStack(alignment: .leading, spacing: 16) {
                        ForEach(local) { v in VideoRow(video: v, thumbWidth: 340, showDescription: true) }
                    }
                }

                if store.hasYouTube && !waiting {
                    if !store.ytResults.isEmpty && !local.isEmpty {
                        Text("On YouTube").font(.headline).foregroundStyle(theme.text)
                    }
                    LazyVStack(alignment: .leading, spacing: 16) {
                        ForEach(store.ytResults) { v in VideoRow(video: v, thumbWidth: 340, showDescription: true) }
                    }
                    if store.ytResults.isEmpty && local.isEmpty && !store.ytLoading && store.ytError == nil {
                        EmptyState(icon: "magnifyingglass", title: "No results",
                                   message: "Try different words, or check the spelling.")
                    }
                } else if !store.hasYouTube && local.isEmpty && matchedChannels.isEmpty {
                    EmptyState(icon: "magnifyingglass", title: "No results",
                               message: "Try different words, or check the spelling.")
                }
            }
            .padding(24)
            .padding(.bottom, 120)
        }
    }
}

// MARK: - Channel page

struct ChannelView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.theme) var theme
    let channel: ChannelInfo
    @State private var tab = 0

    var body: some View {
        let vids = channel.id == "tubelive" ? store.liveStreams
            : channel.id.hasPrefix("yt:") ? (store.ytChannelVideos[channel.id] ?? [])
            : store.videos(of: channel.id)
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                RoundedRectangle(cornerRadius: 18)
                    .fill(LinearGradient(colors: [Color(hex: channel.colorHex), theme.accent.opacity(0.7), theme.surface],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(height: 150)

                HStack(spacing: 18) {
                    ChannelAvatar(channel: channel, size: 110)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(channel.name).font(.system(size: 32, weight: .bold)).foregroundStyle(theme.text)
                        Text("\(channel.handle) • \(Fmt.count(store.subscriberCount(channel))) subscribers • \(vids.count) videos")
                            .foregroundStyle(theme.secondaryText)
                        Text(channel.about).lineLimit(3).foregroundStyle(theme.secondaryText)
                        SubscribeButton(channelID: channel.id).padding(.top, 4)
                    }
                    Spacer()
                }

                Picker("", selection: $tab) {
                    Text("Videos").tag(0)
                    Text("Popular").tag(1)
                    Text("About").tag(2)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 300)

                switch tab {
                case 0: VideoGrid(videos: vids.sorted { $0.published > $1.published })
                case 1: VideoGrid(videos: vids.sorted { $0.views > $1.views })
                default:
                    VStack(alignment: .leading, spacing: 8) {
                        Text("About").font(.headline).foregroundStyle(theme.text)
                        Text(channel.about).foregroundStyle(theme.text)
                        Text("\(Fmt.count(vids.reduce(0) { $0 + $1.views })) total views").foregroundStyle(theme.secondaryText)
                    }
                }
            }
            .padding(24)
            .padding(.bottom, 120)
        }
        .onAppear { store.loadChannelPage(channel.id) }
        .onChange(of: channel.id) { id in store.loadChannelPage(id) }
    }
}
