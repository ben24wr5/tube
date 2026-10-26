import SwiftUI
import AVFoundation
import AppKit

enum SidebarItem: String, CaseIterable, Identifiable, Hashable {
    case home, subscriptions, live, history, liked, watchLater, yourVideos, downloads
    var id: String { rawValue }
    var title: String {
        switch self {
        case .home: return "Home"
        case .subscriptions: return "Subscriptions"
        case .live: return "Live"
        case .history: return "History"
        case .liked: return "Liked videos"
        case .watchLater: return "Watch later"
        case .yourVideos: return "Your videos"
        case .downloads: return "Downloads"
        }
    }
    var icon: String {
        switch self {
        case .home: return "house.fill"
        case .subscriptions: return "play.rectangle.on.rectangle.fill"
        case .live: return "dot.radiowaves.left.and.right"
        case .history: return "clock.arrow.circlepath"
        case .liked: return "hand.thumbsup.fill"
        case .watchLater: return "clock.fill"
        case .yourVideos: return "person.crop.rectangle.fill"
        case .downloads: return "arrow.down.circle.fill"
        }
    }
}

final class AppStore: ObservableObject {
    @Published var data: UserData { didSet { scheduleSave() } }

    // Navigation
    @Published var section: SidebarItem = .home
    @Published var search = ""
    @Published var category = "All"
    @Published var nowPlaying: VideoItem?
    @Published var watchOpen = false
    @Published var openChannel: ChannelInfo?

    // Sheets & messages
    @Published var showSettings = false
    @Published var showUpload = false
    @Published var showGoLive = false
    @Published var toast: String?
    @Published var upNextCountdown: Int?

    // Real YouTube
    @Published var ytFeed: [VideoItem] = []
    @Published var ytLive: [VideoItem] = []
    @Published var ytResults: [VideoItem] = []
    @Published var ytSubsFeed: [VideoItem] = []
    @Published var ytChannels: [String: ChannelInfo] = [:]
    @Published var ytChannelVideos: [String: [VideoItem]] = [:]
    @Published var ytComments: [String: [VideoComment]] = [:]
    @Published var ytLoading = false
    @Published var ytError: String?
    @Published var searchedQuery = ""
    var ytCache: [String: VideoItem] = [:]
    var feedLoadedFor = ""

    let catalog = Catalog.videos
    let liveStreams = Catalog.live

    private var saveWork: DispatchWorkItem?
    private var toastWork: DispatchWorkItem?
    private var countdownTimer: Timer?

    init() {
        if let raw = try? Data(contentsOf: AppPaths.userData),
           let saved = try? JSONDecoder().decode(UserData.self, from: raw) {
            data = saved
        } else {
            data = UserData()
        }
    }

    // MARK: Saving

