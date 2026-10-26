import SwiftUI
import AVFoundation
import AppKit

/// Go live with your Mac's camera and microphone. You get a live preview,
/// a running timer and live chat. When you end the stream it's saved and
/// posted to your channel as a video.
final class CameraModel: NSObject, ObservableObject, AVCaptureFileOutputRecordingDelegate {
    let session = AVCaptureSession()
    private let output = AVCaptureMovieFileOutput()
    private var configured = false
    private var timer: Timer?
    private var recordingURL: URL?

    @Published var permission: Bool?
    @Published var isLive = false
    @Published var elapsed = 0
    @Published var problem: String?
    var onFinished: ((URL) -> Void)?

    func start() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: configure()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { ok in
                DispatchQueue.main.async { if ok { self.configure() } else { self.permission = false } }
            }
        default: permission = false
        }
    }

    private func configure() {
        permission = true
        guard !configured else { startRunning(); return }
        configured = true
        session.beginConfiguration()
        session.sessionPreset = .high
        if let cam = AVCaptureDevice.default(for: .video),
           let input = try? AVCaptureDeviceInput(device: cam), session.canAddInput(input) {
            session.addInput(input)
        } else {
            problem = "No camera found."
        }
        if let mic = AVCaptureDevice.default(for: .audio),
           let input = try? AVCaptureDeviceInput(device: mic), session.canAddInput(input) {
            session.addInput(input)
        }
        if session.canAddOutput(output) { session.addOutput(output) }
        session.commitConfiguration()
        startRunning()
    }

    private func startRunning() {
        let s = session
        DispatchQueue.global(qos: .userInitiated).async { if !s.isRunning { s.startRunning() } }
    }

    func stopSession() {
        if isLive { endLive() }
        let s = session
        DispatchQueue.global(qos: .userInitiated).async { if s.isRunning { s.stopRunning() } }
    }

    func goLive() {
        guard !isLive, permission == true else { return }
        let url = AppPaths.temp.appendingPathComponent("live-\(UUID().uuidString).mov")
        recordingURL = url
        output.startRecording(to: url, recordingDelegate: self)
        isLive = true
        elapsed = 0
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.elapsed += 1 }
    }

    func endLive() {
        guard isLive else { return }
        timer?.invalidate()
        isLive = false
        output.stopRecording()
    }

    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL,
                    from connections: [AVCaptureConnection], error: Error?) {
        DispatchQueue.main.async {
            if FileManager.default.fileExists(atPath: outputFileURL.path) {
                self.onFinished?(outputFileURL)
            } else {
                self.problem = error?.localizedDescription ?? "The stream couldn't be saved."
            }
        }
    }
}

struct CameraPreview: NSViewRepresentable {
    let session: AVCaptureSession
    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        v.layer = layer
        v.wantsLayer = true
        return v
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

struct GoLiveView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.theme) var theme
    @Environment(\.dismiss) private var dismiss
    @StateObject private var cam = CameraModel()

    @State private var title = ""
    @State private var chat: [(String, String)] = []
    @State private var message = ""
    @State private var saving = false

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label("Go live", systemImage: "dot.radiowaves.left.and.right").font(.title2.bold())
                    Spacer()
                    if cam.isLive {
                        LiveBadge()
                        Text(Fmt.time(Double(cam.elapsed))).monospacedDigit().font(.headline)
                    }
                }

                ZStack {
                    Color.black
                    if cam.permission == true {
                        CameraPreview(session: cam.session)
                    } else if cam.permission == false {
                        VStack(spacing: 8) {
                            Image(systemName: "video.slash.fill").font(.largeTitle)
                            Text("Camera access is off").font(.headline)
                            Text("Turn it on in System Settings ▸ Privacy & Security ▸ Camera.").font(.caption)
                            Button("Open System Settings") {
                                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") {
                                    NSWorkspace.shared.open(url)
                                }
                            }
                        }
                        .foregroundStyle(.white)
                    } else {
                        ProgressView().environment(\.colorScheme, .dark)
                    }
                    if let p = cam.problem {
                        Text(p).foregroundStyle(.white).padding(8).background(.red.opacity(0.8), in: Capsule())
                            .frame(maxHeight: .infinity, alignment: .top).padding()
                    }
                }
                .aspectRatio(16 / 9, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 14))

                TextField("Stream title", text: $title).textFieldStyle(.roundedBorder).disabled(cam.isLive)

                HStack {
                    Text(store.data.rtmpURL.isEmpty
                         ? "No streaming server set — your stream is recorded and posted to your channel when you end it."
                         : "Server: \(store.data.rtmpURL)")
                        .font(.caption)
                        .foregroundStyle(theme.secondaryText)
                    Spacer()
                    if saving {
                        ProgressView().controlSize(.small)
                        Text("Posting…").font(.caption)
                    }
                    if cam.isLive {
                        Button("End stream") { cam.endLive(); saving = true }
                            .buttonStyle(PillButtonStyle(theme: theme, prominent: true))
                    } else {
                        Button("Close") { cam.stopSession(); dismiss() }
                            .buttonStyle(PillButtonStyle(theme: theme))
                            .disabled(saving)
                        Button("Go live") {
                            cam.goLive()
                            chat.append(("Tube Mac", "You're live! 🎉"))
                        }
                        .buttonStyle(PillButtonStyle(theme: theme, prominent: true))
                        .disabled(cam.permission != true || saving)
                    }
                }
            }
            .padding(20)
            .frame(width: 620)

            // Live chat
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Live chat").font(.headline)
                    Spacer()
                    if cam.isLive { LiveBadge() }
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(chat.enumerated()), id: \.offset) { _, m in
                            (Text(m.0 + "  ").bold().foregroundColor(theme.secondaryText) + Text(m.1))
                                .font(.system(size: 13))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                HStack {
                    TextField("Say something…", text: $message).textFieldStyle(.roundedBorder)
                        .onSubmit(send)
                    Button(action: send) { Image(systemName: "paperplane.fill") }
                        .disabled(message.isEmpty)
                }
            }
            .padding(16)
            .frame(width: 280)
            .background(theme.surface)
        }
        .frame(height: 560)
        .foregroundStyle(theme.text)
        .background(theme.gradient)
        .onAppear {
            cam.onFinished = { url in
                let t = title.isEmpty ? "Live stream — \(Date().formatted(date: .abbreviated, time: .shortened))" : title
                Task {
                    try? await store.importVideo(from: url, title: t, details: "Recorded live on Tube Mac Player.", category: "Live")
                    try? FileManager.default.removeItem(at: url)
                    await MainActor.run {
                        saving = false
                        cam.stopSession()
                        dismiss()
                        store.goTo(.yourVideos)
                    }
                }
            }
            cam.start()
        }
        .onDisappear { cam.stopSession() }
    }

    private func send() {
        let m = message.trimmingCharacters(in: .whitespaces)
        guard !m.isEmpty else { return }
        chat.append((store.data.displayName, m))
        message = ""
    }
}
