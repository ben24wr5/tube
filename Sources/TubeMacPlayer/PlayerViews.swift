import SwiftUI
import AVKit

// MARK: - Video surface (hosts the shared AVPlayerLayer)

final class PlayerHostView: NSView {
    let playerLayer: AVPlayerLayer
    weak var controller: PlayerController?

    init(controller: PlayerController) {
        self.playerLayer = controller.playerLayer
        self.controller = controller
        super.init(frame: .zero)
        layer = CALayer()
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        controller.hosts.add(self)
        attach()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    func attach() {
        if playerLayer.superlayer !== layer {
            playerLayer.removeFromSuperlayer()
            layer?.addSublayer(playerLayer)
        }
        needsLayout = true
    }

    /// Called when this view goes away: hand the video to any other player view still on screen.
    func detach() {
        controller?.hosts.remove(self)
        if playerLayer.superlayer === layer { playerLayer.removeFromSuperlayer() }
        if playerLayer.superlayer == nil, let other = controller?.hosts.allObjects.last as? PlayerHostView {
            other.attach()
        }
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        playerLayer.frame = bounds
        CATransaction.commit()
    }
}

struct PlayerLayerView: NSViewRepresentable {
    let controller: PlayerController

    func makeNSView(context: Context) -> PlayerHostView { PlayerHostView(controller: controller) }
    func updateNSView(_ view: PlayerHostView, context: Context) { view.attach() }
    static func dismantleNSView(_ view: PlayerHostView, coordinator: ()) { view.detach() }
}

// MARK: - Full YouTube-style player

struct PlayerSurface: View {
    @EnvironmentObject var p: PlayerController
    @EnvironmentObject var store: AppStore
    @Environment(\.theme) var theme

    @State private var showControls = true
    @State private var hideWork: DispatchWorkItem?
    @State private var flashIcon: String?
    @State private var volumeHover = false

    private var controlsVisible: Bool { showControls || !p.isPlaying }

    var body: some View {
        ZStack {
            Color.black
            PlayerLayerView(controller: p)

            if p.isPiPActive {
                VStack(spacing: 10) {
                    Image(systemName: "pip").font(.system(size: 40))
                    Text("Playing in picture-in-picture").font(.headline)
                    Button("Bring it back") { p.togglePiP() }.buttonStyle(PillButtonStyle(theme: theme, prominent: true))
                }
                .foregroundStyle(.white)
            }

            if p.isBuffering && p.errorMessage == nil {
                ProgressView().controlSize(.large).environment(\.colorScheme, .dark)
            }

            if let msg = p.errorMessage {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 34))
                    Text("Something went wrong").font(.headline)
                    Text(msg).font(.caption).multilineTextAlignment(.center).opacity(0.8).frame(maxWidth: 380)
                    Button("Try again") { p.retry() }.buttonStyle(PillButtonStyle(theme: theme, prominent: true))
                }
                .foregroundStyle(.white)
                .padding()
            }

