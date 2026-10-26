import SwiftUI
import AppKit

// MARK: - Thumbnails

struct Thumbnail: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.theme) var theme
    let video: VideoItem
    var showProgress = true
    var cornerRadius: CGFloat = 12

    var body: some View {
        Color.clear
            .aspectRatio(16 / 9, contentMode: .fit)
            .background(theme.surfaceHigh)
            .overlay { image }
            .overlay(alignment: .bottomTrailing) { badge.padding(6) }
            .overlay(alignment: .bottom) {
                if showProgress, store.progress(of: video) > 0.02 {
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            Rectangle().fill(.white.opacity(0.35))
                            Rectangle().fill(theme.accent).frame(width: g.size.width * store.progress(of: video))
                        }
                    }
                    .frame(height: 4)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    @ViewBuilder private var image: some View {
        if let url = video.thumbnailURL {
            if url.isFileURL {
                if let img = NSImage(contentsOf: url) {
                    Image(nsImage: img).resizable().scaledToFill()
                } else { placeholder }
            } else {
                AsyncImage(url: url, transaction: Transaction(animation: .easeOut(duration: 0.25))) { phase in
                    if let image = phase.image { image.resizable().scaledToFill() } else { placeholder }
                }
            }
        } else { placeholder }
    }

    private var placeholder: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: store.channel(id: video.channelID).colorHex).opacity(0.85), theme.surfaceHigh],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            Image(systemName: video.isLive ? "dot.radiowaves.left.and.right" : "play.rectangle.fill")
                .font(.system(size: 30))
                .foregroundStyle(.white.opacity(0.85))
        }
    }

    @ViewBuilder private var badge: some View {
        if video.isLive {
            LiveBadge()
        } else if video.duration > 0 {
            Text(Fmt.time(video.duration))
                .font(.system(size: 11, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(.white)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(RoundedRectangle(cornerRadius: 4).fill(.black.opacity(0.8)))
        }
    }
}

// MARK: - App logo (your gem logo, shown next to the app name)

struct AppLogo: View {
    var size: CGFloat = 30
    private static let image: NSImage? = Bundle.main.url(forResource: "Logo", withExtension: "png")
        .flatMap { NSImage(contentsOf: $0) }

    var body: some View {
        if let img = Self.image {
            Image(nsImage: img)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: size, height: size)
                .shadow(color: .red.opacity(0.35), radius: 4)
        } else {
            Circle().fill(Color(hex: "#C8101E")).frame(width: size, height: size)
                .overlay(Image(systemName: "play.fill").font(.system(size: size * 0.38, weight: .bold)).foregroundStyle(.white))
        }
    }
}

// MARK: - Channel avatar

struct ChannelAvatar: View {
    let channel: ChannelInfo
    var size: CGFloat = 36

    var body: some View {
        Circle()
            .fill(LinearGradient(colors: [Color(hex: channel.colorHex), Color(hex: channel.colorHex).opacity(0.6)],
                                 startPoint: .top, endPoint: .bottom))
            .frame(width: size, height: size)
            .overlay(Text(String(channel.name.prefix(1)).uppercased())
                .font(.system(size: size * 0.45, weight: .bold))
                .foregroundStyle(.white))
            .overlay {
                if let url = channel.avatarURL {
                    AsyncImage(url: url) { phase in
                        if let image = phase.image { image.resizable().scaledToFill() } else { Color.clear }
                    }
                    .frame(width: size, height: size)
                    .clipShape(Circle())
                }
            }
    }
}

// MARK: - Subscribe button (free, always)

struct SubscribeButton: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.theme) var theme
    let channelID: String

    var body: some View {
        if channelID == "me" {
            EmptyView()
        } else if store.isSubscribed(channelID) {
            HStack(spacing: 6) {
                Button {
                    store.toggleSubscribe(channelID)
                } label: { Label("Subscribed", systemImage: "checkmark") }
                .buttonStyle(PillButtonStyle(theme: theme))
                Button {
                    if store.data.notifications.contains(channelID) { store.data.notifications.remove(channelID) }
                    else { store.data.notifications.insert(channelID); store.showToast("You'll be notified about new videos") }
                } label: {
                    Image(systemName: store.data.notifications.contains(channelID) ? "bell.fill" : "bell")
                }
                .buttonStyle(PillButtonStyle(theme: theme))
                .help("Notifications")
            }
        } else {
            Button("Subscribe") { store.toggleSubscribe(channelID) }
                .buttonStyle(PillButtonStyle(theme: theme, prominent: true))
        }
    }
}

// MARK: - Video card (grid)

