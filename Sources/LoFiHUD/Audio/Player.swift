import AVFoundation

/// Shuffled, looping local-library player on AVAudioEngine. Main thread only.
///
/// Two player "decks" alternate: while one plays, the next track is opened in the background
/// and scheduled on the other deck to start exactly when the current one ends (gapless), or
/// `crossfade` seconds earlier with an equal-power fade. The engine is paused whenever playback
/// is, so idle CPU stays at zero.
final class Player {
    enum ToggleResult { case play, pause, empty }

    /// A song moved to Ignored_Lofi, kept so the move can be undone.
    struct Removed {
        let title: String
        let original: URL
        let moved: URL
        let position: TimeInterval
    }

    private(set) var queue = PlayQueue()
    /// Every playable file in the music folder (the queue may be a filtered subset).
    private(set) var library: [URL] = []
    private(set) var isPlaying = false
    private(set) var currentURL: URL?

    /// Fires (asynchronously) whenever a new track starts, including gapless transitions.
    var onTrackStarted: ((URL) -> Void)?
    /// Fires when play state changes on its own (end of library, stop-after-current, device change).
    var onStateChanged: (() -> Void)?

    /// Seconds of overlap between tracks; 0 = gapless.
    var crossfade: TimeInterval = 0
    /// Pause when the current track ends instead of continuing (sleep timer "end of track").
    var stopAfterCurrent = false
    /// Limits the queue to matching songs (e.g. favorites). Falls back to everything if none match.
    private(set) var filter: ((URL) -> Bool)?

    private let engine = AVAudioEngine()
    private let musicMixer = AVAudioMixerNode()
    private let decks = [Deck(), Deck()]
    private var cur = 0
    private let noiseNode = AVAudioPlayerNode()
    private var noiseKind = Noise.Kind.off
    private var noiseScheduled = false

    private var volume: Int
    private var frozenElapsed: TimeInterval?  // position while paused or not yet loaded
    private var lastKnownElapsed: TimeInterval = 0
    private var needsReschedule = false  // decks are empty; next play() must load the track
    private var monitor: Timer?
    private var pending: Pending?
    private var transitionFailed = false
    private var fadeTimer: Timer?
    private var fadeDecks: (from: Deck, to: Deck)?
    private var sleepFade: Timer?
    private var prepared: (url: URL, file: AVAudioFile)?
    private var preloading: URL?
    private let io = DispatchQueue(label: "com.rutamt.lofihud.audio-io", qos: .userInitiated)
    /// Files that failed to decode, with their size at the time; retried if the file changes.
    private var unplayable: [URL: Int] = [:]

    private struct Pending {
        let url: URL
        let deck: Int
        let overlap: TimeInterval
        let commit: DispatchWorkItem
    }

    init(volume: Int) {
        self.volume = max(0, min(100, volume))
        engine.attach(musicMixer)
        engine.attach(noiseNode)
        decks.forEach { engine.attach($0.node) }
        _ = engine.link(musicMixer, to: engine.mainMixerNode, format: nil)
        _ = engine.link(noiseNode, to: engine.mainMixerNode, format: Noise.format)
        musicMixer.outputVolume = Float(self.volume) / 100

        NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { [weak self] _ in
            // Let a device-disconnect auto-pause land first so audio doesn't jump to the speakers.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self?.engineConfigurationChanged() }
        }
    }

    var songs: [URL] { queue.order }
    /// Exposed for the audio smoke test's output tap.
    var outputMixer: AVAudioMixerNode { engine.mainMixerNode }
    var currentTitle: String? { currentURL.map(TitleCleaner.clean(url:)) }
    var duration: TimeInterval { decks[cur].file != nil ? decks[cur].duration : 0 }
    var elapsed: TimeInterval {
        if let frozenElapsed { return frozenElapsed }
        return decks[cur].elapsed ?? lastKnownElapsed
    }

    // MARK: Library

    /// Initial load: restore the saved order and current song (paused at `position`).
    func setLibrary(_ files: [URL], savedOrder: [URL] = [], current: URL? = nil, position: TimeInterval = 0) {
        stopEverything()
        library = files
        let active = activeFiles()
        let restoring = current.flatMap { active.contains($0) ? $0 : nil }
        queue = PlayQueue(files: active, savedOrder: savedOrder, current: restoring)
        currentURL = restoring
        frozenElapsed = restoring == nil ? nil : position
        needsReschedule = true
    }

