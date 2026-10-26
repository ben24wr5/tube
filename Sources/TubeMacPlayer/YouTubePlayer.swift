import SwiftUI
import WebKit
import AppKit

/// Plays real YouTube videos with YouTube's official embedded player.
/// One shared player for the whole app, so the video keeps going in the
/// mini player and in the floating pop-out window.
final class YouTubePlayer: NSObject, ObservableObject, WKScriptMessageHandler, WKNavigationDelegate, WKUIDelegate, NSWindowDelegate {
    let webView: WKWebView
    let hosts = NSHashTable<NSView>.weakObjects()

    @Published private(set) var videoID: String?
    @Published private(set) var isPlaying = false
    @Published private(set) var isBuffering = false
    @Published private(set) var currentTime: Double = 0
    @Published private(set) var duration: Double = 0
    @Published private(set) var finishedCount = 0
    @Published private(set) var errorMessage: String?
    @Published private(set) var isPoppedOut = false

    private var pageReady = false
    private var panel: NSPanel?
    private static let origin = "https://tubemacplayer.app"

    override init() {
        let config = WKWebViewConfiguration()
        config.mediaTypesRequiringUserActionForPlayback = []
        config.preferences.isElementFullscreenEnabled = true
        config.allowsAirPlayForMediaPlayback = true
        let controller = WKUserContentController()
        config.userContentController = controller
        webView = PassScrollWebView(frame: .zero, configuration: config)
        super.init()
        controller.add(WeakMessageHandler(self), name: "tube")
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.setValue(false, forKey: "drawsBackground")
        webView.autoresizingMask = [.width, .height]
    }

    // MARK: Loading

    func load(_ id: String, startAt: Double) {
        videoID = id
        errorMessage = nil
        currentTime = startAt
        duration = 0
        isBuffering = true
        let start = Int(max(0, startAt))
        if pageReady {
            webView.evaluateJavaScript("loadVideo('\(Self.safe(id))', \(start));", completionHandler: nil)
        } else {
            webView.loadHTMLString(Self.page(id: Self.safe(id), start: start), baseURL: URL(string: Self.origin + "/"))
        }
    }

    func stop() {
        if pageReady { webView.evaluateJavaScript("player && player.stopVideo && player.stopVideo();", completionHandler: nil) }
        popIn()
        videoID = nil
        isPlaying = false
        currentTime = 0
        duration = 0
    }

    func retry() {
        guard let id = videoID else { return }
        pageReady = false
        load(id, startAt: currentTime)
    }

    func togglePlay() { run(isPlaying ? "player.pauseVideo()" : "player.playVideo()") }
    func play() { run("player.playVideo()") }
    func pause() { run("player.pauseVideo()") }
    func seek(to t: Double) { run("player.seekTo(\(max(0, t)), true)") }

    private func run(_ js: String) {
        guard pageReady else { return }
        webView.evaluateJavaScript("try { \(js) } catch (e) {}", completionHandler: nil)
    }

    private static func safe(_ id: String) -> String {
        String(id.filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" })
    }

    // MARK: Messages from the page

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
        switch type {
        case "api":
            pageReady = true
        case "state":
            // -1 unstarted, 0 ended, 1 playing, 2 paused, 3 buffering, 5 cued
            let s = body["state"] as? Int ?? -1
            isPlaying = s == 1 || s == 3
            isBuffering = s == 3
            if let d = body["duration"] as? Double, d > 0 { duration = d }
            if s == 0 { isPlaying = false; finishedCount += 1 }
            if s == 1 { errorMessage = nil }
        case "time":
            if let t = body["t"] as? Double { currentTime = t }
            if let d = body["d"] as? Double, d > 0 { duration = d }
        case "error":
            isBuffering = false
            let code = body["code"] as? Int ?? 0
            switch code {
            case 2: errorMessage = "This video link isn't valid."
            case 5: errorMessage = "This video can't play in the app's player."
            case 100: errorMessage = "This video was removed or made private."
            case 101, 150: errorMessage = "The owner of this video only allows it to play on YouTube."
            case -1: errorMessage = "Couldn't reach YouTube. Check your internet connection."
            default: errorMessage = "YouTube couldn't play this video (code \(code))."
            }
        default:
            break
        }
    }