struct VideoCard: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var downloads: DownloadManager
    @Environment(\.theme) var theme
    let video: VideoItem
    @State private var hover = false

    var body: some View {
        let channel = store.channel(id: video.channelID)
        VStack(alignment: .leading, spacing: 10) {
            Thumbnail(video: video)
                .scaleEffect(hover ? 1.02 : 1)
                .shadow(color: .black.opacity(hover ? 0.3 : 0), radius: 12, y: 6)
            HStack(alignment: .top, spacing: 10) {
                Button { store.showChannel(channel.id) } label: { ChannelAvatar(channel: channel) }
                    .buttonStyle(.plain)
                VStack(alignment: .leading, spacing: 3) {
                    Text(video.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(theme.text)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text(channel.name).font(.system(size: 12)).foregroundStyle(theme.secondaryText)
                    Text(metaLine).font(.system(size: 12)).foregroundStyle(theme.secondaryText)
                }
                Spacer(minLength: 0)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { store.play(video) }
        .onHover { h in withAnimation(.easeOut(duration: 0.15)) { hover = h } }
        .contextMenu { VideoMenu(video: video) }
    }

    private var metaLine: String {
        if video.isLive { return "\(Fmt.count(video.views)) watching" }
        return "\(Fmt.count(video.views)) views • \(Fmt.ago(video.published))"
    }
}

/// Right-click menu for any video.
struct VideoMenu: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var downloads: DownloadManager
    let video: VideoItem

    var body: some View {
        Button("Play") { store.play(video) }
        if !video.isLive {
            Button(store.data.watchLater.contains(video.id) ? "Remove from Watch later" : "Save to Watch later") {
                store.toggleWatchLater(video)
            }
            Button("Download (\(store.data.downloadQuality))") {
                downloads.start(video, quality: store.data.downloadQuality)
                store.showToast("Downloading in \(store.data.downloadQuality)…")
            }
        }
        Button("Copy link") { store.copyLink(video) }
        Button("Go to channel") { store.showChannel(video.channelID) }
        if video.isLocal && video.channelID == "me" {
            Divider()
            Button("Delete video", role: .destructive) { store.deleteUpload(video) }
        }
    }
}

// MARK: - Video row (lists, search, up next)

struct VideoRow: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.theme) var theme
    let video: VideoItem
    var thumbWidth: CGFloat = 168
    var showDescription = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Thumbnail(video: video, cornerRadius: 10).frame(width: thumbWidth)
            VStack(alignment: .leading, spacing: 4) {
                Text(video.title)
                    .font(.system(size: showDescription ? 16 : 13, weight: .semibold))
                    .foregroundStyle(theme.text)
                    .lineLimit(2)
                Text(meta).font(.system(size: 12)).foregroundStyle(theme.secondaryText)
                HStack(spacing: 6) {
                    if showDescription { ChannelAvatar(channel: store.channel(id: video.channelID), size: 22) }
                    Text(store.channel(id: video.channelID).name).font(.system(size: 12)).foregroundStyle(theme.secondaryText)
                }
                if showDescription {
                    Text(video.details).font(.system(size: 12)).foregroundStyle(theme.secondaryText).lineLimit(2)
                }
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .onTapGesture { store.play(video) }
        .contextMenu { VideoMenu(video: video) }
    }

    private var meta: String {
        video.isLive ? "\(Fmt.count(video.views)) watching" : "\(Fmt.count(video.views)) views • \(Fmt.ago(video.published))"
    }
}

// MARK: - YouTube connection status (setup tip, loading, errors)

struct YouTubeStatus: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.theme) var theme
    let retry: () -> Void

    var body: some View {
        if !store.hasYouTube {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "play.rectangle.fill").font(.system(size: 26)).foregroundStyle(theme.accent)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Turn on real YouTube videos").font(.headline).foregroundStyle(theme.text)
                    Text("Open Settings at the bottom left and paste your free YouTube API key. Then Home, Search and Live show real YouTube videos.")
                        .font(.system(size: 13)).foregroundStyle(theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 12).fill(theme.surface))
        } else if store.ytLoading {
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text("Loading YouTube…").foregroundStyle(theme.secondaryText)
            }
        } else if let err = store.ytError {
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                Text(err).foregroundStyle(theme.text).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Button("Try again", action: retry).buttonStyle(PillButtonStyle(theme: theme))
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 12).fill(theme.surface))
        }
    }
}

// MARK: - Layout helpers

struct VideoGrid: View {
    let videos: [VideoItem]
    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 270, maximum: 420), spacing: 18, alignment: .top)],
                  alignment: .leading, spacing: 28) {
            ForEach(videos) { VideoCard(video: $0) }
        }
    }
}

struct PageHeader: View {
    @Environment(\.theme) var theme
    let title: String
    var subtitle: String? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 28, weight: .bold)).foregroundStyle(theme.text)
            if let subtitle { Text(subtitle).foregroundStyle(theme.secondaryText) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct EmptyState: View {
    @Environment(\.theme) var theme
    let icon: String
    let title: String
    let message: String
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 44)).foregroundStyle(theme.accent)
            Text(title).font(.title3.bold()).foregroundStyle(theme.text)
            Text(message).foregroundStyle(theme.secondaryText).multilineTextAlignment(.center).frame(maxWidth: 420)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }
}

struct Chip: View {
    @Environment(\.theme) var theme
    let title: String
    let selected: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .foregroundStyle(selected ? theme.onAccent : theme.text)
                .background(RoundedRectangle(cornerRadius: 8).fill(selected ? theme.accent : theme.surfaceHigh))
        }
        .buttonStyle(.plain)
    }
}

/// Little sparkles drawn over the Diamond theme.
struct SparkleLayer: View {
    var body: some View {
        GeometryReader { g in
            ForEach(0..<18, id: \.self) { i in
                let x = CGFloat((i * 137) % 100) / 100 * g.size.width
                let y = CGFloat((i * 71 + 13) % 100) / 100 * g.size.height
                Image(systemName: i % 3 == 0 ? "sparkle" : "plus")
                    .font(.system(size: CGFloat(6 + (i % 4) * 3), weight: .light))
                    .foregroundStyle(Color(hex: "#7FC3EA").opacity(0.35))
                    .position(x: x, y: y)
            }
        }
        .allowsHitTesting(false)
    }
}
