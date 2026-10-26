import SwiftUI

struct AppTheme: Identifiable, Equatable {
    let id: String
    let name: String
    let group: String
    let isDark: Bool
    let background: Color
    let backgroundAlt: Color
    let sidebar: Color
    let surface: Color
    let surfaceHigh: Color
    let accent: Color
    let onAccent: Color
    let text: Color
    let secondaryText: Color
    var sparkle = false

    var gradient: LinearGradient {
        LinearGradient(colors: [background, backgroundAlt], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    static let picks = "Tube Mac picks"
    static let yours = "Your colours"

    static let all: [AppTheme] = [
        // My picks
        AppTheme(id: "midnight", name: "Midnight", group: picks, isDark: true,
                 background: Color(hex: "#0F0F12"), backgroundAlt: Color(hex: "#16161C"),
                 sidebar: Color(hex: "#0B0B0E"), surface: Color(hex: "#1D1D24"), surfaceHigh: Color(hex: "#2A2A33"),
                 accent: Color(hex: "#FF3B4A"), onAccent: .white,
                 text: Color(hex: "#F2F2F5"), secondaryText: Color(hex: "#A1A1AD")),
        AppTheme(id: "daylight", name: "Daylight", group: picks, isDark: false,
                 background: Color(hex: "#FAFAFB"), backgroundAlt: Color(hex: "#F0F0F3"),
                 sidebar: Color(hex: "#F3F3F5"), surface: Color(hex: "#FFFFFF"), surfaceHigh: Color(hex: "#E9E9EE"),
                 accent: Color(hex: "#E62117"), onAccent: .white,
                 text: Color(hex: "#111114"), secondaryText: Color(hex: "#5F5F6B")),
        AppTheme(id: "ocean", name: "Ocean", group: picks, isDark: true,
                 background: Color(hex: "#081A2B"), backgroundAlt: Color(hex: "#0E2A44"),
                 sidebar: Color(hex: "#061523"), surface: Color(hex: "#11314D"), surfaceHigh: Color(hex: "#1A4366"),
                 accent: Color(hex: "#2EC4F1"), onAccent: Color(hex: "#04202E"),
                 text: Color(hex: "#E6F6FF"), secondaryText: Color(hex: "#8DB4CC")),
        AppTheme(id: "sunset", name: "Sunset", group: picks, isDark: true,
                 background: Color(hex: "#241020"), backgroundAlt: Color(hex: "#3A1726"),
                 sidebar: Color(hex: "#1C0C19"), surface: Color(hex: "#3B1C30"), surfaceHigh: Color(hex: "#52273F"),
                 accent: Color(hex: "#FF8A4C"), onAccent: Color(hex: "#2A0F06"),
                 text: Color(hex: "#FFEDE3"), secondaryText: Color(hex: "#C79AA8")),
        AppTheme(id: "lavender", name: "Lavender", group: picks, isDark: false,
                 background: Color(hex: "#F5F2FC"), backgroundAlt: Color(hex: "#EBE5F8"),
                 sidebar: Color(hex: "#EEE9F8"), surface: Color(hex: "#FFFFFF"), surfaceHigh: Color(hex: "#E2DAF4"),
                 accent: Color(hex: "#7B5CD6"), onAccent: .white,
                 text: Color(hex: "#1E1533"), secondaryText: Color(hex: "#6B5F86")),

        // Requested colours
        AppTheme(id: "emerald", name: "Emerald", group: yours, isDark: true,
                 background: Color(hex: "#04221A"), backgroundAlt: Color(hex: "#0A3A2B"),
                 sidebar: Color(hex: "#031A14"), surface: Color(hex: "#0D3D2E"), surfaceHigh: Color(hex: "#145240"),
                 accent: Color(hex: "#2ECC8F"), onAccent: Color(hex: "#02251A"),
                 text: Color(hex: "#E6FFF5"), secondaryText: Color(hex: "#86C2AA")),
        AppTheme(id: "diamond", name: "Diamond", group: yours, isDark: false,
                 background: Color(hex: "#EEF6FB"), backgroundAlt: Color(hex: "#DCEBF6"),
                 sidebar: Color(hex: "#E6F1F9"), surface: Color(hex: "#FFFFFF"), surfaceHigh: Color(hex: "#D4E6F3"),
                 accent: Color(hex: "#4A9FD4"), onAccent: .white,
                 text: Color(hex: "#0D2333"), secondaryText: Color(hex: "#5B7A90"), sparkle: true),
        AppTheme(id: "gold", name: "Gold", group: yours, isDark: true,
                 background: Color(hex: "#17120A"), backgroundAlt: Color(hex: "#2A2010"),
                 sidebar: Color(hex: "#120E07"), surface: Color(hex: "#2B2112"), surfaceHigh: Color(hex: "#3D301A"),
                 accent: Color(hex: "#D4AF37"), onAccent: Color(hex: "#1E1604"),
                 text: Color(hex: "#FFF6DC"), secondaryText: Color(hex: "#C2AE7C")),
        AppTheme(id: "silver", name: "Silver", group: yours, isDark: false,
                 background: Color(hex: "#E4E6EA"), backgroundAlt: Color(hex: "#CDD1D7"),
                 sidebar: Color(hex: "#DADDE2"), surface: Color(hex: "#F3F4F6"), surfaceHigh: Color(hex: "#C5C9D0"),
                 accent: Color(hex: "#5E6670"), onAccent: .white,
                 text: Color(hex: "#1B1E23"), secondaryText: Color(hex: "#5A6069")),
        AppTheme(id: "blackred", name: "Black & Red", group: yours, isDark: true,
                 background: Color(hex: "#000000"), backgroundAlt: Color(hex: "#140303"),
                 sidebar: Color(hex: "#050505"), surface: Color(hex: "#151515"), surfaceHigh: Color(hex: "#262626"),
                 accent: Color(hex: "#E10600"), onAccent: .white,
                 text: Color(hex: "#FFFFFF"), secondaryText: Color(hex: "#A3A3A3")),
        AppTheme(id: "redgold", name: "Red & Gold", group: yours, isDark: true,
                 background: Color(hex: "#3E070C"), backgroundAlt: Color(hex: "#5C0E15"),
                 sidebar: Color(hex: "#33060A"), surface: Color(hex: "#651219"), surfaceHigh: Color(hex: "#7E1A22"),
                 accent: Color(hex: "#E8C15A"), onAccent: Color(hex: "#3A0608"),
                 text: Color(hex: "#FFF2D6"), secondaryText: Color(hex: "#E0B8A0"))
    ]
}

private struct ThemeKey: EnvironmentKey {
    static let defaultValue: AppTheme = AppTheme.all[0]
}

extension EnvironmentValues {
    var theme: AppTheme {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
}

/// Rounded "pill" button used across the app, YouTube style.
struct PillButtonStyle: ButtonStyle {
    let theme: AppTheme
    var prominent = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .foregroundStyle(prominent ? theme.onAccent : theme.text)
            .background(Capsule().fill(prominent ? theme.accent : theme.surfaceHigh))
            .opacity(configuration.isPressed ? 0.75 : 1)
            .contentShape(Capsule())
    }
}
