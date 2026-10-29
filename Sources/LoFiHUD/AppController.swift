import AppKit

/// Composition root: owns config and playback, and routes every input
/// (hotkeys, media keys, menu, settings) through the same actions.
final class AppController {
    private(set) var config: AppConfig
    let player: Player
    let hotkeys = Hotkeys()
    private let hud = HUDController()
    private let media = MediaKeys()
    private let devices = AudioDevices()
    private let instance: SingleInstance
    private var statusMenu: StatusMenu!
    private lazy var settings = SettingsWindowController(app: self)

    private var lastPlayedURL: URL?
    private var wasDevicePresent = false
    private var pendingSave: DispatchWorkItem?

    init(instance: SingleInstance) {
        self.instance = instance
        config = ConfigStore.load()
        player = Player(volume: config.volume)
    }

    func start() {
        Paths.ensureDirectory(config.musicDir)
        LoginItem.sync(enabled: config.autostart)
        player.loadLibrary(config.musicDir)

        player.onTrackStarted = { [weak self] url in self?.trackStarted(url) }
        player.onStateChanged = { [weak self] in self?.playbackChanged() }

        hotkeys.onAction = { [weak self] action in self?.handleHotkey(action) }
        hotkeys.register(config)

        media.onCommand = { [weak self] command in self?.handleMedia(command) }
        media.isEnabled = config.enableHardwareKeys

        devices.startMonitoring { [weak self] in self?.evaluateAutoPause() }

        statusMenu = StatusMenu(
            actions: .init(
                settings: { [weak self] in self?.openSettings() },
                toggle: { [weak self] in self?.toggleAudio() },
                next: { [weak self] in self?.nextTrack() },
                rescan: { [weak self] in self?.rescanLibrary() },
                openFolder: { [weak self] in self?.openMusicFolder() },
                quit: { [weak self] in self?.quit() }),
            state: { [weak self] in (self?.player.isPlaying ?? false, self?.player.currentTitle) })

        instance.listen { [weak self] in self?.activatedByAnotherLaunch() }
        playbackChanged()
    }

    // MARK: Input routing

    private func handleHotkey(_ action: Hotkeys.Action) {
        let playing = player.isPlaying
        switch action {
        case .play: toggleAudio()
        case .volUp: if playing { changeVolume(5) }
        case .volDown: if playing { changeVolume(-5) }
        case .prev: if playing { previousTrack() }
        case .next: if playing { nextTrack() }
        case .showSong: if playing { showCurrentSong() }
        case .ignore: if playing { ignoreCurrentSong() }
        }
    }

    private func handleMedia(_ command: MediaKeys.Command) {
        switch command {
        case .toggle: toggleAudio()
        case .play: forcePlay()
        case .pause: forcePause()
        case .next: if player.isPlaying { nextTrack() }
        case .prev: if player.isPlaying { previousTrack() }
        }
    }

    // MARK: Actions

    func toggleAudio() {
        // An empty library gets one automatic rescan before giving up.
        if player.songs.isEmpty { player.loadLibrary(config.musicDir) }
        switch player.toggle() {
        case .empty:
            toast(.folderEmpty, isAction: true)
            openMusicFolder()
        case .pause:
            toast(.paused, isAction: true)
        case .play:
            toast(.resumed, isAction: true)
        }
        playbackChanged()
    }

    func forcePlay() {
        guard player.play() else { return }
        toast(.resumed, isAction: true)
        playbackChanged()
    }

    func forcePause() {
        guard player.pause() else { return }
        toast(.paused, isAction: true)
        playbackChanged()
    }

    func nextTrack() {
        player.next()
        playbackChanged()
    }

    func previousTrack() {
        player.previous()
        playbackChanged()
    }

    func rescanLibrary() {
        player.loadLibrary(config.musicDir)
        let count = player.songs.count
        toast(count == 0 ? .folderEmpty : .rescanned(count), isAction: true)
        playbackChanged()
    }

    func showCurrentSong() {
        if let title = player.currentTitle {
            toast(.nowPlaying(title), duration: config.hudSongTimeout)
        } else {
            toast(.noSong)
        }
    }

    func ignoreCurrentSong() {
        if let title = player.ignoreCurrent(musicDir: config.musicDir) {
            toast(.removed(title), duration: config.hudSongTimeout)
        } else {
            toast(.removeFailed)
        }
        playbackChanged()
    }

