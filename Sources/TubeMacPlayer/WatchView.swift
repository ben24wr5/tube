import SwiftUI
import AppKit

struct WatchView: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var p: PlayerController
    @EnvironmentObject var yt: YouTubePlayer
    @EnvironmentObject var downloads: DownloadManager
    @Environment(\.theme) var theme
    let video: VideoItem

    @State private var expanded = false
    @State private var showDownload = false

    var body: some View {
        GeometryReader { geo in
            ScrollView {
                if geo.size.width > 1080 {
                    HStack(alignment: .top, spacing: 24) {
                        main
                        upNext.frame(width: 380)
                    }
                    .padding(24)
                } else {
                    VStack(alignment: .leading, spacing: 28) {
                        main
                        upNext
                    }
                    .padding(20)
                }
            }
        }
        .onChange(of: video.id) { _ in expanded = false }
    }

    // MARK: Main column

    private var main: some View {
        let channel = store.channel(id: video.channelID)
        return VStack(alignment: .leading, spacing: 14) {
            Group {
                if video.isYouTube { YouTubeSurface(video: video) } else { PlayerSurface() }
            }
                .aspectRatio(16 / 9, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            Text(video.title)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(theme.text)
                .textSelection(.enabled)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    channelBlock(channel)
                    Spacer(minLength: 12)
                    actions
                }
                VStack(alignment: .leading, spacing: 12) {
                    channelBlock(channel)
                    ScrollView(.horizontal, showsIndicators: false) { actions }
                }
            }

            descriptionBox

            CommentsSection(video: video)
                .padding(.top, 6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func channelBlock(_ c: ChannelInfo) -> some View {
        HStack(spacing: 12) {
            Button { store.showChannel(c.id) } label: { ChannelAvatar(channel: c, size: 42) }
                .buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 2) {
                Text(c.name).font(.system(size: 15, weight: .semibold)).foregroundStyle(theme.text)
                Text("\(Fmt.count(store.subscriberCount(c))) subscribers")
                    .font(.system(size: 12)).foregroundStyle(theme.secondaryText)
            }
            .fixedSize()
            SubscribeButton(channelID: c.id).padding(.leading, 6)
        }
    }

    private var actions: some View {
        HStack(spacing: 8) {
            // Like / dislike
            HStack(spacing: 0) {
                Button { store.toggleLike(video) } label: {
                    Label(Fmt.count(store.likeCount(video)),
                          systemImage: store.isLiked(video) ? "hand.thumbsup.fill" : "hand.thumbsup")
                        .padding(.trailing, 8)
                }
                .buttonStyle(.plain)
                Rectangle().fill(theme.secondaryText.opacity(0.4)).frame(width: 1, height: 20)
                Button { store.toggleDislike(video) } label: {
                    Image(systemName: store.isDisliked(video) ? "hand.thumbsdown.fill" : "hand.thumbsdown")
                        .padding(.leading, 10)
                }
                .buttonStyle(.plain)
            }
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(theme.text)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Capsule().fill(theme.surfaceHigh))

            Button { store.copyLink(video) } label: { Label("Share", systemImage: "arrowshape.turn.up.right") }
                .buttonStyle(PillButtonStyle(theme: theme))

            if video.canDownload {
                Button { showDownload = true } label: { downloadLabel }
                    .buttonStyle(PillButtonStyle(theme: theme))
                    .popover(isPresented: $showDownload, arrowEdge: .bottom) {
                        DownloadPopover(video: video, isPresented: $showDownload)
                            .environmentObject(store)
                            .environmentObject(downloads)
                            .environment(\.theme, theme)
                    }
            }

            if !video.isLive {
                Button { store.toggleWatchLater(video) } label: {
                    Label("Save", systemImage: store.data.watchLater.contains(video.id) ? "bookmark.fill" : "bookmark")
                }
                .buttonStyle(PillButtonStyle(theme: theme))
            }

            if video.isYouTube {
                Button { yt.togglePopOut() } label: { Label(yt.isPoppedOut ? "Bring back" : "Pop out", systemImage: "pip.enter") }
                    .buttonStyle(PillButtonStyle(theme: theme))
                    .help("Keep watching in a small floating window")
                Button { NSWorkspace.shared.open(video.streamURL) } label: { Label("YouTube", systemImage: "arrow.up.right.square") }
                    .buttonStyle(PillButtonStyle(theme: theme))
                    .help("Open this video on YouTube")
            } else if p.pipSupported {
                Button { p.togglePiP() } label: { Label("Mini", systemImage: "pip.enter") }
                    .buttonStyle(PillButtonStyle(theme: theme))
                    .help("Picture-in-picture")
            }
        }
        .fixedSize()
    }

    @ViewBuilder private var downloadLabel: some View {
        if let job = downloads.job(for: video) {
            switch job.state {
            case .downloading: Label("Downloading \(Int(job.progress * 100))%", systemImage: "arrow.down.circle")
            case .converting: Label("Converting \(Int(job.progress * 100))%", systemImage: "gearshape.2")
            case .failed: Label("Download failed", systemImage: "exclamationmark.circle")
            }
        } else if downloads.isDownloaded(video) {
            Label("Downloaded", systemImage: "checkmark.circle.fill")
        } else {
            Label("Download", systemImage: "arrow.down.to.line")
        }
    }

    private var descriptionBox: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(video.isLive ? "\(Fmt.count(video.views)) watching now" :
                    "\(Fmt.count(video.views)) views  •  \(Fmt.ago(video.published))  •  #\(video.category.lowercased())")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(theme.text)
            Text(video.details.isEmpty ? "No description." : video.details)
                .font(.system(size: 13))
                .foregroundStyle(theme.text)
                .lineLimit(expanded ? nil : 2)
                .textSelection(.enabled)
            Button(expanded ? "Show less" : "...more") { withAnimation { expanded.toggle() } }
                .buttonStyle(.plain)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(theme.text)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(theme.surface))
    }

    // MARK: Up next

    private var upNext: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Up next").font(.headline).foregroundStyle(theme.text)
                Spacer()
                Toggle("Autoplay", isOn: $store.data.autoplay)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .foregroundStyle(theme.secondaryText)
            }
            ForEach(store.upNext(after: video).prefix(14)) { v in
                VideoRow(video: v)
            }
        }
    }
}

