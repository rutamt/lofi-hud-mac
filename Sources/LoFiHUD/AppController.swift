import AppKit

/// Composition root: owns config and playback, and routes every input
/// (hotkeys, media keys, menu, settings) through the same actions.
final class AppController {
    enum SleepMode: Equatable {
        case off
        case at(Date)
        case endOfTrack
    }

    private(set) var config: AppConfig
    let player: Player
    let hotkeys = Hotkeys()
    private let hud = HUDController()
    private let media = MediaKeys()
    private let devices = AudioDevices()
    private let instance: SingleInstance
    private var statusMenu: StatusMenu!
    private lazy var settings = SettingsWindowController(app: self)

    private var state: PlaybackState
    private(set) var favorites: Set<String>
    private var watcher: FolderWatcher?
    private(set) var isScanning = false
    private var playWhenLoaded = false
    private(set) var lastRemoved: Player.Removed?
    private(set) var availableUpdate: Updater.Release?
    private(set) var sleep = SleepMode.off
    private var sleepTimer: Timer?

    private var lastPlayedURL: URL?
    private var wasDevicePresent = false
    /// UID of the output device in use while playing (for "Current Output Device" auto-pause).
    private var playingOnUID: String?
    private var pendingSave: DispatchWorkItem?

    static let sleepFadeSeconds: TimeInterval = 10

    init(instance: SingleInstance) {
        self.instance = instance
        config = ConfigStore.load()
        state = PlaybackState.load()
        favorites = Set(state.favorites)
        player = Player(volume: config.volume)
    }

    func start() {
        Paths.ensureDirectory(config.musicDir)
        LoginItem.sync(enabled: config.autostart)
        configurePlayer()

        player.onTrackStarted = { [weak self] url in self?.trackStarted(url) }
        player.onStateChanged = { [weak self] in self?.playerStoppedOnItsOwn() }

        hotkeys.onAction = { [weak self] action in self?.handleHotkey(action) }
        hotkeys.register(config)

        media.onCommand = { [weak self] command in self?.handleMedia(command) }
        media.isEnabled = config.enableHardwareKeys

        devices.startMonitoring(
            devicesChanged: { [weak self] in self?.outputDevicesChanged() },
            defaultChanged: { [weak self] in self?.defaultOutputChanged() })

        statusMenu = StatusMenu(app: self)
        instance.listen { [weak self] in self?.activatedByAnotherLaunch() }

        loadLibrary(restoring: true)
        watchMusicFolder()
        playbackChanged()
        scheduleAutoUpdateCheck()
    }

