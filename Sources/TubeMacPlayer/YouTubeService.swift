import Foundation

enum YouTubeError: LocalizedError {
    case noKey
    case api(String)

    var errorDescription: String? {
        switch self {
        case .noKey: return "Add your YouTube API key in Settings to see real YouTube videos."
        case .api(let message): return message
        }
    }
}

/// Talks to the official YouTube Data API v3.
struct YouTubeService {
    let key: String
    let region: String

    static let categories: [(name: String, id: String?)] = [
        ("All", nil), ("Music", "10"), ("Gaming", "20"), ("Sports", "17"), ("News", "25"),
        ("Comedy", "23"), ("Entertainment", "24"), ("Film", "1"), ("Tech", "28"), ("Education", "27")
    ]

    static let categoryNames: [String: String] = [
        "1": "Film", "2": "Cars", "10": "Music", "15": "Animals", "17": "Sports", "19": "Travel",
        "20": "Gaming", "22": "Vlogs", "23": "Comedy", "24": "Entertainment", "25": "News",
        "26": "How-to", "27": "Education", "28": "Tech", "29": "Activism"
    ]

    // MARK: Requests

    private func get(_ path: String, _ params: [String: String]) async throws -> [String: Any] {
        guard !key.isEmpty else { throw YouTubeError.noKey }
        var c = URLComponents(string: "https://www.googleapis.com/youtube/v3/" + path)!
        c.queryItems = params.map { URLQueryItem(name: $0.key, value: $0.value) } + [URLQueryItem(name: "key", value: key)]
        let (data, response) = try await URLSession.shared.data(from: c.url!)
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
            let raw = ((json["error"] as? [String: Any])?["message"] as? String) ?? "YouTube error \(http.statusCode)"
            throw YouTubeError.api(Self.friendly(raw))
        }
        return json
    }

    static func friendly(_ message: String) -> String {
        let plain = message.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        let lower = plain.lowercased()
        if lower.contains("api key not valid") || lower.contains("api_key_invalid") {
            return "That YouTube API key isn't valid. Check it in Settings."
        }
        if lower.contains("has not been used") || lower.contains("is disabled") {
            return "Turn on “YouTube Data API v3” for your key in Google Cloud, then try again."
        }
        if lower.contains("quota") {
            return "Today's YouTube limit for this key is used up. It resets at midnight Pacific time."
        }
        return plain
    }

    // MARK: Videos

    func test() async throws {
        _ = try await get("videos", ["part": "id", "chart": "mostPopular", "regionCode": region, "maxResults": "1"])
    }

    func popular(categoryID: String?) async throws -> [VideoItem] {
        var p = ["part": "snippet,contentDetails,statistics", "chart": "mostPopular",
                 "regionCode": region, "maxResults": "40"]
        if let categoryID { p["videoCategoryId"] = categoryID }
        return parseVideos(try await get("videos", p))
    }

    func search(_ query: String, liveOnly: Bool = false) async throws -> [VideoItem] {
        var p = ["part": "snippet", "type": "video", "maxResults": "30", "regionCode": region, "safeSearch": "moderate"]
        if !query.isEmpty { p["q"] = query }
        if liveOnly { p["eventType"] = "live"; p["order"] = "viewCount" }
        let json = try await get("search", p)
        let ids = (json["items"] as? [[String: Any]] ?? []).compactMap { ($0["id"] as? [String: Any])?["videoId"] as? String }
        return try await videos(ids: ids)
    }

    func videos(ids: [String]) async throws -> [VideoItem] {
        let wanted = Array(ids.prefix(50))
        guard !wanted.isEmpty else { return [] }
        let json = try await get("videos", ["part": "snippet,contentDetails,statistics,liveStreamingDetails",
                                            "id": wanted.joined(separator: ",")])
        var order: [String: Int] = [:]
        for (i, id) in wanted.enumerated() where order[id] == nil { order[id] = i }
        return parseVideos(json).sorted { (order[$0.youtubeID ?? ""] ?? 0) < (order[$1.youtubeID ?? ""] ?? 0) }
    }

    /// Newest uploads from a channel's uploads playlist.
    func uploads(playlistID: String, max: Int = 30) async throws -> [VideoItem] {
        let json = try await get("playlistItems", ["part": "contentDetails", "playlistId": playlistID, "maxResults": "\(max)"])
        let ids = (json["items"] as? [[String: Any]] ?? []).compactMap { ($0["contentDetails"] as? [String: Any])?["videoId"] as? String }
        return try await videos(ids: ids)
    }

    // MARK: Channels

    func channels(ids: [String]) async throws -> [ChannelInfo] {
        let wanted = Array(Set(ids)).prefix(50)
        guard !wanted.isEmpty else { return [] }
        let json = try await get("channels", ["part": "snippet,statistics,contentDetails", "id": wanted.joined(separator: ",")])
        return (json["items"] as? [[String: Any]] ?? []).compactMap { item in
            guard let id = item["id"] as? String, let snip = item["snippet"] as? [String: Any] else { return nil }
            let stats = item["statistics"] as? [String: Any] ?? [:]
            let uploads = ((item["contentDetails"] as? [String: Any])?["relatedPlaylists"] as? [String: Any])?["uploads"] as? String
            let thumbs = snip["thumbnails"] as? [String: Any] ?? [:]
            let avatar = Self.thumbURL(thumbs, ["medium", "high", "default"])
            let palette = ["#E5484D", "#F76B15", "#46A758", "#12A594", "#0090FF", "#6E56CF", "#D6409F"]
            return ChannelInfo(id: "yt:" + id,
                               name: snip["title"] as? String ?? "YouTube channel",
                               handle: snip["customUrl"] as? String ?? "",
                               colorHex: palette[stableHash(id) % palette.count],
                               subscribers: Int(stats["subscriberCount"] as? String ?? "") ?? 0,
                               about: snip["description"] as? String ?? "",
                               avatarURL: avatar,
                               uploadsPlaylist: uploads)
        }
    }

    // MARK: Comments

    func comments(videoID: String) async throws -> [VideoComment] {
        let json = try await get("commentThreads", ["part": "snippet", "videoId": videoID, "maxResults": "25",
                                                    "order": "relevance", "textFormat": "plainText"])
        return (json["items"] as? [[String: Any]] ?? []).compactMap { item in
            guard let top = ((item["snippet"] as? [String: Any])?["topLevelComment"] as? [String: Any])?["snippet"] as? [String: Any]
            else { return nil }
            var author = top["authorDisplayName"] as? String ?? "Someone"
            if author.hasPrefix("@") { author.removeFirst() }
            return VideoComment(id: "ytc:" + (item["id"] as? String ?? UUID().uuidString),
                                videoID: "yt:" + videoID, author: author,
                                text: top["textOriginal"] as? String ?? top["textDisplay"] as? String ?? "",
                                date: Self.date(top["publishedAt"] as? String),
                                baseLikes: top["likeCount"] as? Int ?? 0, isMine: false)
        }
    }

    // MARK: Parsing

    private func parseVideos(_ json: [String: Any]) -> [VideoItem] {
        (json["items"] as? [[String: Any]] ?? []).compactMap { item in
            guard let id = item["id"] as? String, let snip = item["snippet"] as? [String: Any] else { return nil }
            let stats = item["statistics"] as? [String: Any] ?? [:]
            let details = item["contentDetails"] as? [String: Any] ?? [:]
            let liveDetails = item["liveStreamingDetails"] as? [String: Any] ?? [:]
            let isLive = (snip["liveBroadcastContent"] as? String) == "live"
            let views = isLive ? (Int(liveDetails["concurrentViewers"] as? String ?? "") ?? 0)
                               : (Int(stats["viewCount"] as? String ?? "") ?? 0)
            let channelID = snip["channelId"] as? String ?? ""
            return VideoItem(id: "yt:" + id,
                             title: snip["title"] as? String ?? "Untitled",
                             details: snip["description"] as? String ?? "",
                             channelID: "yt:" + channelID,
                             streamURL: URL(string: "https://www.youtube.com/watch?v=" + id)!,
                             downloadURL: nil,
                             thumbnailURL: Self.thumbURL(snip["thumbnails"] as? [String: Any] ?? [:],
                                                         ["maxres", "standard", "high", "medium", "default"]),
                             duration: Self.duration(details["duration"] as? String ?? ""),
                             views: views,
                             published: Self.date(snip["publishedAt"] as? String),
                             category: Self.categoryNames[snip["categoryId"] as? String ?? ""] ?? (isLive ? "Live" : "YouTube"),
                             isLive: isLive,
                             baseLikes: Int(stats["likeCount"] as? String ?? "") ?? 0,
                             youtubeID: id,
                             channelName: snip["channelTitle"] as? String)
        }
    }

    static func thumbURL(_ thumbs: [String: Any], _ order: [String]) -> URL? {
        for k in order {
            if let s = (thumbs[k] as? [String: Any])?["url"] as? String, let u = URL(string: s) { return u }
        }
        return nil
    }

    static func date(_ s: String?) -> Date {
        guard let s else { return Date() }
        let f = ISO8601DateFormatter()
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: s) ?? Date()
    }

    /// "PT1H2M3S" → 3723 seconds
    static func duration(_ iso: String) -> Double {
        var total = 0.0, number = ""
        var inTime = false
        for ch in iso {
            switch ch {
            case "P": continue
            case "T": inTime = true
            case "0"..."9", ".": number.append(ch)
            default:
                let n = Double(number) ?? 0
                number = ""
                switch ch {
                case "D": total += n * 86_400
                case "H": total += n * 3_600
                case "M": total += inTime ? n * 60 : n * 2_592_000
                case "S": total += n
                case "W": total += n * 604_800
                default: break
                }
            }
        }
        return total
    }
}
