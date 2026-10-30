import Foundation

/// Persisted settings. The JSON schema is a superset of the Python build's `config.json`.
struct AppConfig: Codable, Equatable {
    var musicDir = Paths.defaultMusicDir
    /// Legacy single modifier. Bindings without explicit modifiers ("q") use it.
    var modKey = "option"
    /// Bindings are combos like "option+shift+q"; plain "q" means `modKey` + q.
    var keyPlay = "q"
    var keyNext = "2"
    var keyPrev = "1"
    var keyShowSong = "3"
    var keyIgnore = "4"
    var keyFavorite = "5"
    var keyVolUp = "up"
    var keyVolDown = "down"
    var volume = 50
    var showNowPlaying = true
    var showActions = true
    var showSongProgress = true
    var hudPosition = "Bottom Center"
    /// "mouse" (screen with the pointer), "primary", or a display's localized name.
    var hudDisplay = "mouse"
    /// Center of the HUD as a fraction of the screen, used when `hudPosition == "Custom"`.
    var hudCustomX = 0.5
    var hudCustomY = 0.12
    var hudTimeout = 2000
    var hudSongTimeout = 3500
    /// "Disabled", `AppConfig.autopauseCurrent`, or a device name (matched by `autopauseDeviceUID`).
    var autopauseDevice = "Disabled"
    var autopauseDeviceUID = ""
    var enableHardwareKeys = true
    var theme = Themes.systemID
    var autoLightTheme = "system_light"
    var autoDarkTheme = "harbor_night"
    /// "theme", "system" (macOS accent color) or "custom" (`customAccent`).
    var accentMode = "theme"
    var customAccent = "#4a90e2"
    var autostart = true
    var showDockIcon = true
    var crossfade = 0
    var noise = "off"
    var noiseVolume = 30
    var favoritesOnly = false
    var checkForUpdates = true

    static let autopauseCurrent = "Current Output Device"
    static let `default` = AppConfig()

    init() {}

    enum CodingKeys: String, CodingKey {
        case musicDir = "music_dir"
        case modKey = "mod_key"
        case keyPlay = "key_play"
        case keyNext = "key_next"
        case keyPrev = "key_prev"
        case keyShowSong = "key_show_song"
        case keyIgnore = "key_ignore"
        case keyFavorite = "key_favorite"
        case keyVolUp = "key_vol_up"
        case keyVolDown = "key_vol_down"
        case volume
        case showNowPlaying = "show_now_playing"
        case showActions = "show_actions"
        case showSongProgress = "show_song_progress"
        case hudPosition = "hud_position"
        case hudDisplay = "hud_display"
        case hudCustomX = "hud_custom_x"
        case hudCustomY = "hud_custom_y"
        case hudTimeout = "hud_timeout"
        case hudSongTimeout = "hud_song_timeout"
        case autopauseDevice = "autopause_device"
        case autopauseDeviceUID = "autopause_device_uid"
        case enableHardwareKeys = "enable_hardware_keys"
        case theme
        case autoLightTheme = "auto_light_theme"
        case autoDarkTheme = "auto_dark_theme"
        case accentMode = "accent_mode"
        case customAccent = "custom_accent"
        case autostart
        case showDockIcon = "show_dock_icon"
        case crossfade
        case noise
        case noiseVolume = "noise_volume"
        case favoritesOnly = "favorites_only"
        case checkForUpdates = "check_for_updates"
    }

