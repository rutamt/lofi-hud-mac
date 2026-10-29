import AppKit
import SwiftUI

/// Palette applied to the settings window and the HUD overlay.
struct Theme: Identifiable, Equatable {
    let id: String
    let label: String
    let isLight: Bool
    let bg: String
    let surface: String
    let surfaceAlt: String
    let border: String
    let fg: String
    let muted: String
    let accent: String
    let accentHover: String
    let onAccent: String
    let danger: String

    var colorScheme: ColorScheme { isLight ? .light : .dark }
    func color(_ hex: String) -> Color { Color(nsColor: NSColor(hex: hex)) }
}

enum Themes {
    static let systemID = "system"
    static let systemLabel = "System (Auto)"

    static let all: [Theme] = [
        Theme(id: "harbor_night", label: "Harbor Night", isLight: false,
              bg: "#1e1e2e", surface: "#252536", surfaceAlt: "#2c2c40", border: "#35354a",
              fg: "#e8eaf0", muted: "#8b90a5", accent: "#4a90e2", accentHover: "#357abd",
              onAccent: "#ffffff", danger: "#e63946"),
        Theme(id: "tokyo_night", label: "Tokyo Night", isLight: false,
              bg: "#1a1b26", surface: "#24283b", surfaceAlt: "#2f354a", border: "#3b4261",
              fg: "#c0caf5", muted: "#7aa2f7", accent: "#bb9af7", accentHover: "#9d7cd8",
              onAccent: "#1a1b26", danger: "#f7768e"),
        Theme(id: "rose_pine", label: "Rosé Pine", isLight: false,
              bg: "#191724", surface: "#21202e", surfaceAlt: "#26233a", border: "#393552",
              fg: "#e0def4", muted: "#908caa", accent: "#eb6f92", accentHover: "#d7827e",
              onAccent: "#191724", danger: "#eb6f92"),
        Theme(id: "polar_dusk", label: "Polar Dusk", isLight: false,
              bg: "#2e3440", surface: "#3b4252", surfaceAlt: "#434c5e", border: "#4c566a",
              fg: "#eceff4", muted: "#81a1c1", accent: "#88c0d0", accentHover: "#5e81ac",
              onAccent: "#2e3440", danger: "#bf616a"),
        Theme(id: "gruvbox", label: "Gruvbox Warm", isLight: false,
              bg: "#282828", surface: "#32302f", surfaceAlt: "#3c3836", border: "#504945",
              fg: "#ebdbb2", muted: "#a89984", accent: "#fe8019", accentHover: "#d65d0e",
              onAccent: "#282828", danger: "#fb4934"),
        Theme(id: "latte", label: "Catppuccin Latte", isLight: true,
              bg: "#eff1f5", surface: "#ffffff", surfaceAlt: "#e6e9ef", border: "#ccd0da",
              fg: "#4c4f69", muted: "#8c8fa1", accent: "#8839ef", accentHover: "#7287fd",
              onAccent: "#ffffff", danger: "#d20f39"),
        Theme(id: "system_light", label: "System Light", isLight: true,
              bg: "#f5f5f7", surface: "#ffffff", surfaceAlt: "#eaeaec", border: "#d2d2d7",
              fg: "#1d1d1f", muted: "#86868b", accent: "#0071e3", accentHover: "#0077ed",
              onAccent: "#ffffff", danger: "#ff3b30"),
    ]

    private static let byID = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })

    private static let legacyNames: [String: String] = [
        "Midnight Blue": "harbor_night", "Nordic Clean": "polar_dusk", "Forest Glow": "gruvbox",
        "Cherry Blossom": "rose_pine", "Minimal Light": "system_light", "Cyberpunk": "tokyo_night",
        "Harbor Night": "harbor_night", "Polar Dusk": "polar_dusk", "Canopy": "gruvbox",
        "Hanami": "rose_pine", "Paper": "latte", "Circuit": "tokyo_night",
        "Tokyo Night": "tokyo_night", "Rosé Pine": "rose_pine", "Gruvbox Warm": "gruvbox",
        "Catppuccin Latte": "latte", "System Light": "system_light",
        "canopy": "gruvbox", "hanami": "rose_pine", "paper": "latte", "circuit": "tokyo_night",
    ]

    static var isSystemDark: Bool {
        UserDefaults.standard.string(forKey: "AppleInterfaceStyle")?.lowercased() == "dark"
    }

    /// Stored id, `system`, or legacy display name → stable id to persist.
    static func canonicalID(_ value: String?) -> String {
        guard let value, !value.isEmpty else { return systemID }
        if ["system", "system (auto)", "auto"].contains(value.lowercased()) { return systemID }
        if byID[value] != nil { return value }
        return legacyNames[value] ?? systemID
    }

    static func resolve(_ value: String?) -> Theme {
        let id = canonicalID(value)
        if id == systemID { return byID[isSystemDark ? "harbor_night" : "system_light"]! }
        return byID[id]!
    }

    static func label(for id: String) -> String {
        id == systemID ? systemLabel : (byID[id]?.label ?? systemLabel)
    }
}

extension NSColor {
    convenience init(hex: String, alpha: CGFloat = 1) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        let v = UInt32(s, radix: 16) ?? 0xFFFFFF
        self.init(
            srgbRed: CGFloat((v >> 16) & 0xFF) / 255,
            green: CGFloat((v >> 8) & 0xFF) / 255,
            blue: CGFloat(v & 0xFF) / 255,
            alpha: alpha)
    }
}