    private func scheduleSave() {
        saveWork?.cancel()
        let snapshot = data
        let work = DispatchWorkItem {
            if let raw = try? JSONEncoder().encode(snapshot) {
                try? raw.write(to: AppPaths.userData, options: .atomic)
            }
        }
        saveWork = work
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    // MARK: Theme

    var theme: AppTheme { AppTheme.all.first { $0.id == data.themeID } ?? AppTheme.all[0] }

    // MARK: Lookups

    var allVideos: [VideoItem] { data.uploads + catalog }

    func video(id: String) -> VideoItem? {
        if id.hasPrefix("yt:") { return ytCache[id] ?? data.savedVideos[id] }
        return allVideos.first { $0.id == id } ?? liveStreams.first { $0.id == id }
    }

    var myChannel: ChannelInfo {
        ChannelInfo(id: "me", name: data.displayName, handle: "@" + data.displayName.lowercased().replacingOccurrences(of: " ", with: ""),
                    colorHex: "#7B5CD6", subscribers: 0, about: "Your channel on Tube Mac Player.")
    }

    var channels: [ChannelInfo] { [myChannel] + Catalog.channels }

    func channel(id: String) -> ChannelInfo {
        if let c = channels.first(where: { $0.id == id }) { return c }
        if let c = ytChannels[id] ?? data.savedChannels[id] { return c }
        if id.hasPrefix("yt:") {
            let known = ytCache.values.first { $0.channelID == id } ?? data.savedVideos.values.first { $0.channelID == id }
            let palette = ["#E5484D", "#F76B15", "#46A758", "#12A594", "#0090FF", "#6E56CF", "#D6409F"]
            return ChannelInfo(id: id, name: known?.channelName ?? "YouTube channel", handle: "",
                               colorHex: palette[stableHash(id) % palette.count], subscribers: 0, about: "")
        }
        return myChannel
    }

    func videos(of channelID: String) -> [VideoItem] {
        allVideos.filter { $0.channelID == channelID }
    }

    var categories: [String] {
        if hasYouTube { return YouTubeService.categories.map { $0.name } + ["Live", "Your uploads"] }
        var seen: [String] = ["All"]
        for v in allVideos where !seen.contains(v.category) { seen.append(v.category) }
        seen.append("Live")
        return seen
    }

    var feed: [VideoItem] {
        if hasYouTube {
            switch category {
            case "Live": return ytLive
            case "Your uploads": return data.uploads
            default: return ytFeed
            }
        }
        switch category {
        case "All": return allVideos.sorted { $0.published > $1.published }
        case "Live": return liveStreams
        default: return allVideos.filter { $0.category == category }
        }
    }

    var searchResults: [VideoItem] {
        let words = search.lowercased().split(separator: " ").map(String.init)
        guard !words.isEmpty else { return [] }
        return (allVideos + liveStreams).filter { v in
            let hay = (v.title + " " + v.details + " " + channel(id: v.channelID).name + " " + v.category).lowercased()
            return words.allSatisfy { hay.contains($0) }
        }
    }

    func upNext(after v: VideoItem) -> [VideoItem] {
        if v.isYouTube {
            var seen = Set<String>([v.id])
            var pool: [VideoItem] = []
            for x in ytResults + (ytChannelVideos[v.channelID] ?? []) + ytFeed + ytSubsFeed where !x.isLive && !seen.contains(x.id) {
                seen.insert(x.id); pool.append(x)
            }
            return pool.filter { $0.channelID == v.channelID } + pool.filter { $0.channelID != v.channelID }
        }
        let others = allVideos.filter { $0.id != v.id }
        let same = others.filter { $0.channelID == v.channelID }
        let rest = others.filter { $0.channelID != v.channelID }
        return same + rest
    }

    var subscribedChannels: [ChannelInfo] {
        data.subscriptions.sorted().map { channel(id: $0) }
    }

    // MARK: Navigation

    func goTo(_ item: SidebarItem) {
        section = item
        watchOpen = false
        openChannel = nil
        search = ""
    }

    func play(_ v: VideoItem) {
        cancelCountdown()
        keep(v)
        nowPlaying = v
        watchOpen = true
        openChannel = nil
        data.history.removeAll { $0 == v.id }
        data.history.insert(v.id, at: 0)
        if data.history.count > 200 { data.history.removeLast(data.history.count - 200) }
    }

    func closePlayer() {
        cancelCountdown()
        nowPlaying = nil
        watchOpen = false
    }

    func showChannel(_ id: String) {
        openChannel = channel(id: id)
        watchOpen = false
        search = ""
    }

    func resumePosition(for v: VideoItem) -> Double {
        guard !v.isLive, let p = data.positions[v.id] else { return 0 }
        return (p > 5 && p < v.duration - 10) ? p : 0
    }

    func savePosition(_ id: String, _ t: Double) {
        guard t.isFinite else { return }
        data.positions[id] = t
    }

    func progress(of v: VideoItem) -> Double {
        guard v.duration > 0, let p = data.positions[v.id] else { return 0 }
        return min(1, p / v.duration)
    }

    // MARK: Autoplay

    func startCountdown() {
        guard data.autoplay, let current = nowPlaying, !current.isLive, upNext(after: current).first != nil else { return }
        cancelCountdown()
        upNextCountdown = 5
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self, let n = self.upNextCountdown else { return }
            if n <= 1 { self.playNext() } else { self.upNextCountdown = n - 1 }
        }
    }

    func cancelCountdown() {
        countdownTimer?.invalidate()
        countdownTimer = nil
        upNextCountdown = nil
    }

    func playNext() {
        cancelCountdown()
        guard let current = nowPlaying, let next = upNext(after: current).first else { return }
        play(next)
    }

    // MARK: Likes, subscriptions, watch later

    func isLiked(_ v: VideoItem) -> Bool { data.liked.contains(v.id) }
    func isDisliked(_ v: VideoItem) -> Bool { data.disliked.contains(v.id) }
    func likeCount(_ v: VideoItem) -> Int { v.baseLikes + (isLiked(v) ? 1 : 0) }

    func toggleLike(_ v: VideoItem) {
        keep(v)
        if data.liked.contains(v.id) { data.liked.remove(v.id) }
        else { data.liked.insert(v.id); data.disliked.remove(v.id) }
    }

    func toggleDislike(_ v: VideoItem) {
        if data.disliked.contains(v.id) { data.disliked.remove(v.id) }
        else { data.disliked.insert(v.id); data.liked.remove(v.id) }
    }

    func isSubscribed(_ channelID: String) -> Bool { data.subscriptions.contains(channelID) }

    func toggleSubscribe(_ channelID: String) {
        if data.subscriptions.contains(channelID) {
            data.subscriptions.remove(channelID)
            data.notifications.remove(channelID)
            showToast("Subscription removed")
        } else {
            if channelID.hasPrefix("yt:") { data.savedChannels[channelID] = channel(id: channelID) }
            data.subscriptions.insert(channelID)
            showToast("Subscribed — free, always")
        }
    }