// MARK: - Download quality picker

struct DownloadPopover: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var downloads: DownloadManager
    @Environment(\.theme) var theme
    let video: VideoItem
    @Binding var isPresented: Bool
    @State private var quality = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Download video").font(.headline)
            Text("Pick a quality. Free, no limits.").font(.caption).foregroundStyle(.secondary)
            Picker("", selection: $quality) {
                ForEach(DownloadManager.qualities, id: \.self) { q in
                    Text(describe(q)).tag(q)
                }
            }
            .pickerStyle(.radioGroup)
            .labelsHidden()
            Text("Saves to Downloads ▸ Tube Mac Player and shows up in the app's Downloads page so you can watch offline.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Cancel") { isPresented = false }
                Button("Download") {
                    downloads.start(video, quality: quality)
                    store.data.downloadQuality = quality
                    store.showToast("Downloading in \(quality)…")
                    isPresented = false
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(18)
        .frame(width: 320)
        .onAppear { quality = store.data.downloadQuality }
    }

    private func describe(_ q: String) -> String {
        switch q {
        case "Original": return "Original (best, as uploaded)"
        case "2160p (4K)": return "2160p 4K"
        case "1080p": return "1080p Full HD"
        case "720p": return "720p HD"
        case "540p": return "540p"
        case "480p": return "480p (smaller file)"
        case "Audio only": return "Audio only (.m4a)"
        default: return q
        }
    }
}

// MARK: - Comments

struct CommentsSection: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.theme) var theme
    let video: VideoItem
    @State private var draft = ""
    @State private var newestFirst = false
    @FocusState private var focused: Bool

    var body: some View {
        let list = store.comments(for: video, newestFirst: newestFirst)
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 18) {
                Text("\(list.count) Comments").font(.system(size: 18, weight: .bold)).foregroundStyle(theme.text)
                Menu {
                    Button("Top comments") { newestFirst = false }
                    Button("Newest first") { newestFirst = true }
                } label: {
                    Label("Sort by", systemImage: "line.3.horizontal.decrease")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }

            HStack(alignment: .top, spacing: 12) {
                ChannelAvatar(channel: store.myChannel, size: 38)
                VStack(alignment: .trailing, spacing: 8) {
                    TextField("Add a comment…", text: $draft, axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14))
                        .foregroundStyle(theme.text)
                        .lineLimit(1...6)
                        .focused($focused)
                        .padding(.vertical, 6)
                        .overlay(alignment: .bottom) {
                            Rectangle().fill(focused ? theme.text : theme.secondaryText.opacity(0.4))
                                .frame(height: focused ? 2 : 1)
                        }
                    if focused || !draft.isEmpty {
                        HStack {
                            Button("Cancel") { draft = ""; focused = false }
                                .buttonStyle(PillButtonStyle(theme: theme))
                            Button("Comment") {
                                store.addComment(draft, to: video)
                                draft = ""
                                focused = false
                            }
                            .buttonStyle(PillButtonStyle(theme: theme, prominent: true))
                            .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                }
            }

            ForEach(list) { c in
                CommentRow(comment: c) { author in
                    draft = "@\(author.replacingOccurrences(of: " ", with: "")) "
                    focused = true
                }
            }
        }
    }
}

struct CommentRow: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.theme) var theme
    let comment: VideoComment
    let onReply: (String) -> Void

    var body: some View {
        let author = ChannelInfo(id: comment.author, name: comment.author, handle: "", colorHex: color, subscribers: 0, about: "")
        HStack(alignment: .top, spacing: 12) {
            ChannelAvatar(channel: author, size: 38)
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text("@" + comment.author.replacingOccurrences(of: " ", with: "").lowercased())
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(theme.text)
                    Text(Fmt.ago(comment.date)).font(.system(size: 12)).foregroundStyle(theme.secondaryText)
                }
                Text(comment.text)
                    .font(.system(size: 14))
                    .foregroundStyle(theme.text)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 14) {
                    Button { store.toggleCommentLike(comment) } label: {
                        HStack(spacing: 5) {
                            Image(systemName: store.data.likedComments.contains(comment.id) ? "hand.thumbsup.fill" : "hand.thumbsup")
                            let n = store.commentLikes(comment)
                            if n > 0 { Text(Fmt.count(n)) }
                        }
                    }
                    Button("Reply") { onReply(comment.author) }
                    Button(comment.isMine ? "Delete" : "Hide") { store.deleteComment(comment) }
                        .foregroundStyle(theme.secondaryText)
                }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(theme.text)
            }
            Spacer(minLength: 0)
        }
    }

    private var color: String {
        let palette = ["#E5484D", "#F76B15", "#FFC53D", "#46A758", "#12A594", "#0090FF", "#6E56CF", "#D6409F"]
        return comment.isMine ? "#7B5CD6" : palette[stableHash(comment.author) % palette.count]
    }
}
