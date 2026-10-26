import Foundation
import SwiftUI

// MARK: - Core models

struct ChannelInfo: Identifiable, Codable, Hashable {
    var id: String
    var name: String
    var handle: String
    var colorHex: String
    var subscribers: Int
    var about: String
    var avatarURL: URL? = nil
    var uploadsPlaylist: String? = nil
}

struct VideoItem: Identifiable, Codable, Hashable {
    var id: String
    var title: String
    var details: String
    var channelID: String
    var streamURL: URL          // what the player plays (MP4 file or HLS stream)
    var downloadURL: URL?       // full-quality source used for downloads
    var thumbnailURL: URL?
    var duration: Double        // seconds
    var views: Int
    var published: Date
    var category: String
    var isLive: Bool = false
    var isLocal: Bool = false
    var baseLikes: Int = 0
    var youtubeID: String? = nil      // set for real YouTube videos
    var channelName: String? = nil

    var isYouTube: Bool { youtubeID != nil }
    var canDownload: Bool { downloadURL != nil && !isLive }
}

struct VideoComment: Identifiable, Codable, Hashable {
    var id: String
    var videoID: String
    var author: String
    var text: String
    var date: Date
    var baseLikes: Int
    var isMine: Bool
}

// MARK: - Saved user data (everything is free, nothing is locked)

struct UserData: Codable {
    var themeID = "midnight"
    var displayName = "You"
    var autoplay = true
    var defaultSpeed: Float = 1
    var playbackQuality = "Auto"
    var downloadQuality = "1080p"
    var liked: Set<String> = []
    var disliked: Set<String> = []
    var likedComments: Set<String> = []
    var hiddenComments: Set<String> = []
    var subscriptions: Set<String> = []
    var notifications: Set<String> = []
    var watchLater: [String] = []
    var history: [String] = []
    var positions: [String: Double] = [:]
    var comments: [VideoComment] = []
    var uploads: [VideoItem] = []
    var rtmpURL = ""
    var streamKey = ""
    var youtubeKey = ""
    var region = ""
    var savedVideos: [String: VideoItem] = [:]     // YouTube videos you watched, liked or saved
    var savedChannels: [String: ChannelInfo] = [:] // YouTube channels you subscribed to
}

// MARK: - Folders

enum AppPaths {
    static func folder(_ url: URL) -> URL {
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    static var support: URL {
        folder(FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Tube Mac Player", isDirectory: true))
    }
    static var uploads: URL { folder(support.appendingPathComponent("Uploads", isDirectory: true)) }
    static var temp: URL { folder(support.appendingPathComponent("Temp", isDirectory: true)) }
    static var downloads: URL {
        folder(FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Tube Mac Player", isDirectory: true))
    }
    static var userData: URL { support.appendingPathComponent("userdata.json") }
    static var downloadRecords: URL { support.appendingPathComponent("downloads.json") }
}

// MARK: - Formatting

enum Fmt {
    static func count(_ n: Int) -> String {
        func short(_ v: Double, _ s: String) -> String {
            let txt = v >= 10 ? String(format: "%.0f", v) : String(format: "%.1f", v)
            return txt.replacingOccurrences(of: ".0", with: "") + s
        }
        if n >= 1_000_000_000 { return short(Double(n) / 1e9, "B") }
        if n >= 1_000_000 { return short(Double(n) / 1e6, "M") }
        if n >= 1_000 { return short(Double(n) / 1e3, "K") }
        return "\(n)"
    }

    static func time(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let s = Int(seconds.rounded(.down))
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%d:%02d", m, sec)
    }

    static func ago(_ date: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        return f.localizedString(for: date, relativeTo: Date())
    }

    static func bytes(_ b: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: b, countStyle: .file)
    }
}

extension Color {
    init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        self.init(.sRGB,
                  red: Double((v >> 16) & 0xFF) / 255,
                  green: Double((v >> 8) & 0xFF) / 255,
                  blue: Double(v & 0xFF) / 255,
                  opacity: 1)
    }
}

/// Hash that stays the same every launch (Swift's hashValue changes each run).
func stableHash(_ s: String) -> Int {
    var h = 5381
    for u in s.unicodeScalars { h = ((h << 5) &+ h &+ Int(u.value)) & 0x7FFF_FFFF }
    return h
}

// Reads older saved data too: any missing setting just uses its default.
extension UserData {
    init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func v<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            ((try? c.decodeIfPresent(T.self, forKey: key)) ?? nil) ?? fallback
        }
        themeID = v(.themeID, themeID)
        displayName = v(.displayName, displayName)
        autoplay = v(.autoplay, autoplay)
        defaultSpeed = v(.defaultSpeed, defaultSpeed)
        playbackQuality = v(.playbackQuality, playbackQuality)
        downloadQuality = v(.downloadQuality, downloadQuality)
        liked = v(.liked, liked)
        disliked = v(.disliked, disliked)
        likedComments = v(.likedComments, likedComments)
        hiddenComments = v(.hiddenComments, hiddenComments)
        subscriptions = v(.subscriptions, subscriptions)
        notifications = v(.notifications, notifications)
        watchLater = v(.watchLater, watchLater)
        history = v(.history, history)
        positions = v(.positions, positions)
        comments = v(.comments, comments)
        uploads = v(.uploads, uploads)
        rtmpURL = v(.rtmpURL, rtmpURL)
        streamKey = v(.streamKey, streamKey)
        youtubeKey = v(.youtubeKey, youtubeKey)
        region = v(.region, region)
        savedVideos = v(.savedVideos, savedVideos)
        savedChannels = v(.savedChannels, savedChannels)
    }
}