    func subscriberCount(_ c: ChannelInfo) -> Int { c.subscribers + (isSubscribed(c.id) ? 1 : 0) }

    func toggleWatchLater(_ v: VideoItem) {
        keep(v)
        if let i = data.watchLater.firstIndex(of: v.id) {
            data.watchLater.remove(at: i)
            showToast("Removed from Watch later")
        } else {
            data.watchLater.insert(v.id, at: 0)
            showToast("Saved to Watch later")
        }
    }

    func copyLink(_ v: VideoItem) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString((v.downloadURL ?? v.streamURL).absoluteString, forType: .string)
        showToast("Link copied")
    }

    // MARK: Comments

    func comments(for v: VideoItem, newestFirst: Bool) -> [VideoComment] {
        let mine = data.comments.filter { $0.videoID == v.id }
        var seeded: [VideoComment] = []
        if v.isYouTube {
            seeded = (ytComments[v.id] ?? []).filter { !data.hiddenComments.contains($0.id) }
        } else if !v.isLocal {
            let h = stableHash(v.id)
            let pool = Catalog.commentPool
            for i in 0..<5 {
                let p = pool[(h + i * 5) % pool.count]
                let id = "\(v.id)-seed-\(i)"
                guard !data.hiddenComments.contains(id) else { continue }
                seeded.append(VideoComment(id: id, videoID: v.id, author: p.0, text: p.1,
                                           date: v.published.addingTimeInterval(Double(((h >> i) % 72 + 1) * 3600)),
                                           baseLikes: (h >> (i + 2)) % 2400 + 3, isMine: false))
            }
        }
        let all = mine + seeded
        if newestFirst { return all.sorted { $0.date > $1.date } }
        return all.sorted { a, b in
            if a.isMine != b.isMine { return a.isMine }
            return commentLikes(a) > commentLikes(b)
        }
    }

    func commentLikes(_ c: VideoComment) -> Int { c.baseLikes + (data.likedComments.contains(c.id) ? 1 : 0) }

    func addComment(_ text: String, to v: VideoItem) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        data.comments.insert(VideoComment(id: UUID().uuidString, videoID: v.id, author: data.displayName,
                                          text: t, date: Date(), baseLikes: 0, isMine: true), at: 0)
    }

    func toggleCommentLike(_ c: VideoComment) {
        if data.likedComments.contains(c.id) { data.likedComments.remove(c.id) } else { data.likedComments.insert(c.id) }
    }

    func deleteComment(_ c: VideoComment) {
        if c.isMine { data.comments.removeAll { $0.id == c.id } } else { data.hiddenComments.insert(c.id) }
    }

    // MARK: Uploads

    /// Copies a video into the app, makes a thumbnail and publishes it to your channel.
    func importVideo(from source: URL, title: String, details: String, category: String) async throws {
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }

        let id = "local-" + UUID().uuidString
        let ext = source.pathExtension.isEmpty ? "mov" : source.pathExtension
        let dest = AppPaths.uploads.appendingPathComponent(id + "." + ext)
        try FileManager.default.copyItem(at: source, to: dest)

        let asset = AVURLAsset(url: dest)
        let duration = (try? await asset.load(.duration).seconds) ?? 0

        var thumbURL: URL?
        let gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        gen.maximumSize = CGSize(width: 1280, height: 720)
        let at = CMTime(seconds: min(2, max(0, duration / 3)), preferredTimescale: 600)
        if let cg = (try? await gen.image(at: at))?.image {
            let rep = NSBitmapImageRep(cgImage: cg)
            if let jpg = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.85]) {
                let t = AppPaths.uploads.appendingPathComponent(id + ".jpg")
                try? jpg.write(to: t)
                thumbURL = t
            }
        }

        let cleanTitle = title.trimmingCharacters(in: .whitespaces).isEmpty
            ? source.deletingPathExtension().lastPathComponent : title
        let item = VideoItem(id: id, title: cleanTitle, details: details, channelID: "me",
                             streamURL: dest, downloadURL: dest, thumbnailURL: thumbURL,
                             duration: duration.isFinite ? duration : 0, views: 0, published: Date(),
                             category: category, isLocal: true)
        await MainActor.run {
            self.data.uploads.insert(item, at: 0)
            self.showToast("“\(cleanTitle)” is now live on your channel")
        }
    }

    func deleteUpload(_ v: VideoItem) {
        guard v.isLocal else { return }
        if nowPlaying?.id == v.id { closePlayer() }
        try? FileManager.default.removeItem(at: v.streamURL)
        if let t = v.thumbnailURL { try? FileManager.default.removeItem(at: t) }
        data.uploads.removeAll { $0.id == v.id }
        showToast("Video deleted")
    }

    // MARK: Toast

    func showToast(_ message: String) {
        toastWork?.cancel()
        withAnimation(.spring(response: 0.3)) { toast = message }
        let work = DispatchWorkItem { [weak self] in withAnimation { self?.toast = nil } }
        toastWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2, execute: work)
    }
}
