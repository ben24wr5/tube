import SwiftUI
import AppKit

struct SettingsView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    var showsDone: Bool

    private var theme: AppTheme { store.theme }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label("Settings", systemImage: "gearshape.fill").font(.title2.bold())
                Spacer()
                if showsDone {
                    Button("Done") { dismiss() }
                        .buttonStyle(PillButtonStyle(theme: theme, prominent: true))
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding(20)
            .foregroundStyle(theme.text)

            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    section("Background theme", icon: "paintpalette.fill") {
                        themeGroup(AppTheme.picks)
                        themeGroup(AppTheme.yours)
                    }

                    section("YouTube", icon: "play.tv.fill") {
                        Text("Paste a free YouTube API key to get real YouTube videos in Home, Search, Live, channels and comments.")
                            .font(.caption)
                            .foregroundStyle(theme.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                        row("API key") {
                            HStack(spacing: 8) {
                                SecureField("Paste your key", text: $store.data.youtubeKey).frame(width: 240)
                                Button("Test") { store.testYouTubeKey() }
                                    .buttonStyle(PillButtonStyle(theme: theme, prominent: true))
                            }
                        }
                        row("Country for trending videos") {
                            TextField(store.regionCode, text: $store.data.region).frame(width: 60)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text("How to get a key (about 5 minutes, free):").font(.caption.bold()).foregroundStyle(theme.text)
                            Text("1. Go to console.cloud.google.com and sign in with Google.\n2. Create a project (any name).\n3. Search for “YouTube Data API v3” and press Enable.\n4. Go to Credentials ▸ Create credentials ▸ API key.\n5. Copy the key, paste it above and press Test.")
                                .font(.caption).foregroundStyle(theme.secondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                            Button("Open Google Cloud Console") {
                                if let url = URL(string: "https://console.cloud.google.com/apis/library/youtube.googleapis.com") {
                                    NSWorkspace.shared.open(url)
                                }
                            }
                            .buttonStyle(PillButtonStyle(theme: theme))
                            .padding(.top, 4)
                        }
                    }

                    section("Playback", icon: "play.rectangle.fill") {
                        row("Autoplay next video") {
                            Toggle("", isOn: $store.data.autoplay).toggleStyle(.switch).labelsHidden()
                        }
                        row("Default video quality") {
                            Picker("", selection: $store.data.playbackQuality) {
                                ForEach(PlayerController.qualities, id: \.self) { Text($0).tag($0) }
                            }
                            .labelsHidden().frame(width: 140)
                        }
                        row("Default speed") {
                            Picker("", selection: $store.data.defaultSpeed) {
                                ForEach(PlayerController.speeds, id: \.self) { s in
                                    Text(s == 1 ? "Normal" : String(format: "%gx", s)).tag(s)
                                }
                            }
                            .labelsHidden().frame(width: 140)
                        }
                    }

                    section("Downloads", icon: "arrow.down.circle.fill") {
                        row("Default download quality") {
                            Picker("", selection: $store.data.downloadQuality) {
                                ForEach(DownloadManager.qualities, id: \.self) { Text($0).tag($0) }
                            }
                            .labelsHidden().frame(width: 140)
                        }
                        row("Download folder") {
                            Button("Open") { NSWorkspace.shared.open(AppPaths.downloads) }
                                .buttonStyle(PillButtonStyle(theme: theme))
                        }
                    }

                    section("Your channel", icon: "person.crop.circle.fill") {
                        row("Display name") {
                            TextField("Name", text: $store.data.displayName).frame(width: 200)
                        }
                    }

                    section("Live streaming server", icon: "dot.radiowaves.left.and.right") {
                        Text("To broadcast to other people, paste the details from your streaming server (RTMP). Without one, Go Live records on your Mac and posts the stream to your channel when you finish.")
                            .font(.caption)
                            .foregroundStyle(theme.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                        row("Server URL") { TextField("rtmp://…", text: $store.data.rtmpURL).frame(width: 260) }
                        row("Stream key") { SecureField("Key", text: $store.data.streamKey).frame(width: 260) }
                    }

                    section("Privacy", icon: "hand.raised.fill") {
                        row("Watch history") {
                            Button("Clear") {
                                store.data.history.removeAll()
                                store.data.positions.removeAll()
                                store.showToast("History cleared")
                            }
                            .buttonStyle(PillButtonStyle(theme: theme))
                        }
                    }

                    Text("Tube Mac Player • Every feature free")
                        .font(.caption)
                        .foregroundStyle(theme.secondaryText)
                        .frame(maxWidth: .infinity)
                }
                .padding(20)
            }
        }
        .frame(width: 680, height: 640)
        .background(theme.gradient)
        .tint(theme.accent)
    }

    // MARK: Pieces

    private func section<Content: View>(_ title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: icon).font(.headline).foregroundStyle(theme.text)
            VStack(alignment: .leading, spacing: 12) { content() }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 14).fill(theme.surface))
        }
    }

    private func row<Control: View>(_ label: String, @ViewBuilder control: () -> Control) -> some View {
        HStack {
            Text(label).foregroundStyle(theme.text)
            Spacer()
            control()
        }
    }

    private func themeGroup(_ group: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(group).font(.system(size: 12, weight: .semibold)).foregroundStyle(theme.secondaryText)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 132), spacing: 12)], spacing: 12) {
                ForEach(AppTheme.all.filter { $0.group == group }) { t in
                    ThemeSwatch(t: t, selected: store.data.themeID == t.id) {
                        withAnimation(.easeInOut(duration: 0.3)) { store.data.themeID = t.id }
                    }
                }
            }
        }
    }
}

struct ThemeSwatch: View {
    let t: AppTheme
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                ZStack(alignment: .bottomLeading) {
                    RoundedRectangle(cornerRadius: 10).fill(t.gradient)
                    // mini app preview
                    HStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 3).fill(t.sidebar).frame(width: 20)
                        VStack(spacing: 4) {
                            HStack(spacing: 4) {
                                RoundedRectangle(cornerRadius: 3).fill(t.surface)
                                RoundedRectangle(cornerRadius: 3).fill(t.surface)
                            }
                            HStack(spacing: 4) {
                                Capsule().fill(t.accent).frame(width: 34, height: 9)
                                Capsule().fill(t.surfaceHigh).frame(height: 9)
                            }
                        }
                    }
                    .padding(7)
                    if t.sparkle {
                        Image(systemName: "sparkles").foregroundStyle(.white).shadow(color: .blue.opacity(0.5), radius: 3)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing).padding(6)
                    }
                }
                .frame(height: 78)
                .overlay(RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(selected ? t.accent : Color.gray.opacity(0.3), lineWidth: selected ? 3 : 1))

                HStack(spacing: 6) {
                    Circle().fill(t.accent).frame(width: 10, height: 10)
                    Text(t.name).font(.system(size: 12, weight: .semibold))
                    Spacer()
                    if selected { Image(systemName: "checkmark.circle.fill").foregroundStyle(t.accent) }
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