            if let icon = flashIcon {
                Image(systemName: icon)
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 78, height: 78)
                    .background(Circle().fill(.black.opacity(0.55)))
                    .transition(.scale(scale: 1.4).combined(with: .opacity))
            }

            // Click = play/pause, double-click = full screen (just like YouTube)
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture(count: 2) { p.toggleFullscreen() }
                .onTapGesture(count: 1) { tapToggle() }
                .allowsHitTesting(p.errorMessage == nil && !p.isPiPActive)

            controls

            if let n = store.upNextCountdown, let cur = store.nowPlaying, let next = store.upNext(after: cur).first {
                UpNextOverlay(next: next, seconds: n)
            }
        }
        .onContinuousHover { phase in
            switch phase {
            case .active: poke()
            case .ended: if p.isPlaying { withAnimation(.easeOut(duration: 0.2)) { showControls = false } }
            }
        }
        .onAppear { poke() }
        .onChange(of: p.isPlaying) { _ in poke() }
    }

    private var controls: some View {
        VStack(spacing: 4) {
            Spacer(minLength: 0)
            HStack {
                if let v = p.video, v.isLive { LiveBadge() }
                Spacer()
            }
            .padding(.bottom, 4)

            if !(p.video?.isLive ?? false) || p.duration > 0 {
                SeekBar(accent: theme.accent)
            }

            HStack(spacing: 10) {
                CtrlButton(icon: p.isPlaying ? "pause.fill" : "play.fill", help: "Play / Pause (k)") { p.togglePlay() }
                if let cur = store.nowPlaying, store.upNext(after: cur).first != nil {
                    CtrlButton(icon: "forward.end.fill", help: "Next") { store.playNext() }
                }
                CtrlButton(icon: "gobackward.10", help: "Back 10 seconds (j)") { p.skip(-10) }
                CtrlButton(icon: "goforward.10", help: "Forward 10 seconds (l)") { p.skip(10) }

                HStack(spacing: 4) {
                    CtrlButton(icon: volumeIcon, help: "Mute (m)") { p.isMuted.toggle() }
                    if volumeHover {
                        Slider(value: Binding(get: { Double(p.isMuted ? 0 : p.volume) },
                                              set: { p.volume = Float($0); p.isMuted = $0 == 0 }), in: 0...1)
                            .frame(width: 80)
                            .controlSize(.small)
                            .tint(.white)
                            .transition(.opacity.combined(with: .move(edge: .leading)))
                    }
                }
                .onHover { h in withAnimation(.easeOut(duration: 0.15)) { volumeHover = h } }

                if p.video?.isLive == true {
                    Button { if p.duration > 0 { p.seek(to: p.duration) } } label: {
                        HStack(spacing: 5) { Circle().fill(.red).frame(width: 7, height: 7); Text("LIVE") }
                            .font(.system(size: 12, weight: .bold))
                    }
                    .buttonStyle(.plain)
                    .help("Jump to live")
                } else {
                    Text("\(Fmt.time(p.currentTime)) / \(Fmt.time(p.duration))")
                        .font(.system(size: 12, weight: .medium))
                        .monospacedDigit()
                }

                Spacer()

                if p.rate != 1 {
                    Text(String(format: "%gx", p.rate)).font(.system(size: 12, weight: .bold))
                }

                Menu {
                    Picker("Quality — \(p.qualityLabel)", selection: $p.quality) {
                        ForEach(PlayerController.qualities, id: \.self) { q in
                            Text(q == "Auto" ? "Auto (best for your connection)" : q).tag(q)
                        }
                    }
                    .pickerStyle(.menu)
                    Picker("Playback speed — \(speedLabel(p.rate))", selection: $p.rate) {
                        ForEach(PlayerController.speeds, id: \.self) { s in Text(speedLabel(s)).tag(s) }
                    }
                    .pickerStyle(.menu)
                    Divider()
                    Toggle("Autoplay next video", isOn: $store.data.autoplay)
                } label: {
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: "slider.horizontal.3").font(.system(size: 16, weight: .semibold))
                        if p.isHD {
                            Text("HD").font(.system(size: 7, weight: .black))
                                .padding(.horizontal, 2)
                                .background(RoundedRectangle(cornerRadius: 2).fill(theme.accent))
                                .offset(x: 8, y: -5)
                        }
                    }
                    .foregroundColor(.white)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Quality and speed")

                if p.pipSupported {
                    CtrlButton(icon: p.isPiPActive ? "pip.exit" : "pip.enter", help: "Picture-in-picture (i)") { p.togglePiP() }
                }
                CtrlButton(icon: p.isFullscreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right",
                           help: "Full screen (f)") { p.toggleFullscreen() }
            }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 8)
        .foregroundStyle(.white)
        .background(alignment: .bottom) {
            LinearGradient(colors: [.clear, .black.opacity(0.8)], startPoint: .top, endPoint: .bottom)
                .frame(height: 120)
                .allowsHitTesting(false)
        }
        .opacity(controlsVisible ? 1 : 0)
        .allowsHitTesting(controlsVisible && !p.isPiPActive)
        .animation(.easeOut(duration: 0.2), value: controlsVisible)
    }

    private var volumeIcon: String {
        if p.isMuted || p.volume == 0 { return "speaker.slash.fill" }
        if p.volume < 0.34 { return "speaker.wave.1.fill" }
        if p.volume < 0.67 { return "speaker.wave.2.fill" }
        return "speaker.wave.3.fill"
    }

    private func speedLabel(_ s: Float) -> String { s == 1 ? "Normal" : String(format: "%gx", s) }

    private func tapToggle() {
        let willPlay = !p.isPlaying
        p.togglePlay()
        withAnimation(.easeOut(duration: 0.15)) { flashIcon = willPlay ? "play.fill" : "pause.fill" }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            withAnimation(.easeOut(duration: 0.25)) { flashIcon = nil }
        }
    }

    private func poke() {
        if !showControls { withAnimation(.easeOut(duration: 0.15)) { showControls = true } }
        hideWork?.cancel()
        let work = DispatchWorkItem {
            guard p.isPlaying else { return }
            withAnimation(.easeOut(duration: 0.3)) { showControls = false }
            if p.isFullscreen { NSCursor.setHiddenUntilMouseMoves(true) }
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.8, execute: work)
    }
}

struct CtrlButton: View {
    let icon: String
    var help: String = ""
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .frame(width: 32, height: 32)
                .background(Circle().fill(.white.opacity(hover ? 0.15 : 0)))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .onHover { hover = $0 }
    }
}

struct LiveBadge: View {
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "dot.radiowaves.left.and.right").font(.system(size: 9, weight: .bold))
            Text("LIVE").font(.system(size: 11, weight: .heavy))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(RoundedRectangle(cornerRadius: 4).fill(Color.red))
    }
}

// MARK: - Seek bar with buffered range, hover time and scrubbing

struct SeekBar: View {
    @EnvironmentObject var p: PlayerController
    let accent: Color
    @State private var hoverX: CGFloat?
    @State private var dragTime: Double?

