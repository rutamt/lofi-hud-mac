import Foundation

/// Persisted settings. The JSON schema matches the Python build's `config.json`.
struct AppConfig: Codable, Equatable {
    var musicDir: String
    var modKey: String
    var keyPlay: String
    var keyNext: String
    var keyPrev: String
    var keyShowSong: String
    var keyIgnore: String
    var keyVolUp: String
    var keyVolDown: String
    var volume: Int
    var showNowPlaying: Bool
    var showActions: Bool
    var hudPosition: String
    var hudTimeout: Int
    var hudSongTimeout: Int
    var autopauseDevice: String
    var enableHardwareKeys: Bool
    var theme: String
    var autostart: Bool

    static let `default` = AppConfig(
        musicDir: Paths.defaultMusicDir,
        modKey: "option",
        keyPlay: "q",
        keyNext: "2",
        keyPrev: "1",
        keyShowSong: "3",
        keyIgnore: "4",
        keyVolUp: "up",
        keyVolDown: "down",
        volume: 50,
        showNowPlaying: true,
        showActions: true,
        hudPosition: "Bottom Center",
        hudTimeout: 2000,
        hudSongTimeout: 3500,
        autopauseDevice: "Disabled",
        enableHardwareKeys: true,
        theme: Themes.systemID,
        autostart: true
    )

    enum CodingKeys: String, CodingKey {
        case musicDir = "music_dir"
        case modKey = "mod_key"
        case keyPlay = "key_play"
        case keyNext = "key_next"
        case keyPrev = "key_prev"
        case keyShowSong = "key_show_song"
        case keyIgnore = "key_ignore"
        case keyVolUp = "key_vol_up"
        case keyVolDown = "key_vol_down"
        case volume
        case showNowPlaying = "show_now_playing"
        case showActions = "show_actions"
        case hudPosition = "hud_position"
        case hudTimeout = "hud_timeout"
        case hudSongTimeout = "hud_song_timeout"
        case autopauseDevice = "autopause_device"
        case enableHardwareKeys = "enable_hardware_keys"
        case theme
        case autostart
    }

    init(
        musicDir: String, modKey: String, keyPlay: String, keyNext: String, keyPrev: String,
        keyShowSong: String, keyIgnore: String, keyVolUp: String, keyVolDown: String,
        volume: Int, showNowPlaying: Bool, showActions: Bool, hudPosition: String,
        hudTimeout: Int, hudSongTimeout: Int, autopauseDevice: String,
        enableHardwareKeys: Bool, theme: String, autostart: Bool
    ) {
        self.musicDir = musicDir
        self.modKey = modKey
        self.keyPlay = keyPlay
        self.keyNext = keyNext
        self.keyPrev = keyPrev
        self.keyShowSong = keyShowSong
        self.keyIgnore = keyIgnore
        self.keyVolUp = keyVolUp
        self.keyVolDown = keyVolDown
        self.volume = volume
        self.showNowPlaying = showNowPlaying
        self.showActions = showActions
        self.hudPosition = hudPosition
        self.hudTimeout = hudTimeout
        self.hudSongTimeout = hudSongTimeout
        self.autopauseDevice = autopauseDevice
        self.enableHardwareKeys = enableHardwareKeys
        self.theme = theme
        self.autostart = autostart
    }

    /// Missing or mistyped keys fall back to defaults instead of failing the whole file.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppConfig.default
        func v<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            (try? c.decodeIfPresent(T.self, forKey: key)) ?? fallback
        }
        musicDir = v(.musicDir, d.musicDir)
        modKey = v(.modKey, d.modKey)
        keyPlay = v(.keyPlay, d.keyPlay)
        keyNext = v(.keyNext, d.keyNext)
        keyPrev = v(.keyPrev, d.keyPrev)
        keyShowSong = v(.keyShowSong, d.keyShowSong)
        keyIgnore = v(.keyIgnore, d.keyIgnore)
        keyVolUp = v(.keyVolUp, d.keyVolUp)
        keyVolDown = v(.keyVolDown, d.keyVolDown)
        volume = v(.volume, d.volume)
        showNowPlaying = v(.showNowPlaying, d.showNowPlaying)
        showActions = v(.showActions, d.showActions)
        hudPosition = v(.hudPosition, d.hudPosition)
        hudTimeout = v(.hudTimeout, d.hudTimeout)
        hudSongTimeout = v(.hudSongTimeout, d.hudSongTimeout)
        autopauseDevice = v(.autopauseDevice, d.autopauseDevice)
        enableHardwareKeys = v(.enableHardwareKeys, d.enableHardwareKeys)
        theme = v(.theme, d.theme)
        autostart = v(.autostart, d.autostart)
        normalize()
    }

    mutating func normalize() {
        modKey = modKey.lowercased()
        if modKey == "alt" { modKey = "option" }
        volume = max(0, min(100, volume))
        theme = Themes.canonicalID(theme)
    }
}

enum ConfigStore {
    /// Defaults merged with `config.json`. A corrupt file is moved aside to `.bak`.
    static func load(from url: URL = Paths.configURL) -> AppConfig {
        guard let data = try? Data(contentsOf: url) else { return .default }
        do {
            return try JSONDecoder().decode(AppConfig.self, from: data)
        } catch {
            let bak = url.appendingPathExtension("bak")
            if !FileManager.default.fileExists(atPath: bak.path) {
                try? FileManager.default.moveItem(at: url, to: bak)
            }
            return .default
        }
    }

    static func save(_ config: AppConfig, to url: URL = Paths.configURL) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(config) else { return }
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }
}
