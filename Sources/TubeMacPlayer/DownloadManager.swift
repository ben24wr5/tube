import Foundation
import AVFoundation
import AppKit

struct DownloadRecord: Codable, Identifiable, Hashable {
    var id: String
    var videoID: String
    var title: String
    var channelID: String
    var quality: String
    var fileURL: URL
    var thumbnailURL: URL?
    var duration: Double
    var date: Date
    var bytes: Int64

    var asVideo: VideoItem {
        VideoItem(id: videoID, title: title, details: "Downloaded in \(quality). Plays offline.",
                  channelID: channelID, streamURL: fileURL, downloadURL: fileURL, thumbnailURL: thumbnailURL,
                  duration: duration, views: 0, published: date, category: "Downloads", isLocal: true)
    }
}

/// Free downloads in the quality you pick. The full video is fetched, then
/// re-encoded on your Mac to the chosen size, and saved to Downloads ▸ Tube Mac Player.
final class DownloadManager: NSObject, ObservableObject, URLSessionDownloadDelegate {
    static let qualities = ["Original", "2160p (4K)", "1080p", "720p", "540p", "480p", "Audio only"]

    enum JobState: Equatable { case downloading, converting, failed(String) }

    struct Job: Identifiable {
        let id = UUID()
        let video: VideoItem
        let quality: String
        var progress: Double = 0
        var state: JobState = .downloading
        var task: URLSessionDownloadTask?
        var export: AVAssetExportSession?
        var isFailed: Bool { if case .failed = state { return true }; return false }
    }

    @Published var jobs: [Job] = []
    @Published var records: [DownloadRecord] = [] { didSet { save() } }

    private var taskToJob: [Int: UUID] = [:]
    private lazy var session = URLSession(configuration: .default, delegate: self, delegateQueue: .main)
    private var timers: [UUID: Timer] = [:]

    override init() {
        super.init()
        if let raw = try? Data(contentsOf: AppPaths.downloadRecords),
           let saved = try? JSONDecoder().decode([DownloadRecord].self, from: raw) {
            records = saved.filter { FileManager.default.fileExists(atPath: $0.fileURL.path) }
        }
    }

    private func save() {
        if let raw = try? JSONEncoder().encode(records) { try? raw.write(to: AppPaths.downloadRecords, options: .atomic) }
    }

    func job(for v: VideoItem) -> Job? { jobs.first { $0.video.id == v.id } }
    func isDownloaded(_ v: VideoItem) -> Bool { records.contains { $0.videoID == v.id } }

    // MARK: Start

    func start(_ v: VideoItem, quality: String) {
        guard !v.isLive, let source = v.downloadURL else { return }
        guard job(for: v) == nil else { return }
        var job = Job(video: v, quality: quality)
        if source.isFileURL {
            job.state = .converting
            jobs.append(job)
            convert(jobID: job.id, source: source, deleteSourceAfter: false)
        } else {
            let task = session.downloadTask(with: source)
            job.task = task
            jobs.append(job)
            taskToJob[task.taskIdentifier] = job.id
            task.resume()
        }
    }

    func cancel(_ job: Job) {
        job.task?.cancel()
        job.export?.cancelExport()
        timers[job.id]?.invalidate()
        jobs.removeAll { $0.id == job.id }
    }

    func dismiss(_ job: Job) { jobs.removeAll { $0.id == job.id } }

    func delete(_ r: DownloadRecord) {
        try? FileManager.default.removeItem(at: r.fileURL)
        records.removeAll { $0.id == r.id }
    }

    func reveal(_ r: DownloadRecord) { NSWorkspace.shared.activateFileViewerSelecting([r.fileURL]) }

    func openFolder() { NSWorkspace.shared.open(AppPaths.downloads) }