    // Links inside the player (like the YouTube logo) open in your browser.
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if navigationAction.navigationType == .linkActivated, let url = navigationAction.request.url {
            NSWorkspace.shared.open(url)
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = navigationAction.request.url { NSWorkspace.shared.open(url) }
        return nil
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { loadFailed(error) }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { loadFailed(error) }

    private func loadFailed(_ error: Error) {
        if (error as NSError).code == NSURLErrorCancelled { return }   // a newer load replaced this one
        pageReady = false
        isBuffering = false
        errorMessage = "Couldn't reach YouTube. Check your internet connection."
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        pageReady = false
        if let id = videoID { load(id, startAt: currentTime) }
    }

    // MARK: Pop-out window (picture-in-picture for YouTube videos)

    func togglePopOut() { isPoppedOut ? popIn() : popOut() }

    func popOut() {
        guard videoID != nil, panel == nil else { return }
        let size = NSSize(width: 480, height: 270)
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let frame = NSRect(x: screen.maxX - size.width - 24, y: screen.minY + 24, width: size.width, height: size.height)
        let p = NSPanel(contentRect: frame,
                        styleMask: [.titled, .closable, .resizable, .utilityWindow, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        p.title = "Tube Mac Player"
        p.level = .floating
        p.hidesOnDeactivate = false
        p.isReleasedWhenClosed = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.contentAspectRatio = NSSize(width: 16, height: 9)
        p.delegate = self
        let container = NSView(frame: NSRect(origin: .zero, size: size))
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.black.cgColor
        webView.removeFromSuperview()
        webView.frame = container.bounds
        container.addSubview(webView)
        p.contentView = container
        panel = p
        isPoppedOut = true
        p.orderFrontRegardless()
    }

    func popIn() {
        guard let p = panel else { return }
        panel = nil
        p.delegate = nil
        webView.removeFromSuperview()
        p.close()
        isPoppedOut = false
        (hosts.allObjects.last as? YouTubeHostView)?.attach()
    }

    func windowWillClose(_ notification: Notification) {
        guard panel != nil, (notification.object as? NSPanel) === panel else { return }
        DispatchQueue.main.async { self.popIn() }
    }

    // MARK: The page that hosts YouTube's player

    private static func page(id: String, start: Int) -> String {
        """
        <!doctype html><html><head>
        <meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
        <meta name="referrer" content="strict-origin-when-cross-origin">
        <style>html,body{margin:0;height:100%;background:#000;overflow:hidden}#p{position:absolute;inset:0;width:100%;height:100%}</style>
        </head><body><div id="p"></div>
        <script>
        function post(m){ try { window.webkit.messageHandlers.tube.postMessage(m); } catch(e){} }
        var player = null, first = '\(id)', firstStart = \(start);
        function loadVideo(id, start){
          if (player && player.loadVideoById) { player.loadVideoById({videoId: id, startSeconds: start}); }
          else { first = id; firstStart = start; }
        }
        function onYouTubeIframeAPIReady(){
          post({type:'api'});
          player = new YT.Player('p', {
            videoId: first,
            host: 'https://www.youtube.com',
            playerVars: { autoplay: 1, start: firstStart, playsinline: 1, rel: 0, fs: 1, enablejsapi: 1,
                          origin: '\(origin)', widget_referrer: '\(origin)' },
            events: {
              onReady: function(e){ e.target.playVideo(); },
              onStateChange: function(e){ post({type:'state', state:e.data, duration: player.getDuration ? player.getDuration() : 0}); },
              onError: function(e){ post({type:'error', code:e.data}); }
            }
          });
          setInterval(function(){
            if (player && player.getCurrentTime) post({type:'time', t: player.getCurrentTime(), d: player.getDuration()});
          }, 1000);
        }
        var tag = document.createElement('script');
        tag.src = 'https://www.youtube.com/iframe_api';
        tag.onerror = function(){ post({type:'error', code: -1}); };
        document.head.appendChild(tag);
        </script></body></html>
        """
    }
}

/// Lets the mouse wheel scroll the page around the player instead of getting stuck on the video.
final class PassScrollWebView: WKWebView {
    override func scrollWheel(with event: NSEvent) {
        nextResponder?.scrollWheel(with: event)
    }
}

/// Avoids a retain cycle between the web view and the player.
private final class WeakMessageHandler: NSObject, WKScriptMessageHandler {
    weak var target: WKScriptMessageHandler?
    init(_ target: WKScriptMessageHandler) { self.target = target }
    func userContentController(_ c: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(c, didReceive: message)
    }
}

// MARK: - Showing the player in SwiftUI

final class YouTubeHostView: NSView {
    weak var player: YouTubePlayer?

    init(player: YouTubePlayer) {
        self.player = player
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        player.hosts.add(self)
        attach()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    func attach() {
        guard let p = player, !p.isPoppedOut else { return }
        if p.webView.superview !== self {
            p.webView.removeFromSuperview()
            p.webView.frame = bounds
            p.webView.autoresizingMask = [.width, .height]
            addSubview(p.webView)
        }
    }

    func detach() {
        guard let p = player else { return }
        p.hosts.remove(self)
        if p.webView.superview === self {
            p.webView.removeFromSuperview()
            (p.hosts.allObjects.last as? YouTubeHostView)?.attach()
        }
    }

    override func layout() {
        super.layout()
        if let wv = player?.webView, wv.superview === self { wv.frame = bounds }
    }
}

struct YouTubeWebHost: NSViewRepresentable {
    let player: YouTubePlayer
    func makeNSView(context: Context) -> YouTubeHostView { YouTubeHostView(player: player) }
    func updateNSView(_ view: YouTubeHostView, context: Context) { view.attach() }
    static func dismantleNSView(_ view: YouTubeHostView, coordinator: ()) { view.detach() }
}

/// The YouTube player on the watch page.
struct YouTubeSurface: View {
    @EnvironmentObject var yt: YouTubePlayer
    @EnvironmentObject var store: AppStore
    @Environment(\.theme) var theme
    let video: VideoItem

    var body: some View {
        ZStack {
            Color.black
            YouTubeWebHost(player: yt)

            if yt.isPoppedOut {
                VStack(spacing: 10) {
                    Image(systemName: "pip").font(.system(size: 40))
                    Text("Playing in the pop-out window").font(.headline)
                    Button("Bring it back") { yt.popIn() }
                        .buttonStyle(PillButtonStyle(theme: theme, prominent: true))
                }
                .foregroundStyle(.white)
            }

            if let msg = yt.errorMessage {
                ZStack {
                    Color.black.opacity(0.85)
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 34))
                        Text(msg).font(.headline).multilineTextAlignment(.center).frame(maxWidth: 420)
                        HStack(spacing: 10) {
                            Button("Try again") { yt.retry() }
                                .buttonStyle(PillButtonStyle(theme: theme))
                            Button("Watch on YouTube") { NSWorkspace.shared.open(video.streamURL) }
                                .buttonStyle(PillButtonStyle(theme: theme, prominent: true))
                        }
                    }
                    .foregroundStyle(.white)
                    .padding()
                }
            }

            if let n = store.upNextCountdown, let cur = store.nowPlaying, let next = store.upNext(after: cur).first {
                UpNextOverlay(next: next, seconds: n)
            }
        }
    }
}