    /// Rescan result: merge without interrupting what's playing. Returns the number of new files.
    @discardableResult
    func mergeLibrary(_ files: [URL]) -> Int {
        let added = Set(files).subtracting(library).count
        library = files
        rebuildQueue()
        return added
    }

    func setFilter(_ filter: ((URL) -> Bool)?) {
        self.filter = filter
        rebuildQueue()
    }

    /// True when a filter is set but nothing matches, so the whole library is used instead.
    var filterFellBack: Bool {
        guard let filter else { return false }
        let all = playable
        return !all.isEmpty && !all.contains(where: filter)
    }

    /// Library files minus known-undecodable ones.
    var playable: [URL] { library.filter(isPlayable) }

    private func activeFiles() -> [URL] {
        let all = playable
        guard let filter else { return all }
        let matching = all.filter(filter)
        return matching.isEmpty ? all : matching
    }

    private func isPlayable(_ url: URL) -> Bool {
        guard let size = unplayable[url] else { return true }
        if Self.fileSize(url) != size {
            unplayable[url] = nil  // changed since it failed (e.g. a finished download); try again
            return true
        }
        return false
    }

    private func markUnplayable(_ urls: [URL]) {
        for url in urls {
            unplayable[url] = Self.fileSize(url)
            queue.remove(url)
        }
    }

