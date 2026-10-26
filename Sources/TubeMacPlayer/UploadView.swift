import SwiftUI
import UniformTypeIdentifiers

struct UploadView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.theme) var theme
    @Environment(\.dismiss) private var dismiss

    @State private var file: URL?
    @State private var title = ""
    @State private var details = ""
    @State private var category = "Vlogs"
    @State private var picking = false
    @State private var working = false
    @State private var error: String?
    @State private var dropTargeted = false

    private let categories = ["Vlogs", "Music", "Gaming", "Animation", "Film", "Cars", "Education", "Comedy", "Shorts"]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("Upload video", systemImage: "video.badge.plus").font(.title2.bold())
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark") }.buttonStyle(.plain).disabled(working)
            }

            Button { picking = true } label: {
                VStack(spacing: 10) {
                    Image(systemName: file == nil ? "square.and.arrow.up.circle.fill" : "checkmark.circle.fill")
                        .font(.system(size: 46))
                        .foregroundStyle(theme.accent)
                    Text(file?.lastPathComponent ?? "Choose a video, or drop one here")
                        .font(.headline)
                    Text("MP4, MOV, M4V").font(.caption).foregroundStyle(theme.secondaryText)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 170)
                .background(RoundedRectangle(cornerRadius: 14).fill(theme.surface))
                .overlay(RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(dropTargeted ? theme.accent : theme.secondaryText.opacity(0.4),
                                  style: StrokeStyle(lineWidth: 2, dash: [7])))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onDrop(of: [.fileURL], isTargeted: $dropTargeted) { providers in
                guard let provider = providers.first else { return false }
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    if let url { DispatchQueue.main.async { choose(url) } }
                }
                return true
            }

            TextField("Title", text: $title).textFieldStyle(.roundedBorder)
            TextField("Description (optional)", text: $details, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(3...6)
            Picker("Category", selection: $category) {
                ForEach(categories, id: \.self) { Text($0).tag($0) }
            }
            .frame(width: 260)

            if let error { Text(error).foregroundStyle(.red).font(.caption) }

            HStack {
                Text("Publishes to your channel. People can watch, like, comment and download it.")
                    .font(.caption).foregroundStyle(theme.secondaryText)
                Spacer()
                if working { ProgressView().controlSize(.small) }
                Button(working ? "Publishing…" : "Publish") { publish() }
                    .buttonStyle(PillButtonStyle(theme: theme, prominent: true))
                    .disabled(file == nil || working)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 560)
        .foregroundStyle(theme.text)
        .background(theme.gradient)
        .fileImporter(isPresented: $picking, allowedContentTypes: [.movie, .mpeg4Movie, .quickTimeMovie]) { result in
            if case .success(let url) = result { choose(url) }
        }
    }

    private func choose(_ url: URL) {
        file = url
        if title.isEmpty { title = url.deletingPathExtension().lastPathComponent }
    }

    private func publish() {
        guard let file else { return }
        working = true
        error = nil
        let t = title, d = details, c = category
        Task {
            do {
                try await store.importVideo(from: file, title: t, details: d, category: c)
                await MainActor.run {
                    working = false
                    store.showUpload = false
                    store.goTo(.yourVideos)
                }
            } catch {
                await MainActor.run {
                    working = false
                    self.error = "Couldn't upload: \(error.localizedDescription)"
                }
            }
        }
    }
}