    var body: some View {
        GeometryReader { geo in
            let w = max(geo.size.width, 1)
            let d = max(p.duration, 0.001)
            let shown = dragTime ?? p.currentTime
            let playedW = CGFloat(min(1, max(0, shown / d))) * w
            let bufferW = CGFloat(min(1, max(0, p.buffered / d))) * w
            let active = hoverX != nil || dragTime != nil
            let barH: CGFloat = active ? 6 : 3.5

            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.25)).frame(height: barH)
                Capsule().fill(.white.opacity(0.45)).frame(width: bufferW, height: barH)
                if let hx = hoverX, dragTime == nil {
                    Capsule().fill(.white.opacity(0.35)).frame(width: max(0, min(hx, w)), height: barH)
                }
                Capsule().fill(accent).frame(width: playedW, height: barH)
                Circle().fill(accent)
                    .frame(width: 14, height: 14)
                    .scaleEffect(active ? 1 : 0.01)
                    .offset(x: playedW - 7)

                if let x = dragTime.map({ CGFloat($0 / d) * w }) ?? hoverX {
                    let t = Double(min(max(x, 0), w) / w) * d
                    Text(Fmt.time(t))
                        .font(.system(size: 12, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(RoundedRectangle(cornerRadius: 5).fill(.black.opacity(0.8)))
                        .fixedSize()
                        .offset(x: min(max(x - 24, 0), w - 52), y: -24)
                }
            }
            .frame(height: 18)
            .contentShape(Rectangle())
            .animation(.easeOut(duration: 0.12), value: active)
            .onContinuousHover { phase in
                switch phase {
                case .active(let pt): hoverX = pt.x
                case .ended: hoverX = nil
                }
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        let t = Double(min(max(g.location.x, 0), w) / w) * d
                        dragTime = t
                        p.scrubPreview(to: t)
                    }
                    .onEnded { g in
                        let t = Double(min(max(g.location.x, 0), w) / w) * d
                        p.seek(to: t)
                        dragTime = nil
                    }
            )
        }
        .frame(height: 18)
    }
}

// MARK: - "Up next" countdown at the end of a video

struct UpNextOverlay: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.theme) var theme
    let next: VideoItem
    let seconds: Int

    var body: some View {
        ZStack {
            Color.black.opacity(0.78)
            VStack(spacing: 14) {
                Text("Up next in \(seconds)").font(.headline).foregroundStyle(.white.opacity(0.8))
                Thumbnail(video: next, showProgress: false).frame(width: 300)
                Text(next.title).font(.title3.bold()).foregroundStyle(.white).lineLimit(2).multilineTextAlignment(.center)
                Text(store.channel(id: next.channelID).name).foregroundStyle(.white.opacity(0.7))
                HStack(spacing: 12) {
                    Button("Cancel") { store.cancelCountdown() }
                        .buttonStyle(PillButtonStyle(theme: theme))
                    Button("Play now") { store.playNext() }
                        .buttonStyle(PillButtonStyle(theme: theme, prominent: true))
                }
            }
            .padding()
        }
    }
}

// MARK: - Mini player (keeps playing while you browse)

struct MiniPlayer: View {
    @EnvironmentObject var p: PlayerController
    @EnvironmentObject var yt: YouTubePlayer
    @EnvironmentObject var store: AppStore
    @Environment(\.theme) var theme
    let video: VideoItem

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                if video.isYouTube {
                    YouTubeWebHost(player: yt)
                    // Clicking the small video opens the watch page
                    Color.black.opacity(0.001).contentShape(Rectangle())
                    if yt.isPoppedOut { Image(systemName: "pip").foregroundStyle(.white) }
                } else {
                    PlayerLayerView(controller: p)
                    if p.isPiPActive { Image(systemName: "pip").foregroundStyle(.white) }
                }
            }
            .frame(width: 176, height: 99)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .onTapGesture { store.watchOpen = true }

            VStack(alignment: .leading, spacing: 4) {
                Text(video.title).font(.system(size: 13, weight: .semibold)).lineLimit(2).foregroundStyle(theme.text)
                Text(store.channel(id: video.channelID).name).font(.caption).foregroundStyle(theme.secondaryText)
                if duration > 0 {
                    ProgressView(value: min(currentTime, duration), total: duration)
                        .progressViewStyle(.linear).tint(theme.accent)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Group {
                MiniButton(icon: isPlaying ? "pause.fill" : "play.fill") {
                    if video.isYouTube { yt.togglePlay() } else { p.togglePlay() }
                }
                MiniButton(icon: "forward.end.fill") { store.playNext() }
                MiniButton(icon: "arrow.up.left.and.arrow.down.right") { store.watchOpen = true }
                MiniButton(icon: "xmark") { store.closePlayer() }
            }
            .foregroundStyle(theme.text)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 16).fill(theme.surface).shadow(color: .black.opacity(0.35), radius: 18, y: 6))
        .frame(maxWidth: 620)
    }

    private var isPlaying: Bool { video.isYouTube ? yt.isPlaying : p.isPlaying }
    private var currentTime: Double { video.isYouTube ? yt.currentTime : p.currentTime }
    private var duration: Double { video.isYouTube ? yt.duration : p.duration }
}

private struct MiniButton: View {
    let icon: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 15, weight: .semibold)).frame(width: 32, height: 32).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
