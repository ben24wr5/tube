import Foundation

/// Loading real YouTube videos, channels and comments into the app.
extension AppStore {
    var hasYouTube: Bool { !data.youtubeKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var regionCode: String {
        let r = data.region.trimmingCharacters(in: .whitespaces).uppercased()
        if r.count == 2 { return r }
        return (Locale.current as NSLocale).countryCode ?? "GB"
    }

    var youtube: YouTubeService {
        YouTubeService(key: data.youtubeKey.trimmingCharacters(in: .whitespacesAndNewlines), region: regionCode)
    }

    /// Remembers YouTube videos you interact with so History, Liked and Watch later still work next launch.
    func keep(_ v: VideoItem) {
        guard v.isYouTube else { return }
        data.savedVideos[v.id] = v
        if data.savedVideos.count > 600 {
            let wanted = Set(data.history.prefix(300)).union(data.liked).union(data.watchLater)
            data.savedVideos = data.savedVideos.filter { wanted.contains($0.key) }
        }
    }

    private func remember(_ vids: [VideoItem]) {
        for v in vids { ytCache[v.id] = v }
    }

    /// Runs a YouTube request with the loading spinner and a friendly error if it fails.
    private func load(_ work: @escaping (YouTubeService) async throws -> Void) {
        guard hasYouTube else { return }
        let service = youtube
        ytLoading = true
        ytError = nil
        Task {
            do {
                try await work(service)
                await MainActor.run { self.ytLoading = false }
            } catch {
                let message = (error as? URLError)?.code == .notConnectedToInternet
                    ? "You're offline. Connect to the internet to see YouTube videos."
                    : error.localizedDescription
                await MainActor.run {
                    self.ytLoading = false
                    self.ytError = message
                }
            }
        }
    }

    private func fetchChannels(for vids: [VideoItem], using service: YouTubeService) async {
        let missing = Set(vids.map { $0.channelID }).filter { $0.hasPrefix("yt:") }
        let known = await MainActor.run { Set(self.ytChannels.keys) }
        let ids = missing.subtracting(known).map { String($0.dropFirst(3)) }
        guard !ids.isEmpty, let list = try? await service.channels(ids: ids) else { return }
        await MainActor.run { for c in list { self.ytChannels[c.id] = c } }
    }

    // MARK: Home feed

    func loadFeed(force: Bool = false) {
        guard hasYouTube else { return }
        let cat = category
        if cat == "Live" { loadLive(); return }
        if cat == "Your uploads" { return }
        let key = cat + "|" + regionCode + "|" + data.youtubeKey
        if !force && feedLoadedFor == key && !ytFeed.isEmpty { return }
        let categoryID = YouTubeService.categories.first { $0.name == cat }?.id
        load { s in
            let vids = try await s.popular(categoryID: categoryID)
            await MainActor.run {
                self.remember(vids)
                self.ytFeed = vids
                self.feedLoadedFor = key
            }
            await self.fetchChannels(for: vids, using: s)
        }
    }

    func loadLive() {
        load { s in
            let vids = try await s.search("", liveOnly: true)
            await MainActor.run { self.remember(vids); self.ytLive = vids }
            await self.fetchChannels(for: vids, using: s)
        }
    }

    // MARK: Search

    func searchYouTube() {
        let q = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard hasYouTube, !q.isEmpty else { return }
        searchedQuery = q
        ytResults = []
        load { s in
            let vids = try await s.search(q)
            await MainActor.run {
                guard self.searchedQuery == q else { return }
                self.remember(vids)
                self.ytResults = vids
            }
            await self.fetchChannels(for: vids, using: s)
        }
    }

    // MARK: Channels

    func loadChannelPage(_ id: String) {
        guard id.hasPrefix("yt:") else { return }
        let raw = String(id.dropFirst(3))
        load { s in
            var info = await MainActor.run { self.ytChannels[id] }
            if info?.uploadsPlaylist == nil {
                info = try await s.channels(ids: [raw]).first
                if let info { await MainActor.run { self.ytChannels[id] = info; self.openChannel = self.openChannel?.id == id ? info : self.openChannel } }
            }
            guard let playlist = info?.uploadsPlaylist else { return }
            let vids = try await s.uploads(playlistID: playlist)
            await MainActor.run { self.remember(vids); self.ytChannelVideos[id] = vids }
        }
    }

    /// Newest videos from every YouTube channel you subscribe to.
    func loadSubscriptionsFeed() {
        let subs = data.subscriptions.filter { $0.hasPrefix("yt:") }
        guard !subs.isEmpty else { ytSubsFeed = []; return }
        load { s in
            let have = await MainActor.run { self.ytChannels }
            var infos = subs.compactMap { have[$0] }.filter { $0.uploadsPlaylist != nil }
            let missing = subs.filter { id in !infos.contains { $0.id == id } }.map { String($0.dropFirst(3)) }
            if !missing.isEmpty {
                let fetched = try await s.channels(ids: missing)
                infos += fetched
                await MainActor.run { for c in fetched { self.ytChannels[c.id] = c } }
            }
            var all: [VideoItem] = []
            for info in infos.prefix(25) {
                if let p = info.uploadsPlaylist, let vids = try? await s.uploads(playlistID: p, max: 8) { all += vids }
            }
            let sorted = all.sorted { $0.published > $1.published }
            await MainActor.run { self.remember(sorted); self.ytSubsFeed = sorted }
        }
    }

    // MARK: Comments

    func loadComments(for v: VideoItem) {
        guard let id = v.youtubeID, hasYouTube, ytComments[v.id] == nil else { return }
        let service = youtube
        ytComments[v.id] = []
        Task {
            let list = (try? await service.comments(videoID: id)) ?? []
            await MainActor.run { self.ytComments[v.id] = list }
        }
    }

    func testYouTubeKey() {
        guard hasYouTube else { showToast("Paste your YouTube API key first"); return }
        let service = youtube
        Task {
            do {
                try await service.test()
                await MainActor.run {
                    self.showToast("YouTube connected ✓")
                    self.feedLoadedFor = ""
                    self.category = "All"
                    self.loadFeed(force: true)
                }
            } catch {
                await MainActor.run { self.showToast(error.localizedDescription) }
            }
        }
    }
}
