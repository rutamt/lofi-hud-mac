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
    var accent: String
    var accentHover: String
    var onAccent: String
    let danger: String

    var colorScheme: ColorScheme { isLight ? .light : .dark }

    /// Replace the accent, deriving a hover shade and a readable foreground.
    mutating func applyAccent(_ hex: String) {
        let c = NSColor(hex: hex)
        accent = c.hexString
        accentHover = (c.blended(withFraction: 0.18, of: .black) ?? c).hexString
        onAccent = c.luminance > 0.22 ? "#1a1a1a" : "#ffffff"  // whichever contrasts more
    }
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
        Theme(id: "mocha", label: "Catppuccin Mocha", isLight: false,
              bg: "#1e1e2e", surface: "#181825", surfaceAlt: "#313244", border: "#45475a",
              fg: "#cdd6f4", muted: "#a6adc8", accent: "#cba6f7", accentHover: "#b4befe",
              onAccent: "#1e1e2e", danger: "#f38ba8"),
        Theme(id: "dracula", label: "Dracula", isLight: false,
              bg: "#282a36", surface: "#21222c", surfaceAlt: "#343746", border: "#44475a",
              fg: "#f8f8f2", muted: "#9aa5ce", accent: "#ff79c6", accentHover: "#bd93f9",
              onAccent: "#282a36", danger: "#ff5555"),
        Theme(id: "one_dark", label: "One Dark", isLight: false,
              bg: "#282c34", surface: "#21252b", surfaceAlt: "#2c313a", border: "#3e4451",
              fg: "#dcdfe4", muted: "#8b929e", accent: "#61afef", accentHover: "#528bcc",
              onAccent: "#1e2127", danger: "#e06c75"),
        Theme(id: "kanagawa", label: "Kanagawa", isLight: false,
              bg: "#1f1f28", surface: "#16161d", surfaceAlt: "#2a2a37", border: "#363646",
              fg: "#dcd7ba", muted: "#938aa9", accent: "#e6c384", accentHover: "#c0a36e",
              onAccent: "#1f1f28", danger: "#e46876"),
        Theme(id: "everforest", label: "Everforest", isLight: false,
              bg: "#2d353b", surface: "#272e33", surfaceAlt: "#343f44", border: "#475258",
              fg: "#d3c6aa", muted: "#9da9a0", accent: "#a7c080", accentHover: "#83c092",
              onAccent: "#2d353b", danger: "#e67e80"),
        Theme(id: "solarized_dark", label: "Solarized Dark", isLight: false,
              bg: "#002b36", surface: "#073642", surfaceAlt: "#0a404d", border: "#24535e",
              fg: "#eee8d5", muted: "#93a1a1", accent: "#2aa198", accentHover: "#268bd2",
              onAccent: "#002b36", danger: "#dc322f"),
        Theme(id: "solarized_light", label: "Solarized Light", isLight: true,
              bg: "#fdf6e3", surface: "#fffbee", surfaceAlt: "#eee8d5", border: "#d9d2bc",
              fg: "#586e75", muted: "#93a1a1", accent: "#268bd2", accentHover: "#2aa198",
              onAccent: "#ffffff", danger: "#dc322f"),
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
        "Catppuccin Mocha": "mocha", "Dracula": "dracula", "One Dark": "one_dark",
        "Kanagawa": "kanagawa", "Everforest": "everforest",
        "Solarized Dark": "solarized_dark", "Solarized Light": "solarized_light",
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

    static func isPreset(_ id: String) -> Bool { byID[id] != nil }

    static func preset(_ id: String) -> Theme? { byID[id] }

    static var lightThemes: [Theme] { all.filter(\.isLight) }
    static var darkThemes: [Theme] { all.filter { !$0.isLight } }

    /// Theme for a stored id using the default System (Auto) pair and no accent override.
    static func resolve(_ value: String?) -> Theme {
        resolve(value, light: "system_light", dark: "harbor_night")
    }

    static func resolve(_ value: String?, light: String, dark: String) -> Theme {
        let id = canonicalID(value)
        if id == systemID {
            return byID[isSystemDark ? dark : light] ?? byID[isSystemDark ? "harbor_night" : "system_light"]!
        }
        return byID[id]!
    }

    /// Fully resolved theme for a config: System (Auto) pair and accent override applied.
    static func resolve(_ c: AppConfig) -> Theme {
        var theme = resolve(c.theme, light: c.autoLightTheme, dark: c.autoDarkTheme)
        let accent: String?
        switch c.accentMode {
        case "system": accent = NSColor.controlAccentColor.hexString
        case "custom": accent = c.customAccent
        default: accent = nil
        }
        if let accent { theme.applyAccent(accent) }
        return theme
    }

    static func label(for id: String) -> String {
        id == systemID ? systemLabel : (byID[id]?.label ?? systemLabel)
    }
}

extension NSColor {
    var hexString: String {
        guard let c = usingColorSpace(.sRGB) else { return "#4a90e2" }
        let r = Int(round(c.redComponent * 255)), g = Int(round(c.greenComponent * 255))
        let b = Int(round(c.blueComponent * 255))
        return String(format: "#%02x%02x%02x", r, g, b)
    }

    /// Relative luminance (WCAG).
    var luminance: CGFloat {
        guard let c = usingColorSpace(.sRGB) else { return 0.5 }
        func lin(_ v: CGFloat) -> CGFloat { v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        return 0.2126 * lin(c.redComponent) + 0.7152 * lin(c.greenComponent) + 0.0722 * lin(c.blueComponent)
    }

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