    /// Missing or mistyped keys fall back to defaults instead of failing the whole file.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func v<T: Decodable>(_ key: CodingKeys, _ value: inout T) {
            if let decoded = try? c.decodeIfPresent(T.self, forKey: key) { value = decoded }
        }
        v(.musicDir, &musicDir)
        v(.modKey, &modKey)
        v(.keyPlay, &keyPlay)
        v(.keyNext, &keyNext)
        v(.keyPrev, &keyPrev)
        v(.keyShowSong, &keyShowSong)
        v(.keyIgnore, &keyIgnore)
        v(.keyFavorite, &keyFavorite)
        v(.keyVolUp, &keyVolUp)
        v(.keyVolDown, &keyVolDown)
        v(.volume, &volume)
        v(.showNowPlaying, &showNowPlaying)
        v(.showActions, &showActions)
        v(.showSongProgress, &showSongProgress)
        v(.hudPosition, &hudPosition)
        v(.hudDisplay, &hudDisplay)
        v(.hudCustomX, &hudCustomX)
        v(.hudCustomY, &hudCustomY)
        v(.hudTimeout, &hudTimeout)
        v(.hudSongTimeout, &hudSongTimeout)
        v(.autopauseDevice, &autopauseDevice)
        v(.autopauseDeviceUID, &autopauseDeviceUID)
        v(.enableHardwareKeys, &enableHardwareKeys)
        v(.theme, &theme)
        v(.autoLightTheme, &autoLightTheme)
        v(.autoDarkTheme, &autoDarkTheme)
        v(.accentMode, &accentMode)
        v(.customAccent, &customAccent)
        v(.autostart, &autostart)
        v(.showDockIcon, &showDockIcon)
        v(.crossfade, &crossfade)
        v(.noise, &noise)
        v(.noiseVolume, &noiseVolume)
        v(.favoritesOnly, &favoritesOnly)
        v(.checkForUpdates, &checkForUpdates)
        normalize()
    }

    mutating func normalize() {
        modKey = modKey.lowercased()
        if modKey == "alt" { modKey = "option" }
        volume = max(0, min(100, volume))
        noiseVolume = max(0, min(100, noiseVolume))
        crossfade = max(0, min(12, crossfade))
        hudCustomX = max(0, min(1, hudCustomX))
        hudCustomY = max(0, min(1, hudCustomY))
        theme = Themes.canonicalID(theme)
        if !Themes.isPreset(autoLightTheme) { autoLightTheme = "system_light" }
        if !Themes.isPreset(autoDarkTheme) { autoDarkTheme = "harbor_night" }
        if !["theme", "system", "custom"].contains(accentMode) { accentMode = "theme" }
    }
}

enum ConfigStore {
    /// Defaults merged with `config.json`. A corrupt file is moved aside to `.bak`.
    static func load(from url: URL = Paths.configURL) -> AppConfig {
        guard let data = try? Data(contentsOf: url) else { return .default }
        do {
            return try JSONDecoder().decode(AppConfig.self, from: data)
        } catch {
            Log.config.error("config.json unreadable, using defaults: \(error.localizedDescription, privacy: .public)")
            let bak = url.appendingPathExtension("bak")
            if !FileManager.default.fileExists(atPath: bak.path) {
                try? FileManager.default.moveItem(at: url, to: bak)
            }
            return .default
        }
    }

    static func save(_ config: AppConfig, to url: URL = Paths.configURL) {
        JSONFile.write(config, to: url)
    }
}

/// Playback session persisted between launches: order, resume point and favorites.
struct PlaybackState: Codable, Equatable {
    var order: [String] = []
    var current: String?
    var position: Double = 0
    var favorites: [String] = []

    static func load(from url: URL = Paths.stateURL) -> PlaybackState {
        guard let data = try? Data(contentsOf: url) else { return PlaybackState() }
        do {
            return try JSONDecoder().decode(PlaybackState.self, from: data)
        } catch {
            Log.config.error("state.json unreadable: \(error.localizedDescription, privacy: .public)")
            return PlaybackState()
        }
    }

    func save(to url: URL = Paths.stateURL) {
        JSONFile.write(self, to: url, pretty: false)
    }
}

enum JSONFile {
    static func write<T: Encodable>(_ value: T, to url: URL, pretty: Bool = true) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = pretty ? [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes] : [.withoutEscapingSlashes]
        do {
            let data = try encoder.encode(value)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
        } catch {
            Log.config.error("Saving \(url.lastPathComponent, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