    func changeVolume(_ delta: Int) {
        config.volume = player.setVolume(config.volume + delta)
        toast(.volume(config.volume), isAction: true)
        scheduleSave()
    }

    func openMusicFolder() {
        Paths.ensureDirectory(config.musicDir)
        NSWorkspace.shared.open(URL(fileURLWithPath: (config.musicDir as NSString).expandingTildeInPath))
    }

    func openSettings() { settings.open() }

    /// Show a HUD preview using unsaved settings from the Settings window.
    func previewHUD(theme: Theme, position: String, duration: Int) {
        let title = player.currentTitle ?? "Midnight Coffee Beats"
        hud.show(.nowPlaying(title), theme: theme, position: position, duration: duration)
    }

    func apply(_ newConfig: AppConfig) {
        var newConfig = newConfig
        newConfig.volume = config.volume  // volume is owned by the hotkeys, not the form
        newConfig.normalize()
        let dirChanged = newConfig.musicDir != config.musicDir
        config = newConfig
        pendingSave?.cancel()
        ConfigStore.save(config)

        LoginItem.sync(enabled: config.autostart)
        settings.refreshDockIcon()
        _ = player.setVolume(config.volume)
        hotkeys.register(config)
        media.isEnabled = config.enableHardwareKeys
        if dirChanged {
            Paths.ensureDirectory(config.musicDir)
            player.loadLibrary(config.musicDir)
            lastPlayedURL = nil
        }
        playbackChanged()
        toast(.settingsSaved)
    }

    func quit() {
        pendingSave?.cancel()
        ConfigStore.save(config)
        hotkeys.suspend()
        devices.stopMonitoring()
        player.stop()
        media.updateNowPlaying(title: nil, isPlaying: false, elapsed: 0, duration: 0)
        instance.release()
        NSApp.terminate(nil)
    }

    func uninstall() {
        hotkeys.suspend()
        player.stop()
        Uninstaller.run(deleteMusic: false)
        Uninstaller.trashAppBundle()
        instance.release()
        // Give the Trash move a moment before exiting.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { exit(0) }
    }

    func activatedByAnotherLaunch() {
        settings.open()
        toast(.alreadyRunning, duration: 3000)
    }

    // MARK: State propagation

    private func toast(_ toast: Toast, isAction: Bool = false, duration: Int? = nil) {
        if isAction && !config.showActions { return }
        hud.show(
            toast, theme: Themes.resolve(config.theme), position: config.hudPosition,
            duration: duration ?? config.hudTimeout)
    }

    private func trackStarted(_ url: URL) {
        guard player.isPlaying, player.currentURL == url else { return }
        if url != lastPlayedURL {
            lastPlayedURL = url
            if config.showNowPlaying {
                toast(.nowPlaying(TitleCleaner.clean(url: url)), duration: config.hudSongTimeout)
            }
        }
        playbackChanged()
    }

    /// Refresh the menu bar tooltip, Now Playing info, and the auto-pause check.
    private func playbackChanged() {
        let title = player.currentTitle
        let tooltip: String
        if player.isPlaying {
            tooltip = "LoFi HUD ▶ \(title ?? "Playing")"
        } else if let title {
            tooltip = "LoFi HUD ⏸ \(title)"
        } else {
            tooltip = "LoFi HUD Idle"
        }
        statusMenu?.update(tooltip: tooltip)
        media.updateNowPlaying(
            title: title, isPlaying: player.isPlaying, elapsed: player.elapsed, duration: player.duration)
        evaluateAutoPause()
    }

    /// Pause when the chosen output device disappears after having been seen.
    private func evaluateAutoPause() {
        let target = config.autopauseDevice
        guard target != "Disabled", player.isPlaying else { return }
        if AudioDevices.outputDeviceNames().contains(target) {
            wasDevicePresent = true
        } else if wasDevicePresent {
            wasDevicePresent = false
            forcePause()
            toast(.autoPaused, duration: 5000)
        }
    }

    /// Volume hotkeys can fire rapidly; coalesce disk writes.
    private func scheduleSave() {
        pendingSave?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            ConfigStore.save(self.config)
        }
        pendingSave = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
    }
}
