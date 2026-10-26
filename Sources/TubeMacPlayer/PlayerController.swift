import AVKit
import AVFoundation
import Combine
import AppKit

/// One shared player for the whole app, so a video keeps going when you
/// leave the watch page (mini player) or pop it out (picture-in-picture).
final class PlayerController: NSObject, ObservableObject, AVPictureInPictureControllerDelegate {
    static let qualities = ["Auto", "2160p", "1440p", "1080p", "720p", "480p", "360p", "240p", "144p"]
    static let speeds: [Float] = [0.25, 0.5, 0.75, 1, 1.25, 1.5, 1.75, 2]

    let player = AVPlayer()
    let playerLayer = AVPlayerLayer()
    private(set) var pip: AVPictureInPictureController?
    /// Player views currently on screen (the video layer can only live in one at a time).
    let hosts = NSHashTable<NSView>.weakObjects()

    @Published private(set) var video: VideoItem?
    @Published private(set) var isPlaying = false
    @Published private(set) var isBuffering = false
    @Published var currentTime: Double = 0
    @Published private(set) var duration: Double = 0
    @Published private(set) var buffered: Double = 0
    @Published private(set) var resolution: Int = 0
    @Published private(set) var errorMessage: String?
    @Published private(set) var isPiPActive = false
    @Published private(set) var isFullscreen = false
    @Published private(set) var finishedCount = 0

    @Published var rate: Float = 1 {
        didSet {
            player.defaultRate = rate
            if isPlaying { player.rate = rate }
        }
    }
    @Published var volume: Float = 1 { didSet { player.volume = volume; if volume > 0 { isMuted = false } } }
    @Published var isMuted = false { didSet { player.isMuted = isMuted } }
    @Published var quality = "Auto" { didSet { applyQuality() } }

    /// Lets the app say when keyboard shortcuts should drive the player.
    var keysEnabled: () -> Bool = { false }

    private var timeObserver: Any?
    private var itemBag = Set<AnyCancellable>()
    private var bag = Set<AnyCancellable>()
    private var pendingStart: Double = 0
    private var isSeeking = false
    private var reachedEnd = false
    private var wantsFullscreen = false
    private var keyMonitor: Any?

