import AppKit
import Carbon.HIToolbox
import SwiftUI

/// Draft state for the Settings window. Nothing is applied until "Save & Apply".
final class SettingsModel: ObservableObject {
    enum Tab: String, CaseIterable, Identifiable {
        case appearance = "Appearance", playback = "Playback", controls = "Controls"
        var id: String { rawValue }
        var symbol: String {
            switch self {
            case .appearance: return "paintpalette"
            case .playback: return "play.circle"
            case .controls: return "keyboard"
            }
        }
    }

    static let timeouts: [(ms: Int, label: String)] = [
        (1000, "1 Second"), (1500, "1.5 Seconds"), (2000, "2 Seconds"),
        (3500, "3.5 Seconds"), (5000, "5 Seconds"),
    ]
    static let modifiers: [(id: String, label: String)] = [
        ("cmd", "⌘ Command"), ("option", "⌥ Option"), ("ctrl", "⌃ Control"), ("shift", "⇧ Shift"),
    ]

    @Published var tab: Tab = .appearance
    @Published var themeID: String
    @Published var hudPosition: String
    @Published var hudTimeout: Int
    @Published var hudSongTimeout: Int
    @Published var autostart: Bool
    @Published var showDockIcon: Bool
    @Published var showNowPlaying: Bool
    @Published var showActions: Bool
    @Published var autopauseDevice: String
    @Published var musicDir: String
    @Published var enableHardwareKeys: Bool
    @Published var modKey: String
    @Published var binds: [Hotkeys.Action: String]

    @Published private(set) var devices: [String] = []
    @Published private(set) var capturing: Hotkeys.Action?
    @Published private(set) var savedFlash = false
    @Published private(set) var failedHotkeys: [Hotkeys.Action] = []
    @Published private(set) var trackCount = 0
    @Published var uninstallHover = false
    @Published private var systemDarkTick = Themes.isSystemDark

    private weak var app: AppController?
    private var keyMonitor: Any?
    private var appearanceObserver: NSObjectProtocol?
    var onAppearanceChange: ((Theme) -> Void)?

    init(app: AppController) {
        self.app = app
        let c = app.config
        themeID = c.theme
        hudPosition = c.hudPosition
        hudTimeout = c.hudTimeout
        hudSongTimeout = c.hudSongTimeout
        autostart = c.autostart
        showDockIcon = c.showDockIcon
        showNowPlaying = c.showNowPlaying
        showActions = c.showActions
        autopauseDevice = c.autopauseDevice
        musicDir = c.musicDir
        enableHardwareKeys = c.enableHardwareKeys
        modKey = c.modKey
        binds = Dictionary(uniqueKeysWithValues: Hotkeys.Action.allCases.map { ($0, Hotkeys.binding($0, in: c)) })
        failedHotkeys = app.hotkeys.failed
        trackCount = app.player.songs.count
        refreshDevices()

        appearanceObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("AppleInterfaceThemeChangedNotification"), object: nil, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.systemDarkTick = Themes.isSystemDark
            self.onAppearanceChange?(self.theme)
        }
    }

    deinit {
        if let appearanceObserver { DistributedNotificationCenter.default().removeObserver(appearanceObserver) }
        endCapture(resumeHotkeys: true)
    }

    var theme: Theme {
        _ = systemDarkTick
        return Themes.resolve(themeID)
    }

    var deviceOptions: [String] {
        var opts = ["Disabled"] + devices
        if !opts.contains(autopauseDevice) { opts.append(autopauseDevice) }
        return opts
    }

    func timeoutOptions(including value: Int) -> [(ms: Int, label: String)] {
        var opts = Self.timeouts
        if !opts.contains(where: { $0.ms == value }) {
            opts.append((value, String(format: "%.1f Seconds", Double(value) / 1000)))
            opts.sort { $0.ms < $1.ms }
        }
        return opts
    }

    var cmdShortcutWarning: Bool {
        modKey == "cmd" && binds.values.contains { ["q", "w", "c", "v", "x", "z", "a", "tab", "space"].contains($0) }
    }

    func selectTheme(_ id: String) {
        withAnimation(.easeInOut(duration: 0.2)) { themeID = id }
        onAppearanceChange?(theme)
    }

    func refreshDevices() {
        devices = AudioDevices.outputDeviceNames()
    }

    // MARK: Actions

    func browse() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Choose"
        panel.directoryURL = URL(fileURLWithPath: (musicDir as NSString).expandingTildeInPath)
        if panel.runModal() == .OK, let url = panel.url { musicDir = url.path }
    }

    func openFolder() {
        let path = (musicDir.trimmingCharacters(in: .whitespaces) as NSString).expandingTildeInPath
        guard !path.isEmpty else { return }
        Paths.ensureDirectory(path)
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }

    func rescan() {
        app?.rescanLibrary()
        trackCount = app?.player.songs.count ?? 0
    }

    func previewHUD() {
        app?.previewHUD(theme: theme, position: hudPosition, duration: hudSongTimeout)
    }

    func save() {
        guard let app else { return }
        endCapture(resumeHotkeys: false)
        var c = app.config
        c.theme = themeID
        c.hudPosition = hudPosition
        c.hudTimeout = hudTimeout
        c.hudSongTimeout = hudSongTimeout
        c.autostart = autostart
        c.showDockIcon = showDockIcon
        c.showNowPlaying = showNowPlaying
        c.showActions = showActions
        c.autopauseDevice = autopauseDevice
        c.musicDir = musicDir.trimmingCharacters(in: .whitespaces)
        c.enableHardwareKeys = enableHardwareKeys
        c.modKey = modKey
        c.keyPlay = binds[.play] ?? c.keyPlay
        c.keyNext = binds[.next] ?? c.keyNext
        c.keyPrev = binds[.prev] ?? c.keyPrev
        c.keyShowSong = binds[.showSong] ?? c.keyShowSong
        c.keyIgnore = binds[.ignore] ?? c.keyIgnore
        c.keyVolUp = binds[.volUp] ?? c.keyVolUp
        c.keyVolDown = binds[.volDown] ?? c.keyVolDown
        app.apply(c)

        failedHotkeys = app.hotkeys.failed
        trackCount = app.player.songs.count
        withAnimation(.spring(response: 0.3)) { savedFlash = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            withAnimation(.easeOut(duration: 0.25)) { self?.savedFlash = false }
        }
    }

    func confirmUninstall() {
        let alert = NSAlert()
        alert.messageText = "Uninstall LoFi HUD?"
        alert.informativeText = """
            This removes LoFi HUD, its login item, and all settings from this Mac.

            Your music folder and songs will be preserved.
            """
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Uninstall").hasDestructiveAction = true
        guard alert.runModal() == .alertSecondButtonReturn else { return }
        app?.uninstall()
    }

    // MARK: Keybind capture

    func startCapture(_ action: Hotkeys.Action) {
        endCapture(resumeHotkeys: false)
        capturing = action
        // Release the global hotkeys so the combo itself can be typed into the window.
        app?.hotkeys.suspend()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let action = self.capturing else { return event }
            if Int(event.keyCode) == kVK_Escape {
                self.endCapture(resumeHotkeys: true)
            } else if let name = KeyCodes.name(for: Int(event.keyCode)) {
                self.binds[action] = name
                self.endCapture(resumeHotkeys: true)
            }
            return nil
        }
    }

    func endCapture(resumeHotkeys: Bool) {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        let wasCapturing = keyMonitor != nil
        keyMonitor = nil
        capturing = nil
        if wasCapturing && resumeHotkeys { app?.hotkeys.resume() }
    }
}
