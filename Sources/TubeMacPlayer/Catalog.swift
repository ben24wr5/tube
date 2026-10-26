import Foundation

/// Starter videos so the app has something to play straight away.
/// They are free, openly licensed sample films hosted publicly.
enum Catalog {
    static let base = "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/"

    static let channels: [ChannelInfo] = [
        ChannelInfo(id: "blender", name: "Blender Studio", handle: "@blenderstudio", colorHex: "#F5792A",
                    subscribers: 1_840_000, about: "Open movies made entirely with free software."),
        ChannelInfo(id: "bigscreen", name: "Big Screen Moments", handle: "@bigscreen", colorHex: "#4285F4",
                    subscribers: 912_000, about: "Short, punchy clips made for the big screen."),
        ChannelInfo(id: "garage", name: "Garage Drive", handle: "@garagedrive", colorHex: "#2BB673",
                    subscribers: 356_000, about: "Car reviews, road trips and everything with wheels."),
        ChannelInfo(id: "tubelive", name: "Tube Mac Live", handle: "@tubemaclive", colorHex: "#E62117",
                    subscribers: 128_000, about: "Round-the-clock streams.")
    ]

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

    static let videos: [VideoItem] = [
        make("bbb", "Big Buck Bunny — Full Short Film", "blender", "BigBuckBunny",
             duration: 596, views: 18_400_000, days: 12, category: "Animation", likes: 412_000,
             hls: "https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8",
             about: "A giant rabbit with a heart bigger than himself gets his revenge on three bullies. Streams in adaptive quality — try switching between 1080p, 720p and 480p in the player's settings."),
        make("sintel", "Sintel — An Epic Fantasy Short", "blender", "Sintel",
             duration: 888, views: 9_120_000, days: 40, category: "Animation", likes: 238_000,
             about: "A lonely young woman searches for the baby dragon she once rescued."),
        make("tos", "Tears of Steel — Sci‑Fi Short", "blender", "TearsOfSteel",
             duration: 734, views: 6_870_000, days: 75, category: "Film", likes: 151_000,
             about: "A group of warriors and scientists gather in Amsterdam to stage a crucial event from the past."),
        make("ed", "Elephants Dream", "blender", "ElephantsDream",
             duration: 653, views: 3_310_000, days: 210, category: "Animation", likes: 64_000,
             about: "The world's first open movie, about two characters exploring a strange machine."),
        make("blazes", "For Bigger Blazes", "bigscreen", "ForBiggerBlazes",
             duration: 15, views: 1_240_000, days: 3, category: "Shorts", likes: 22_000,
             about: "Fifteen seconds of fire."),
        make("escapes", "For Bigger Escapes", "bigscreen", "ForBiggerEscapes",
             duration: 15, views: 980_000, days: 5, category: "Shorts", likes: 18_000,
             about: "Get away from it all."),
        make("fun", "For Bigger Fun", "bigscreen", "ForBiggerFun",
             duration: 60, views: 2_050_000, days: 8, category: "Shorts", likes: 41_000,
             about: "A minute of pure fun."),
        make("joyrides", "For Bigger Joyrides", "bigscreen", "ForBiggerJoyrides",
             duration: 15, views: 770_000, days: 16, category: "Shorts", likes: 9_800,
             about: "Hold on tight."),
        make("meltdowns", "For Bigger Meltdowns", "bigscreen", "ForBiggerMeltdowns",
             duration: 15, views: 640_000, days: 20, category: "Shorts", likes: 7_300,
             about: "When it all gets too much."),
        make("subaru", "Subaru Outback On Street And Dirt", "garage", "SubaruOutbackOnStreetAndDirt",
             duration: 594, views: 1_430_000, days: 30, category: "Cars", likes: 26_000,
             about: "We take the Outback from smooth tarmac to muddy trails."),
        make("gti", "Volkswagen GTI Review", "garage", "VolkswagenGTIReview",
             duration: 51, views: 2_880_000, days: 2, category: "Cars", likes: 57_000,
             about: "Is the hot hatch still king?"),
        make("bullrun", "We Are Going On Bullrun", "garage", "WeAreGoingOnBullrun",
             duration: 47, views: 1_110_000, days: 60, category: "Cars", likes: 19_000,
             about: "Road trip time."),
        make("grand", "What Car Can You Get For A Grand?", "garage", "WhatCarCanYouGetForAGrand",
             duration: 487, views: 4_560_000, days: 95, category: "Cars", likes: 88_000,
             about: "We go bargain hunting.")
    ]

    static let live: [VideoItem] = [
        VideoItem(id: "live-1", title: "24/7 Big Buck Bunny Live", details: "Non-stop stream.",
                  channelID: "tubelive",
                  streamURL: URL(string: "https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8")!,
                  downloadURL: nil, thumbnailURL: URL(string: base + "images/BigBuckBunny.jpg"),
                  duration: 0, views: 4_213, published: Date(), category: "Live", isLive: true),
        VideoItem(id: "live-2", title: "Colour Test Pattern — Live Broadcast", details: "Classic broadcast test stream.",
                  channelID: "tubelive",
                  streamURL: URL(string: "https://devstreaming-cdn.apple.com/videos/streaming/examples/img_bipbop_adv_example_fmp4/master.m3u8")!,
                  downloadURL: nil, thumbnailURL: nil,
                  duration: 0, views: 1_087, published: Date(), category: "Live", isLive: true),
        VideoItem(id: "live-3", title: "Tears of Steel — Watch Party", details: "Watching together, live.",
                  channelID: "tubelive",
                  streamURL: URL(string: "https://demo.unified-streaming.com/k8s/features/stable/video/tears-of-steel/tears-of-steel.ism/.m3u8")!,
                  downloadURL: nil, thumbnailURL: URL(string: base + "images/TearsOfSteel.jpg"),
                  duration: 0, views: 2_560, published: Date(), category: "Live", isLive: true)
    ]

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