    private func configurePlayer() {
        player.crossfade = Double(config.crossfade)
        player.setNoise(Noise.Kind(rawValue: config.noise) ?? .off, volume: config.noiseVolume)
        applyFavoritesFilter()
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
        case .favorite: if playing { toggleFavorite() }
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

    // MARK: Library

    /// Scan in the background. `restoring` applies the saved order and resume point.
    private func loadLibrary(restoring: Bool) {
        isScanning = true
        let dir = config.musicDir
        Library.scanInBackground(dir) { [weak self] files in
            guard let self, dir == self.config.musicDir else { return }
            self.isScanning = false
            if restoring {
                self.player.setLibrary(
                    files,
                    savedOrder: self.state.order.map { URL(fileURLWithPath: $0) },
                    current: self.state.current.map { URL(fileURLWithPath: $0) },
                    position: self.state.position)
            } else {
                self.player.setLibrary(files)
            }
            self.libraryChanged()
            if self.playWhenLoaded {
                self.playWhenLoaded = false
                self.toggleAudio()
            }
        }
    }

    /// Merge a fresh scan without interrupting playback.
    func rescanLibrary(announce: Bool = true) {
        let dir = config.musicDir
        Library.scanInBackground(dir) { [weak self] files in
            guard let self, dir == self.config.musicDir, !self.isScanning else { return }
            let added = self.player.mergeLibrary(files)
            if announce {
                self.toast(files.isEmpty ? .folderEmpty : .rescanned(files.count), isAction: true)
            } else if added > 0 {
                self.toast(.newTracks(added), isAction: true)
            }
            self.libraryChanged()
        }
    }

    private func watchMusicFolder() {
        Paths.ensureDirectory(config.musicDir)
        watcher = FolderWatcher(path: config.musicDir) { [weak self] in self?.rescanLibrary(announce: false) }
    }

    private func libraryChanged() {
        settings.libraryChanged()
        playbackChanged()
        saveState()
    }

    var libraryCount: Int { player.playable.count }

    // MARK: Actions

    func toggleAudio() {
        if isScanning {
            playWhenLoaded = true
            toast(.scanning, isAction: true)
            return
        }
        // An empty library gets one quick rescan before giving up (empty folders scan instantly).
        if player.library.isEmpty { player.mergeLibrary(Library.scan(config.musicDir)) }
        switch player.toggle() {
        case .empty:
            toast(.folderEmpty, isAction: true)
            openMusicFolder()
        case .pause:
            toast(.paused, isAction: true)
            saveState()
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
        saveState()
    }

    func nextTrack() {
        player.next()
        playbackChanged()
    }

    func previousTrack() {
        player.previous()
        playbackChanged()
    }

    func showCurrentSong() {
        if let title = player.currentTitle {
            toast(.nowPlaying(title, track: trackProgress()), duration: config.hudSongTimeout)
        } else {
            toast(.noSong)
        }
    }

    func ignoreCurrentSong() {
        if let removed = player.ignoreCurrent(musicDir: config.musicDir) {
            lastRemoved = removed
            toast(.removed(removed.title, undoable: true), duration: config.hudSongTimeout) { [weak self] in
                self?.undoRemove()
            }
        } else {
            toast(.removeFailed)
        }
        playbackChanged()
        saveState()
        settings.libraryChanged()
    }

    func undoRemove() {
        guard let removed = lastRemoved else { return }
        lastRemoved = nil
        if player.undo(removed) {
            lastPlayedURL = removed.original  // the restore toast replaces "Now Playing"
            toast(.restored(removed.title), duration: config.hudSongTimeout)
        } else {
            toast(.undoFailed)
        }
        playbackChanged()
        saveState()
        settings.libraryChanged()
    }

    func isFavorite(_ url: URL?) -> Bool { url.map { favorites.contains($0.path) } ?? false }

    func toggleFavorite() {
        guard let url = player.currentURL, let title = player.currentTitle else {
            toast(.noSong)
            return
        }
        if favorites.remove(url.path) == nil {
            favorites.insert(url.path)
            toast(.favorited(title), isAction: true)
        } else {
            toast(.unfavorited(title), isAction: true)
        }
        if config.favoritesOnly { applyFavoritesFilter() }
        saveState()
    }

    private func applyFavoritesFilter() {
        player.setFilter(config.favoritesOnly ? { [weak self] url in self?.favorites.contains(url.path) ?? true } : nil)
    }

    func changeVolume(_ delta: Int) {
        setVolume(config.volume + delta, showToast: true)
    }

    func setVolume(_ value: Int, showToast: Bool) {
        config.volume = player.setVolume(value)
        if showToast { toast(.volume(config.volume), isAction: true) }
        scheduleSave()
    }

    /// Menu bar changes that bypass the Settings form.
    func update(_ change: (inout AppConfig) -> Void) {
        var c = config
        change(&c)
        apply(c)
        settings.configChangedExternally()
    }

    func openMusicFolder() {
        Paths.ensureDirectory(config.musicDir)
        NSWorkspace.shared.open(URL(fileURLWithPath: (config.musicDir as NSString).expandingTildeInPath))
    }

    func openSettings() { settings.open() }

    /// Show a sample HUD with the current settings.
    func previewHUD() {
        let title = player.currentTitle ?? "Midnight Coffee Beats"
        let track = trackProgress() ?? Toast.Track(elapsed: 42, duration: 150, playing: true)
        hud.show(.nowPlaying(title, track: config.showSongProgress ? track : nil),
                 theme: Themes.resolve(config), placement: HUDPlacement(config), duration: config.hudSongTimeout)
    }

    /// Show a draggable HUD; dropping it stores a custom position.
    func beginHUDPositioning() {
        hud.beginPositioning(theme: Themes.resolve(config), placement: HUDPlacement(config)) { [weak self] display, x, y in
            self?.update { c in
                c.hudPosition = HUDPosition.custom.rawValue
                c.hudCustomX = x
                c.hudCustomY = y
                if c.hudDisplay != "mouse", let display { c.hudDisplay = display }
            }
        }
    }

    func endHUDPositioning() { hud.endPositioning() }
    var isPositioningHUD: Bool { hud.isPositioning }

    /// Apply settings live. Only the parts that changed are touched.
    func apply(_ newConfig: AppConfig) {
        var c = newConfig
        c.volume = config.volume  // volume is owned by the hotkeys/menu, not the form
        c.normalize()
        let old = config
        guard c != old else { return }
        config = c
        pendingSave?.cancel()
        ConfigStore.save(config)

        if old.autostart != c.autostart { LoginItem.sync(enabled: c.autostart) }
        if old.showDockIcon != c.showDockIcon { settings.refreshDockIcon() }
        let bindings = { (cfg: AppConfig) in Hotkeys.Action.allCases.map { Hotkeys.combo($0, in: cfg) } }
        if bindings(old) != bindings(c) { hotkeys.update(c) }
        media.isEnabled = c.enableHardwareKeys
        player.crossfade = Double(c.crossfade)
        player.setNoise(Noise.Kind(rawValue: c.noise) ?? .off, volume: c.noiseVolume)
        if old.favoritesOnly != c.favoritesOnly {
            applyFavoritesFilter()
            if c.favoritesOnly && player.filterFellBack {
                toast(.info("FAVORITES", "No favorites yet: playing everything", icon: .heart))
            }
        }
        if old.musicDir != c.musicDir {
            player.stop()
            lastPlayedURL = nil
            state = PlaybackState(favorites: state.favorites)
            Paths.ensureDirectory(c.musicDir)
            loadLibrary(restoring: false)
            watchMusicFolder()
        }
        if !old.checkForUpdates && c.checkForUpdates { scheduleAutoUpdateCheck() }
        if old.autopauseDevice != c.autopauseDevice || old.autopauseDeviceUID != c.autopauseDeviceUID {
            wasDevicePresent = false
            playingOnUID = nil
        }
        playbackChanged()
    }

    // MARK: Sleep timer

    func setSleepTimer(minutes: Int?) {
        cancelSleep()
        guard let minutes else {
            toast(.sleepOff, isAction: true)
            return
        }
        let deadline = Date().addingTimeInterval(TimeInterval(minutes * 60))
        sleep = .at(deadline)
        let fireAt = deadline.addingTimeInterval(-Self.sleepFadeSeconds)
        let timer = Timer(fire: fireAt, interval: 0, repeats: false) { [weak self] _ in self?.sleepTimerFired() }
        RunLoop.main.add(timer, forMode: .common)
        sleepTimer = timer
        toast(.sleep("Pausing in \(minutes) min"), isAction: true)
    }

    func setSleepAtEndOfTrack() {
        cancelSleep()
        sleep = .endOfTrack
        player.stopAfterCurrent = true
        toast(.sleep("Pausing after this song"), isAction: true)
    }

    private func cancelSleep() {
        sleepTimer?.invalidate()
        sleepTimer = nil
        player.stopAfterCurrent = false
        sleep = .off
    }

    private func sleepTimerFired() {
        cancelSleep()
        guard player.isPlaying else { return }
        player.fadeOutAndPause(over: Self.sleepFadeSeconds) { [weak self] in
            self?.toast(.sleepDone)
            self?.playbackChanged()
            self?.saveState()
        }
    }

    var sleepDescription: String? {
        switch sleep {
        case .off: return nil
        case .endOfTrack: return "Pausing after this song"
        case .at(let date):
            let minutes = max(1, Int(ceil(date.timeIntervalSinceNow / 60)))
            return "Pausing in \(minutes) min"
        }
    }

    // MARK: Updates

    func checkForUpdates(interactive: Bool) {
        Updater.check { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let release?):
                self.availableUpdate = release
                if interactive {
                    Updater.presentAvailable(release)
                } else {
                    self.toast(.update(release.version), duration: 6000) { Updater.presentAvailable(release) }
                }
            case .success(nil):
                self.availableUpdate = nil
                if interactive { self.alert("You’re up to date", "LoFi HUD \(AppInfo.version) is the latest version.") }
            case .failure(let error):
                if interactive { self.alert("Couldn’t check for updates", error.localizedDescription) }
            }
        }
    }