    override init() {
        super.init()
        playerLayer.player = player
        playerLayer.videoGravity = .resizeAspect
        playerLayer.backgroundColor = NSColor.black.cgColor
        player.automaticallyWaitsToMinimizeStalling = true

        pip = AVPictureInPictureController(playerLayer: playerLayer)
        pip?.delegate = self

        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.25, preferredTimescale: 600),
                                                      queue: .main) { [weak self] t in
            self?.tick(t)
        }

        player.publisher(for: \.timeControlStatus)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                self?.isPlaying = status != .paused
                self?.isBuffering = status == .waitingToPlayAtSpecifiedRate
            }
            .store(in: &bag)

        NotificationCenter.default.publisher(for: NSWindow.didExitFullScreenNotification)
            .sink { [weak self] _ in self?.wantsFullscreen = false; self?.isFullscreen = false }
            .store(in: &bag)
    }

    // MARK: Loading

    func load(_ v: VideoItem, startAt: Double, quality q: String, speed: Float, autoplay: Bool = true) {
        itemBag.removeAll()
        video = v
        errorMessage = nil
        reachedEnd = false
        currentTime = startAt
        duration = v.isLive ? 0 : v.duration
        buffered = 0
        resolution = 0
        pendingStart = startAt

        let item = AVPlayerItem(url: v.streamURL)
        item.preferredForwardBufferDuration = 0  // let AVFoundation decide, like YouTube's adaptive buffering
        player.replaceCurrentItem(with: item)
        quality = q              // also applies it to the new item
        rate = speed

        item.publisher(for: \.status)
            .receive(on: DispatchQueue.main)
            .sink { [weak self, weak item] status in
                guard let self, let item else { return }
                switch status {
                case .readyToPlay:
                    if self.pendingStart > 1 {
                        self.seek(to: self.pendingStart)
                        self.pendingStart = 0
                    }
                case .failed:
                    self.errorMessage = item.error?.localizedDescription ?? "This video can't be played right now."
                default: break
                }
            }
            .store(in: &itemBag)

        NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime, object: item)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.reachedEnd = true
                self.finishedCount += 1
            }
            .store(in: &itemBag)

        NotificationCenter.default.publisher(for: .AVPlayerItemFailedToPlayToEndTime, object: item)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] note in
                let err = note.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error
                self?.errorMessage = err?.localizedDescription ?? "Playback stopped — check your connection."
            }
            .store(in: &itemBag)

        if autoplay { play() }
    }

    func retry() {
        guard let v = video else { return }
        load(v, startAt: currentTime, quality: quality, speed: rate)
    }

    func stop() {
        if pip?.isPictureInPictureActive == true { pip?.stopPictureInPicture() }
        player.pause()
        player.replaceCurrentItem(with: nil)
        itemBag.removeAll()
        video = nil
        currentTime = 0
        duration = 0
        buffered = 0
    }

    private func tick(_ t: CMTime) {
        guard let item = player.currentItem else { return }
        if !isSeeking, t.seconds.isFinite { currentTime = t.seconds }
        let d = item.duration
        if d.isNumeric, d.seconds.isFinite, d.seconds > 0 { duration = d.seconds }
        if let range = item.loadedTimeRanges.last?.timeRangeValue {
            let end = range.end.seconds
            if end.isFinite { buffered = end }
        }
        let h = Int(item.presentationSize.height.rounded())
        if h > 0 { resolution = h }
    }

    // MARK: Controls

    func play() {
        if reachedEnd, duration > 0, currentTime >= duration - 0.5 { seek(to: 0) }
        reachedEnd = false
        player.play()
        player.rate = rate
    }

    func pause() { player.pause() }

    func togglePlay() { isPlaying ? pause() : play() }

    func seek(to t: Double) {
        var target = max(0, t)
        if duration > 0 { target = min(target, duration - 0.1) }
        currentTime = target
        isSeeking = true
        reachedEnd = false
        player.seek(to: CMTime(seconds: target, preferredTimescale: 600),
                    toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            DispatchQueue.main.async { self?.isSeeking = false }
        }
    }

    /// Quick, rough seek while dragging the scrubber so the picture follows your finger.
    func scrubPreview(to t: Double) {
        currentTime = t
        isSeeking = true
        player.seek(to: CMTime(seconds: t, preferredTimescale: 600),
                    toleranceBefore: CMTime(seconds: 0.5, preferredTimescale: 600),
                    toleranceAfter: CMTime(seconds: 0.5, preferredTimescale: 600))
    }

    func skip(_ seconds: Double) { seek(to: currentTime + seconds) }

    func changeVolume(by delta: Float) {
        volume = min(1, max(0, volume + delta))
        if volume == 0 { isMuted = true }
    }

    func stepSpeed(_ dir: Int) {
        guard let i = Self.speeds.firstIndex(of: rate) else { rate = 1; return }
        let n = min(Self.speeds.count - 1, max(0, i + dir))
        rate = Self.speeds[n]
    }

    private func applyQuality() {
        guard let item = player.currentItem else { return }
        if quality == "Auto" {
            item.preferredMaximumResolution = .zero
            item.preferredPeakBitRate = 0
        } else {
            let h = Double(quality.dropLast()) ?? 1080
            item.preferredMaximumResolution = CGSize(width: (h * 16 / 9).rounded(), height: h)
            let bitrates: [Double: Double] = [2160: 20e6, 1440: 10e6, 1080: 6e6, 720: 3.2e6,
                                              480: 1.5e6, 360: 0.9e6, 240: 0.5e6, 144: 0.25e6]
            item.preferredPeakBitRate = bitrates[h] ?? 0
        }
    }

    var qualityLabel: String {
        if quality == "Auto" { return resolution > 0 ? "Auto (\(resolution)p)" : "Auto" }
        return quality
    }

    var isHD: Bool { resolution >= 720 }

    // MARK: Picture in picture

    var pipSupported: Bool { AVPictureInPictureController.isPictureInPictureSupported() }

    func togglePiP() {
        guard let pip else { return }
        if pip.isPictureInPictureActive { pip.stopPictureInPicture() }
        else {
            if !isPlaying { play() }
            pip.startPictureInPicture()
        }
    }

    func pictureInPictureControllerDidStartPictureInPicture(_ c: AVPictureInPictureController) {
        DispatchQueue.main.async { self.isPiPActive = true }
    }

    func pictureInPictureControllerDidStopPictureInPicture(_ c: AVPictureInPictureController) {
        DispatchQueue.main.async { self.isPiPActive = false }
    }

    func pictureInPictureController(_ c: AVPictureInPictureController,
                                    failedToStartPictureInPictureWithError error: Error) {
        DispatchQueue.main.async {
            self.isPiPActive = false
            self.errorMessage = nil
        }
    }

    // MARK: Full screen

    func toggleFullscreen() {
        guard video != nil else { return }
        let window = NSApp.keyWindow ?? NSApp.mainWindow ?? NSApp.windows.first
        if isFullscreen {
            isFullscreen = false
            wantsFullscreen = false
            if window?.styleMask.contains(.fullScreen) == true { window?.toggleFullScreen(nil) }
        } else {
            wantsFullscreen = true
            isFullscreen = true
            if window?.styleMask.contains(.fullScreen) == false { window?.toggleFullScreen(nil) }
        }
    }

    // MARK: Keyboard shortcuts (same keys as YouTube)

    func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.video != nil, self.isFullscreen || self.keysEnabled() else { return event }
            if NSApp.keyWindow?.firstResponder is NSText { return event }   // typing in a text box
            if event.modifierFlags.contains(.command) { return event }
            return self.handle(event) ? nil : event
        }
    }

    private func handle(_ e: NSEvent) -> Bool {
        switch e.keyCode {
        case 49: togglePlay(); return true                  // space
        case 123: skip(-5); return true                     // ←
        case 124: skip(5); return true                      // →
        case 126: changeVolume(by: 0.05); return true       // ↑
        case 125: changeVolume(by: -0.05); return true      // ↓
        case 53: if isFullscreen { toggleFullscreen(); return true }; return false  // esc
        default: break
        }
        guard let c = e.charactersIgnoringModifiers?.lowercased() else { return false }
        switch c {
        case "k": togglePlay()
        case "j": skip(-10)
        case "l": skip(10)
        case "m": isMuted.toggle()
        case "f": toggleFullscreen()
        case "i": togglePiP()
        case ">", ".": if e.modifierFlags.contains(.shift) || c == ">" { stepSpeed(1) } else { return false }
        case "<", ",": if e.modifierFlags.contains(.shift) || c == "<" { stepSpeed(-1) } else { return false }
        case "0", "1", "2", "3", "4", "5", "6", "7", "8", "9":
            guard duration > 0, let n = Double(c) else { return false }
            seek(to: duration * n / 10)
        default: return false
        }
        return true
    }
}
