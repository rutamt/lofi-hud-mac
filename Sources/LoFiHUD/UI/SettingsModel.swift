import AppKit
import Carbon.HIToolbox
import SwiftUI

/// State for the Settings window. Edits apply live (debounced), so there's nothing to lose on close.
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

    struct Option: Hashable {
        let tag: String
        let label: String
    }

    static let timeouts: [(ms: Int, label: String)] = [
        (1000, "1 Second"), (1500, "1.5 Seconds"), (2000, "2 Seconds"),
        (3500, "3.5 Seconds"), (5000, "5 Seconds"),
    ]

    @Published var tab: Tab = .appearance
    @Published var draft: AppConfig {
        didSet { if !syncing, draft != oldValue { scheduleApply() } }
    }
    /// The folder field applies on Return/Apply/Browse, not on every keystroke.
    @Published var musicDirText: String

    @Published private(set) var devices: [AudioDevices.Device] = []
    @Published private(set) var screens: [String] = []
    @Published private(set) var capturing: Hotkeys.Action?
    @Published private(set) var captureHint: String?
    @Published private(set) var failedHotkeys: [Hotkeys.Action] = []
    /// Combos found to be held by another app when they were recorded.
    @Published private(set) var takenElsewhere: Set<Hotkeys.Action> = []
    @Published private(set) var trackCount = 0
    @Published private(set) var savedFlash = false
    @Published var uninstallHover = false
    @Published private var systemTick = 0

    private weak var app: AppController?
    private var syncing = false
    private var applyWork: DispatchWorkItem?
    private var flashWork: DispatchWorkItem?
    private var keyMonitor: Any?
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    var onAppearanceChange: ((Theme) -> Void)?

    init(app: AppController) {
        self.app = app
        draft = app.config
        musicDirText = app.config.musicDir
        failedHotkeys = app.hotkeys.failed
        trackCount = app.libraryCount
        refreshDevices()
        refreshScreens()

        let refreshTheme: (Notification) -> Void = { [weak self] _ in
            guard let self else { return }
            self.systemTick += 1
            self.onAppearanceChange?(self.theme)
        }
        observe(DistributedNotificationCenter.default(), Notification.Name("AppleInterfaceThemeChangedNotification"), refreshTheme)
        observe(NotificationCenter.default, NSColor.systemColorsDidChangeNotification, refreshTheme)
        observe(NotificationCenter.default, NSApplication.didChangeScreenParametersNotification) { [weak self] _ in
            self?.refreshScreens()
        }
    }

    deinit {
        observers.forEach { $0.0.removeObserver($0.1) }
        endCapture(resumeHotkeys: true)
    }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name, _ block: @escaping (Notification) -> Void) {
        observers.append((center, center.addObserver(forName: name, object: nil, queue: .main, using: block)))
    }

    var theme: Theme {
        _ = systemTick
        return Themes.resolve(draft)
    }

    // MARK: Live apply

    private func scheduleApply() {
        applyWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.applyNow() }
        applyWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }

    private func applyNow() {
        guard let app else { return }
        app.apply(draft)
        failedHotkeys = app.hotkeys.failed
        trackCount = app.libraryCount
        withAnimation(.easeOut(duration: 0.15)) { savedFlash = true }
        flashWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            withAnimation(.easeOut(duration: 0.3)) { self?.savedFlash = false }
        }
        flashWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: work)
        onAppearanceChange?(theme)
    }

    /// Pull in changes made elsewhere (menu bar, HUD drag) without re-applying them.
    func syncFromApp() {
        guard let app else { return }
        applyWork?.cancel()
        syncing = true
        draft = app.config
        if musicDirText != draft.musicDir, !musicDirEdited { musicDirText = draft.musicDir }
        syncing = false
        failedHotkeys = app.hotkeys.failed
        onAppearanceChange?(theme)
    }

    func libraryChanged() { trackCount = app?.libraryCount ?? 0 }

    // MARK: Options

    func selectTheme(_ id: String) {
        withAnimation(.easeInOut(duration: 0.2)) { draft.theme = id }
    }

    func refreshDevices() { devices = AudioDevices.outputDevices() }
    func refreshScreens() { screens = NSScreen.screens.map(\.localizedName) }

    var autopauseOptions: [Option] {
        var opts = [Option(tag: "Disabled", label: "Disabled"),
                    Option(tag: AppConfig.autopauseCurrent, label: "Whichever Device Is Playing")]
        var seen = Set<String>()
        for d in devices where seen.insert(d.uid).inserted {
            opts.append(Option(tag: "uid:" + d.uid, label: d.name))
        }
        if !opts.contains(where: { $0.tag == autopauseSelection }) {
            opts.append(Option(tag: autopauseSelection, label: "\(draft.autopauseDevice) (not connected)"))
        }
        return opts
    }

    var autopauseSelection: String {
        get {
            switch draft.autopauseDevice {
            case "Disabled", AppConfig.autopauseCurrent: return draft.autopauseDevice
            default:
                // Legacy configs only have a name; resolve it to a UID if that device is connected.
                if draft.autopauseDeviceUID.isEmpty,
                   let d = devices.first(where: { $0.name == draft.autopauseDevice }) { return "uid:" + d.uid }
                return draft.autopauseDeviceUID.isEmpty ? "name:" + draft.autopauseDevice : "uid:" + draft.autopauseDeviceUID
            }
        }
        set {
            if newValue.hasPrefix("uid:") {
                let uid = String(newValue.dropFirst(4))
                draft.autopauseDeviceUID = uid
                draft.autopauseDevice = devices.first { $0.uid == uid }?.name ?? draft.autopauseDevice
            } else if newValue.hasPrefix("name:") {
                draft.autopauseDevice = String(newValue.dropFirst(5))
                draft.autopauseDeviceUID = ""
            } else {
                draft.autopauseDevice = newValue
                draft.autopauseDeviceUID = ""
            }
        }
    }

    var displayOptions: [Option] {
        var opts = [Option(tag: "mouse", label: "Display with Pointer"), Option(tag: "primary", label: "Main Display")]
        opts += screens.map { Option(tag: $0, label: $0) }
        if !opts.contains(where: { $0.tag == draft.hudDisplay }) {
            opts.append(Option(tag: draft.hudDisplay, label: "\(draft.hudDisplay) (not connected)"))
        }
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

    var customAccent: Binding<Color> {
        Binding(
            get: { Color(nsColor: NSColor(hex: self.draft.customAccent)) },
            set: { self.draft.customAccent = NSColor($0).hexString })
    }

    var favoritesCount: Int { app?.favorites.count ?? 0 }

    // MARK: Actions

    var musicDirEdited: Bool {
        musicDirText.trimmingCharacters(in: .whitespaces) != draft.musicDir
    }

    func applyMusicDir() {
        let path = musicDirText.trimmingCharacters(in: .whitespaces)
        guard !path.isEmpty else {
            musicDirText = draft.musicDir
            return
        }
        musicDirText = path
        draft.musicDir = path
    }

    func browse() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Choose"
        panel.directoryURL = URL(fileURLWithPath: (draft.musicDir as NSString).expandingTildeInPath)
        if panel.runModal() == .OK, let url = panel.url {
            musicDirText = url.path
            applyMusicDir()
        }
    }

    func openFolder() { app?.openMusicFolder() }
    func rescan() { app?.rescanLibrary() }
    func previewHUD() {
        applyWork?.perform()
        app?.previewHUD()
    }
    func positionHUD() {
        applyWork?.perform()
        app?.beginHUDPositioning()
    }
    func checkForUpdates() { app?.checkForUpdates(interactive: true) }

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

    // MARK: Hotkeys

    func combo(_ action: Hotkeys.Action) -> KeyCombo { Hotkeys.combo(action, in: draft) }

    /// Other actions bound to the same combo.
    func duplicates(of action: Hotkeys.Action) -> [Hotkeys.Action] {
        let c = combo(action)
        return Hotkeys.Action.allCases.filter { $0 != action && combo($0) == c }
    }

    func problem(for action: Hotkeys.Action) -> String? {
        if let dup = duplicates(of: action).first { return "Same as \(dup.label)" }
        if takenElsewhere.contains(action) || failedHotkeys.contains(action) { return "In use by another app" }
        if combo(action).isCommonShortcut { return "Overrides a common shortcut" }
        return nil
    }

    func resetHotkeys() {
        var d = draft
        for action in Hotkeys.Action.allCases {
            let defaultCombo = KeyCombo(Hotkeys.binding(action, in: .default), defaultModifier: "option")
            Hotkeys.setBinding(action, defaultCombo, in: &d)
        }
        takenElsewhere = []
        draft = d
    }

    func startCapture(_ action: Hotkeys.Action) {
        endCapture(resumeHotkeys: false)
        capturing = action
        captureHint = nil
        // Release the global hotkeys so the combo itself can be typed into the window.
        app?.hotkeys.suspend()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let action = self.capturing else { return event }
            let code = Int(event.keyCode)
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            var mods: KeyCombo.Modifiers = []
            if flags.contains(.control) { mods.insert(.control) }
            if flags.contains(.option) { mods.insert(.option) }
            if flags.contains(.shift) { mods.insert(.shift) }
            if flags.contains(.command) { mods.insert(.command) }

            if code == kVK_Escape && mods.isEmpty {
                self.endCapture(resumeHotkeys: true)
                return nil
            }
            guard let name = KeyCodes.name(for: code) else { return nil }
            let isFunctionKey = name.count > 1 && name.hasPrefix("f")
            if mods.isEmpty && !isFunctionKey {
                self.captureHint = "Hold at least one modifier (⌃ ⌥ ⇧ ⌘) with the key."
                return nil
            }
            let combo = KeyCombo(modifiers: mods, key: name)
            if Hotkeys.isAvailable(combo) {
                self.takenElsewhere.remove(action)
            } else {
                self.takenElsewhere.insert(action)
            }
            self.endCapture(resumeHotkeys: true)
            Hotkeys.setBinding(action, combo, in: &self.draft)
            return nil
        }
    }

    func endCapture(resumeHotkeys: Bool) {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        let wasCapturing = keyMonitor != nil
        keyMonitor = nil
        capturing = nil
        captureHint = nil
        if wasCapturing && resumeHotkeys { app?.hotkeys.resume() }
    }
}