    // MARK: URLSession

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard let id = taskToJob[downloadTask.taskIdentifier], let i = jobs.firstIndex(where: { $0.id == id }),
              totalBytesExpectedToWrite > 0 else { return }
        jobs[i].progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let id = taskToJob[downloadTask.taskIdentifier] else { return }
        if let http = downloadTask.response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            fail(id, "Server said \(http.statusCode)")
            return
        }
        // The temporary file disappears when this method returns, so move it now.
        let kept = AppPaths.temp.appendingPathComponent(UUID().uuidString + ".mp4")
        do {
            try FileManager.default.moveItem(at: location, to: kept)
        } catch {
            fail(id, "Couldn't save the file")
            return
        }
        if let i = jobs.firstIndex(where: { $0.id == id }) {
            jobs[i].state = .converting
            jobs[i].progress = 0
        }
        convert(jobID: id, source: kept, deleteSourceAfter: true)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let id = taskToJob.removeValue(forKey: task.taskIdentifier) else { return }
        if let error, (error as NSError).code != NSURLErrorCancelled {
            fail(id, error.localizedDescription)
        }
    }

    // MARK: Converting to the chosen quality

    private static func preset(for quality: String) -> String {
        switch quality {
        case "2160p (4K)": return AVAssetExportPreset3840x2160
        case "1080p": return AVAssetExportPreset1920x1080
        case "720p": return AVAssetExportPreset1280x720
        case "540p": return AVAssetExportPreset960x540
        case "480p": return AVAssetExportPreset640x480
        case "Audio only": return AVAssetExportPresetAppleM4A
        default: return AVAssetExportPresetPassthrough
        }
    }

    private func destination(for v: VideoItem, quality: String, ext: String) -> URL {
        let bad = CharacterSet(charactersIn: "/\\:?%*|\"<>")
        let safe = v.title.components(separatedBy: bad).joined(separator: "-")
        let label = quality.replacingOccurrences(of: " ", with: "")
        var url = AppPaths.downloads.appendingPathComponent("\(safe) [\(label)].\(ext)")
        var n = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = AppPaths.downloads.appendingPathComponent("\(safe) [\(label)] \(n).\(ext)")
            n += 1
        }
        return url
    }

    private func convert(jobID: UUID, source: URL, deleteSourceAfter: Bool) {
        guard let i = jobs.firstIndex(where: { $0.id == jobID }) else { return }
        let v = jobs[i].video
        let quality = jobs[i].quality
        let isAudio = quality == "Audio only"
        let dest = destination(for: v, quality: quality, ext: isAudio ? "m4a" : "mp4")

        // "Original" keeps the file exactly as it came.
        if quality == "Original" {
            do {
                if deleteSourceAfter { try FileManager.default.moveItem(at: source, to: dest) }
                else { try FileManager.default.copyItem(at: source, to: dest) }
                finish(jobID, file: dest)
            } catch { fail(jobID, "Couldn't save the file") }
            return
        }

        let asset = AVURLAsset(url: source)
        guard let export = AVAssetExportSession(asset: asset, presetName: Self.preset(for: quality)) else {
            fail(jobID, "This quality isn't available for this video")
            return
        }
        export.outputURL = dest
        export.outputFileType = isAudio ? .m4a : .mp4
        export.shouldOptimizeForNetworkUse = true
        jobs[i].export = export

        timers[jobID] = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self, weak export] _ in
            guard let self, let export, let j = self.jobs.firstIndex(where: { $0.id == jobID }) else { return }
            self.jobs[j].progress = Double(export.progress)
        }

        export.exportAsynchronously { [weak self] in
            DispatchQueue.main.async {
                guard let self else { return }
                self.timers.removeValue(forKey: jobID)?.invalidate()
                if deleteSourceAfter { try? FileManager.default.removeItem(at: source) }
                switch export.status {
                case .completed: self.finish(jobID, file: dest)
                case .cancelled: break
                default: self.fail(jobID, export.error?.localizedDescription ?? "Converting failed")
                }
            }
        }
    }

    private func finish(_ id: UUID, file: URL) {
        guard let i = jobs.firstIndex(where: { $0.id == id }) else { return }
        let job = jobs.remove(at: i)
        let size = (try? FileManager.default.attributesOfItem(atPath: file.path)[.size] as? NSNumber)?.int64Value ?? 0
        records.insert(DownloadRecord(id: UUID().uuidString, videoID: job.video.id, title: job.video.title,
                                      channelID: job.video.channelID, quality: job.quality, fileURL: file,
                                      thumbnailURL: job.video.thumbnailURL, duration: job.video.duration,
                                      date: Date(), bytes: size), at: 0)
        NSSound(named: "Glass")?.play()
    }

    private func fail(_ id: UUID, _ message: String) {
        timers.removeValue(forKey: id)?.invalidate()
        guard let i = jobs.firstIndex(where: { $0.id == id }) else { return }
        jobs[i].state = .failed(message)
    }
}