    private static func fileSize(_ url: URL) -> Int {
        (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? -1
    }

    private func rebuildQueue() {
        queue.merge(activeFiles(), playing: currentURL)
        if prepared.map({ !queue.order.contains($0.url) }) ?? false { prepared = nil }
        if queue.isEmpty, currentURL != nil {
            stop()
            currentURL = nil
            frozenElapsed = nil
        }
    }

    // MARK: Transport

    @discardableResult
    func play() -> Bool {
        guard !queue.isEmpty, !isPlaying else { return false }
        cancelSleepFade()
        if currentURL != nil, decks[cur].file != nil, !needsReschedule, ensureEngine(), decks[cur].node.start() {
            startNoiseIfNeeded()
            isPlaying = true
            frozenElapsed = nil
            startMonitor()
        } else {
            let (i, position) = resumePoint(frozenElapsed ?? 0)
            isPlaying = startTrack(at: i, remember: false, position: position)
        }
        return isPlaying
    }

    @discardableResult
    func pause() -> Bool {
        guard isPlaying else { return false }
        cancelSleepFade()
        cancelPending()
        finishFade()
        frozenElapsed = elapsed
        decks[cur].node.pause()
        noiseNode.pause()
        engine.pause()
        isPlaying = false
        stopMonitor()
        return true
    }

    func toggle() -> ToggleResult {
        if queue.isEmpty { return .empty }
        if isPlaying {
            pause()
            return .pause
        }
        return play() ? .play : .empty
    }

    @discardableResult
    func next() -> Bool {
        guard let i = queue.nextIndex() else { return false }
        isPlaying = startTrack(at: i, remember: true)
        return isPlaying
    }

    @discardableResult
    func previous() -> Bool {
        guard let i = queue.previousIndex() else { return false }
        isPlaying = startTrack(at: i, remember: false)
        return isPlaying
    }

    func setVolume(_ value: Int) -> Int {
        volume = max(0, min(100, value))
        musicMixer.outputVolume = Float(volume) / 100
        return volume
    }

    func stop() {
        stopEverything()
        isPlaying = false
    }

    // MARK: Ambient noise

    func setNoise(_ kind: Noise.Kind, volume: Int) {
        noiseNode.volume = Float(max(0, min(100, volume))) / 100
        guard kind != noiseKind else { return }
        noiseKind = kind
        noiseNode.stop()
        noiseScheduled = false
        if isPlaying { startNoiseIfNeeded() }
    }

    private func startNoiseIfNeeded() {
        guard noiseKind != .off else { return }
        if !noiseScheduled, let buffer = Noise.buffer(noiseKind) {
            noiseNode.scheduleBuffer(buffer, at: nil, options: .loops)
            noiseScheduled = true
        }
        _ = noiseNode.start()
    }

    // MARK: Sleep fade

    /// Fade everything out over `seconds`, then pause and restore the level.
    func fadeOutAndPause(over seconds: TimeInterval, completion: @escaping () -> Void) {
        guard isPlaying else { completion(); return }
        cancelSleepFade()
        let start = Date()
        sleepFade = Timer.scheduledTimer(withTimeInterval: 1.0 / 20, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            let p = min(1, Date().timeIntervalSince(start) / seconds)
            self.engine.mainMixerNode.outputVolume = Float(1 - p)
            if p >= 1 {
                self.pause()  // cancels the fade and restores the level
                completion()
            }
        }
    }

    private func cancelSleepFade() {
        sleepFade?.invalidate()
        sleepFade = nil
        engine.mainMixerNode.outputVolume = 1
    }

    // MARK: Ignore / undo

    /// Move the current file to Ignored_Lofi (never overwriting) and continue with the next track.
    func ignoreCurrent(musicDir: String) -> Removed? {
        guard let url = currentURL, FileManager.default.fileExists(atPath: url.path) else { return nil }
        let ignored = Paths.ignoredDir(for: musicDir)
        let position = elapsed
        let dest: URL
        do {
            try FileManager.default.createDirectory(at: ignored, withIntermediateDirectories: true)
            dest = Paths.uniqueDestination(in: ignored, for: url.lastPathComponent)
            // Renaming an open file is safe; the deck keeps reading the same inode until replaced.
            try FileManager.default.moveItem(at: url, to: dest)
        } catch {
            Log.library.error("Ignore failed for \(url.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return nil
        }

        let wasPlaying = isPlaying
        library.removeAll { $0 == url }
        queue.remove(url)
        currentURL = nil
        if queue.isEmpty {
            stop()
        } else if wasPlaying, let i = queue.nextIndex() {
            isPlaying = startTrack(at: i, remember: false)
        } else {
            stopEverything()
            if let i = queue.nextIndex() {
                queue.select(i, remember: false)
                currentURL = queue.current
                frozenElapsed = 0
            }
        }
        return Removed(title: TitleCleaner.clean(url: url), original: url, moved: dest, position: position)
    }

    /// Move a removed song back and resume it where it left off.
    func undo(_ removed: Removed) -> Bool {
        let fm = FileManager.default
        guard fm.fileExists(atPath: removed.moved.path), !fm.fileExists(atPath: removed.original.path) else {
            return false
        }
        do {
            try fm.moveItem(at: removed.moved, to: removed.original)
        } catch {
            Log.library.error("Undo failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
        if !library.contains(removed.original) { library.append(removed.original) }
        queue.insertAsCurrent(removed.original)
        isPlaying = startTrack(at: queue.startIndex, remember: false, position: removed.position)
        return true
    }

    // MARK: Track start

    /// Where to (re)start: the current song at `position` if it's still queued, else the next song.
    private func resumePoint(_ position: TimeInterval) -> (Int, TimeInterval) {
        if let url = currentURL, let i = queue.order.firstIndex(of: url) { return (i, position) }
        return (queue.nextIndex() ?? 0, 0)
    }

    /// Start the queue entry at `start` (skipping files that can't be decoded) from `position`.
    private func startTrack(at start: Int, remember: Bool, position: TimeInterval = 0) -> Bool {
        stopEverything()
        guard !queue.isEmpty else { return false }
        var position = position
        var bad: [URL] = []
        defer { markUnplayable(bad) }
        for offset in 0..<queue.count {
            let i = (start + offset) % queue.count
            let url = queue.order[i]
            guard let file = openFile(url) else {
                bad.append(url)
                position = 0
                continue
            }
            let deck = decks[cur]
            guard load(deck, url: url, file: file, position: position), ensureEngine() else {
                position = 0
                continue
            }
            deck.node.volume = 1
            guard deck.node.start() else {
                deck.reset()
                position = 0
                continue
            }
            queue.select(i, remember: remember)
            startNoiseIfNeeded()
            currentURL = url
            frozenElapsed = nil
            needsReschedule = false
            lastKnownElapsed = position
            didStart(url)
            return true
        }
        currentURL = nil
        return false
    }

    private func didStart(_ url: URL) {
        transitionFailed = false
        startMonitor()
        preloadNext()
        DispatchQueue.main.async { [weak self] in self?.onTrackStarted?(url) }
    }

    private func openFile(_ url: URL) -> AVAudioFile? {
        if let prepared, prepared.url == url {
            self.prepared = nil
            return prepared.file
        }
        do {
            return try AVAudioFile(forReading: url)
        } catch {
            Log.audio.notice("Skipping undecodable file \(url.lastPathComponent, privacy: .public)")
            return nil
        }
    }

    /// Open the upcoming file on a background queue so the switch costs nothing on main.
    private func preloadNext() {
        guard let i = queue.nextIndex() else { return }
        let url = queue.order[i]
        guard prepared?.url != url, preloading != url else { return }
        preloading = url
        io.async { [weak self] in
            let file = try? AVAudioFile(forReading: url)
            DispatchQueue.main.async {
                guard let self, self.preloading == url else { return }
                self.preloading = nil
                if let file { self.prepared = (url, file) }
            }
        }
    }

    private func load(_ deck: Deck, url: URL, file: AVAudioFile, position: TimeInterval) -> Bool {
        let format = file.processingFormat
        let startFrame = max(0, min(AVAudioFramePosition(position * format.sampleRate), file.length - 1))
        guard file.length > 0, file.length - startFrame > 0 else { return false }
        if deck.connectedFormat != format {
            if deck.connectedFormat != nil { engine.disconnectNodeOutput(deck.node) }
            guard engine.link(deck.node, to: musicMixer, format: format) else {
                deck.connectedFormat = nil
                return false
            }
            deck.connectedFormat = format
        }
        deck.token += 1
        let token = deck.token
        let deckIndex = decks.firstIndex { $0 === deck }!
        deck.file = file
        deck.url = url
        deck.startFrame = startFrame
        deck.node.scheduleSegment(
            file, startingFrame: startFrame, frameCount: AVAudioFrameCount(file.length - startFrame),
            at: nil, completionCallbackType: .dataPlayedBack
        ) { [weak self] _ in
            DispatchQueue.main.async { self?.deckFinished(deckIndex, token: token) }
        }
        return true
    }

    private func ensureEngine() -> Bool {
        if engine.isRunning { return true }
        do {
            try engine.start()
            return true
        } catch {
            Log.audio.error("Audio engine failed to start: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    // MARK: Transitions

    private func startMonitor() {
        guard monitor == nil else { return }
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in self?.tick() }
        timer.tolerance = 0.05
        RunLoop.main.add(timer, forMode: .common)
        monitor = timer
    }

    private func stopMonitor() {
        monitor?.invalidate()
        monitor = nil
    }

    /// Schedule the next track on the idle deck shortly before the current one ends.
    private func tick() {
        guard isPlaying else { return }
        let deck = decks[cur]
        if let e = deck.elapsed { lastKnownElapsed = e }
        guard pending == nil, !transitionFailed, !stopAfterCurrent, let file = deck.file,
              let renderTime = deck.node.lastRenderTime, renderTime.isSampleTimeValid,
              let playerTime = deck.node.playerTime(forNodeTime: renderTime) else { return }

        let rate = file.processingFormat.sampleRate
        let remaining = Double(file.length - deck.startFrame - max(0, playerTime.sampleTime)) / rate
        let overlap = max(0, min(crossfade, deck.duration / 3, 12))
        guard remaining <= overlap + 1.5 else { return }

        guard let i = queue.nextIndex() else { return }
        let url = queue.order[i]
        guard let nextFile = openFile(url) else {
            markUnplayable([url])  // try the following song on the next tick
            return
        }
        let other = 1 - cur
        let nextDeck = decks[other]
        nextDeck.reset()
        guard load(nextDeck, url: url, file: nextFile, position: 0) else {
            transitionFailed = true
            return
        }

        let lead = max(0, remaining - overlap)
        let hostNow = renderTime.isHostTimeValid ? renderTime.hostTime : mach_absolute_time()
        let startHost = hostNow + AVAudioTime.hostTime(forSeconds: lead)
        nextDeck.node.volume = overlap > 0 ? 0 : 1
        guard nextDeck.node.start(at: AVAudioTime(hostTime: startHost)) else {
            nextDeck.reset()
            transitionFailed = true
            return
        }

        let delay = max(0, AVAudioTime.seconds(forHostTime: startHost) - AVAudioTime.seconds(forHostTime: mach_absolute_time()))
        let commit = DispatchWorkItem { [weak self] in self?.commitTransition() }
        pending = Pending(url: url, deck: other, overlap: overlap, commit: commit)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: commit)
    }

    private func commitTransition() {
        guard let p = pending else { return }
        pending = nil
        let old = decks[cur]
        cur = p.deck
        let new = decks[cur]
        queue.select(p.url, remember: true)
        currentURL = p.url
        lastKnownElapsed = 0

        if p.overlap > 0 {
            startFade(from: old, to: new, over: p.overlap)
        } else {
            let token = old.token
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                if old.token == token { old.reset() }
            }
        }
        didStart(p.url)
    }

    private func cancelPending() {
        guard let p = pending else { return }
        p.commit.cancel()
        decks[p.deck].reset()
        pending = nil
    }

    private func startFade(from old: Deck, to new: Deck, over seconds: TimeInterval) {
        finishFade()
        fadeDecks = (old, new)
        let start = Date()
        let timer = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            guard let self else { return }
            let p = min(1, Date().timeIntervalSince(start) / seconds)
            old.node.volume = Float(cos(p * .pi / 2))
            new.node.volume = Float(sin(p * .pi / 2))
            if p >= 1 { self.finishFade() }
        }
        RunLoop.main.add(timer, forMode: .common)
        fadeTimer = timer
    }

    /// Jump any running crossfade to its end state.
    private func finishFade() {
        fadeTimer?.invalidate()
        fadeTimer = nil
        guard let (old, new) = fadeDecks else { return }
        fadeDecks = nil
        old.reset()
        new.node.volume = 1
    }

    private func deckFinished(_ index: Int, token: Int) {
        guard isPlaying, index == cur, decks[index].token == token else { return }
        if pending != nil { return }  // the scheduled transition takes over
        if stopAfterCurrent {
            stopAfterCurrent = false
            stopEverything()
            isPlaying = false
            if let i = queue.nextIndex() {
                queue.select(i, remember: true)
                currentURL = queue.current
                frozenElapsed = 0
            }
            onStateChanged?()
            return
        }
        if !next() { onStateChanged?() }
    }

    // MARK: Engine lifecycle

    /// Output device changed: the engine stopped itself, so reload at the same position.
    private func engineConfigurationChanged() {
        let position = elapsed
        noiseScheduled = false
        if isPlaying {
            let (i, at) = resumePoint(position)
            isPlaying = startTrack(at: i, remember: false, position: at)
            if !isPlaying { onStateChanged?() }
        } else if currentURL != nil {
            stopEverything()
            frozenElapsed = position
        }
    }

    /// Stop decks, timers and the engine; keeps queue position and `currentURL`.
    private func stopEverything() {
        stopMonitor()
        cancelPending()
        finishFade()
        cancelSleepFade()
        decks.forEach { $0.reset() }
        noiseNode.stop()
        noiseScheduled = false
        prepared = nil
        preloading = nil
        engine.stop()
        needsReschedule = true
    }
}

/// One player node plus what's loaded on it.
private final class Deck {
    let node = AVAudioPlayerNode()
    /// Format the node is currently connected to the mixer with (nil = not connected).
    var connectedFormat: AVAudioFormat?
    var file: AVAudioFile?
    var url: URL?
    var startFrame: AVAudioFramePosition = 0
    /// Bumped on every load/reset so stale completion callbacks are ignored.
    var token = 0

    var duration: TimeInterval {
        guard let file else { return 0 }
        return Double(file.length) / file.processingFormat.sampleRate
    }

    var elapsed: TimeInterval? {
        guard let file, let t = node.lastRenderTime, t.isSampleTimeValid,
              let p = node.playerTime(forNodeTime: t) else { return nil }
        return Double(startFrame + max(0, p.sampleTime)) / file.processingFormat.sampleRate
    }

    func reset() {
        token += 1
        node.stop()
        node.volume = 1
        file = nil
        url = nil
        startFrame = 0
    }
}

// macOS 27 replaced the exception-throwing calls with error-returning ones; use them when available.
private extension AVAudioPlayerNode {
    func start(at time: AVAudioTime? = nil) -> Bool {
        if #available(macOS 27.0, *) {
            do {
                try playAudio(at: time)
                return true
            } catch {
                Log.audio.error("Player node failed to start: \(error.localizedDescription, privacy: .public)")
                return false
            }
        }
        play(at: time)
        return true
    }
}

private extension AVAudioEngine {
    func link(_ source: AVAudioNode, to destination: AVAudioNode, format: AVAudioFormat?) -> Bool {
        if #available(macOS 27.0, *) {
            do {
                try connectNode(source, to: destination, format: format)
                return true
            } catch {
                Log.audio.error("Audio connection failed: \(error.localizedDescription, privacy: .public)")
                return false
            }
        }
        connect(source, to: destination, format: format)
        return true
    }
}