    private func scheduleAutoUpdateCheck() {
        guard config.checkForUpdates, Paths.devHome == nil, Updater.isAutoCheckDue else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak self] in
            guard let self, self.config.checkForUpdates else { return }
            self.checkForUpdates(interactive: false)
        }
    }

    private func alert(_ title: String, _ text: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = text
        NSApp.activate()
        alert.runModal()
    }

    // MARK: Lifecycle

    func quit() {
        pendingSave?.cancel()
        ConfigStore.save(config)
        saveState()
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

    private func toast(_ toast: Toast, isAction: Bool = false, duration: Int? = nil, onAction: (() -> Void)? = nil) {
        if isAction && !config.showActions { return }
        hud.show(
            toast, theme: Themes.resolve(config), placement: HUDPlacement(config),
            duration: duration ?? config.hudTimeout, onAction: onAction)
    }

    private func trackProgress() -> Toast.Track? {
        guard config.showSongProgress, player.duration > 0 else { return nil }
        return Toast.Track(elapsed: player.elapsed, duration: player.duration, playing: player.isPlaying)
    }

    private func trackStarted(_ url: URL) {
        guard player.isPlaying, player.currentURL == url else { return }
        if url != lastPlayedURL {
            lastPlayedURL = url
            if config.showNowPlaying {
                toast(.nowPlaying(TitleCleaner.clean(url: url), track: trackProgress()), duration: config.hudSongTimeout)
            }
        }
        playbackChanged()
        saveState()
    }

    /// End of library, stop-after-current, or a device change the player couldn't recover from.
    private func playerStoppedOnItsOwn() {
        if sleep == .endOfTrack, !player.isPlaying {
            sleep = .off
            toast(.sleepDone)
        }
        playbackChanged()
        saveState()
    }

    /// Refresh the menu bar, Now Playing info, and the auto-pause check.
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
        statusMenu?.update(tooltip: tooltip, playing: player.isPlaying)
        media.updateNowPlaying(
            title: title, isPlaying: player.isPlaying, elapsed: player.elapsed, duration: player.duration)
        evaluateAutoPause()
    }

    private func outputDevicesChanged() {
        evaluateAutoPause()
        settings.devicesChanged()
    }

    /// A manual output switch (old device still connected) moves "current output" to the new one.
    private func defaultOutputChanged() {
        guard let uid = playingOnUID else { return }
        if AudioDevices.outputDevices().contains(where: { $0.uid == uid }) {
            playingOnUID = AudioDevices.defaultOutputUID()
        }
    }

    /// Pause when the chosen (or current) output device disappears.
    private func evaluateAutoPause() {
        guard player.isPlaying else {
            playingOnUID = nil
            return
        }
        switch config.autopauseDevice {
        case "Disabled":
            return
        case AppConfig.autopauseCurrent:
            let present = Set(AudioDevices.outputDevices().map(\.uid))
            if let uid = playingOnUID {
                if !present.contains(uid) {
                    playingOnUID = nil
                    autoPause()
                }
            } else {
                playingOnUID = AudioDevices.defaultOutputUID()
            }
        default:
            let devices = AudioDevices.outputDevices()
            let present = config.autopauseDeviceUID.isEmpty
                ? devices.contains { $0.name == config.autopauseDevice }
                : devices.contains { $0.uid == config.autopauseDeviceUID }
            if present {
                wasDevicePresent = true
            } else if wasDevicePresent {
                wasDevicePresent = false
                autoPause()
            }
        }
    }

    private func autoPause() {
        guard player.pause() else { return }
        toast(.autoPaused, duration: 5000)
        playbackChanged()
        saveState()
    }

    private func saveState() {
        state.order = player.songs.map(\.path)
        state.current = player.currentURL?.path
        state.position = player.elapsed
        state.favorites = favorites.sorted()
        state.save()
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
