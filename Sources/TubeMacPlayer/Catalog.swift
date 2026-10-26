import Foundation

/// Starter videos so the app has something to play straight away.
/// They are free, openly licensed sample films hosted publicly.
enum Catalog {
    static let base = "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/"

    // No built-in sample content: every video in the app is a real YouTube video
    // (or one you upload yourself).
    static let channels: [ChannelInfo] = []

    private static func ago(_ days: Double) -> Date { Date(timeIntervalSinceNow: -days * 86_400) }

    private static func make(_ id: String, _ title: String, _ channel: String, _ file: String,
                             duration: Double, views: Int, days: Double, category: String, likes: Int,
                             hls: String? = nil, about: String) -> VideoItem {
        let mp4 = URL(string: base + file + ".mp4")!
        let stream = hls.flatMap { URL(string: $0) } ?? mp4
        return VideoItem(id: id, title: title, details: about, channelID: channel,
                         streamURL: stream, downloadURL: mp4,
                         thumbnailURL: URL(string: base + "images/" + file + ".jpg"),
                         duration: duration, views: views, published: ago(days),
                         category: category, baseLikes: likes)
    }

    static let videos: [VideoItem] = []

    static let live: [VideoItem] = []

    static let commentPool: [(String, String)] = [
        ("Maya Okafor", "The animation in this still holds up so well."),
        ("theo_builds", "Came back to watch this again, never gets old."),
        ("Priya S.", "That ending got me every single time."),
        ("Lukas", "Watching this in 1080p on a big screen is something else."),
        ("Ana Ribeiro", "Who else is here after it popped up on their feed?"),
        ("jonnyclips", "The sound design deserves way more credit."),
        ("Hana K.", "Saved to watch later, glad I finally did."),
        ("Ollie Grant", "Picture-in-picture while working is a game changer."),
        ("sofia.m", "No ads, just the video. Beautiful."),
        ("Daniel Mensah", "Downloaded this for the train, works perfectly offline."),
        ("Ren", "Every frame looks like a painting."),
        ("Chloe Bennett", "I didn't expect to enjoy this so much!"),
        ("marcus_v", "Can we get a part two please?"),
        ("Isla", "Perfect thing to watch with a cup of tea.")
    ]
}
