import AVFoundation

/// Shuffled, looping local-library player built on AVAudioPlayer.
/// Mirrors the VLC MediaListPlayer semantics of the original build. Main thread only.
final class Player: NSObject, AVAudioPlayerDelegate {
    static let validExtensions: Set<String> = [
        "mp3", "wav", "flac", "ogg", "m4a", "aac", "opus", "wma", "aif", "aiff", "alac", "caf",
    ]

    enum ToggleResult { case play, pause, empty }

    private(set) var songs: [URL] = []
    private(set) var isPlaying = false
    private(set) var currentURL: URL?
    private var index = 0
    private var audio: AVAudioPlayer?
    private var volume: Int

    /// Fires (asynchronously, after the triggering action) whenever a new track starts.
    var onTrackStarted: ((URL) -> Void)?
    /// Fires when play state changes for reasons other than a direct call (e.g. no playable files).
    var onStateChanged: (() -> Void)?

    init(volume: Int) {
        self.volume = max(0, min(100, volume))
    }

    var currentTitle: String? { currentURL.map(TitleCleaner.clean(url:)) }
    var duration: TimeInterval { audio?.duration ?? 0 }
    var elapsed: TimeInterval { audio?.currentTime ?? 0 }

    // MARK: Library

    /// Scan `musicDir` (skipping Ignored_Lofi), shuffle, and reset to a stopped state.
    func loadLibrary(_ musicDir: String) {
        stopAudio()
        isPlaying = false
        currentURL = nil
        index = 0
        songs = Self.scan(musicDir).shuffled()
    }

    static func scan(_ musicDir: String) -> [URL] {
        let root = URL(fileURLWithPath: (musicDir as NSString).expandingTildeInPath, isDirectory: true)
        guard let walker = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }

        var found: [URL] = []
        for case let url as URL in walker {
            if url.lastPathComponent.contains("Ignored_Lofi") {
                walker.skipDescendants()
                continue
            }
            if validExtensions.contains(url.pathExtension.lowercased()) {
                found.append(url)
            }
        }
        return found
    }

    // MARK: Transport

    @discardableResult
    func play() -> Bool {
        guard !songs.isEmpty, !isPlaying else { return false }
        if let audio {
            audio.play()
            isPlaying = true
        } else {
            isPlaying = startTrack(at: index)
        }
        return isPlaying
    }

    @discardableResult
    func pause() -> Bool {
        guard isPlaying else { return false }
        audio?.pause()
        isPlaying = false
        return true
    }

    func toggle() -> ToggleResult {
        if songs.isEmpty { return .empty }
        if isPlaying {
            pause()
            return .pause
        }
        return play() ? .play : .empty
    }

    @discardableResult
    func next() -> Bool {
        guard !songs.isEmpty else { return false }
        isPlaying = startTrack(at: (index + 1) % songs.count)
        return isPlaying
    }

    @discardableResult
    func previous() -> Bool {
        guard !songs.isEmpty else { return false }
        isPlaying = startTrack(at: (index - 1 + songs.count) % songs.count)
        return isPlaying
    }

    func setVolume(_ value: Int) -> Int {
        volume = max(0, min(100, value))
        audio?.volume = Float(volume) / 100
        return volume
    }

    func stop() {
        stopAudio()
        isPlaying = false
    }

    /// Move the current file to Ignored_Lofi and continue with the next track.
    /// Returns the cleaned title of the removed song, or nil on failure.
    func ignoreCurrent(musicDir: String) -> String? {
        guard let url = currentURL, FileManager.default.fileExists(atPath: url.path) else { return nil }
        let title = TitleCleaner.clean(url: url)
        let ignored = Paths.ignoredDir(for: musicDir)
        let dest = ignored.appendingPathComponent(url.lastPathComponent)
        do {
            try FileManager.default.createDirectory(at: ignored, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: dest.path) {
                try FileManager.default.removeItem(at: dest)
            }
            stopAudio()
            try FileManager.default.moveItem(at: url, to: dest)
        } catch {
            return nil
        }

        if let i = songs.firstIndex(of: url) {
            songs.remove(at: i)
            if i < index { index -= 1 }
        }
        currentURL = nil
        if songs.isEmpty {
            isPlaying = false
        } else {
            // The list shifted left, so the "next" song now lives at the current index.
            isPlaying = startTrack(at: index % songs.count)
        }
        return title
    }

    // MARK: Internals

    /// Start the track at `start`, skipping files AVFoundation can't decode.
    private func startTrack(at start: Int) -> Bool {
        stopAudio()
        for offset in 0..<songs.count {
            let i = (start + offset) % songs.count
            guard let player = try? AVAudioPlayer(contentsOf: songs[i]) else { continue }
            player.delegate = self
            player.volume = Float(volume) / 100
            guard player.play() else { continue }
            audio = player
            index = i
            currentURL = songs[i]
            let url = songs[i]
            DispatchQueue.main.async { [weak self] in self?.onTrackStarted?(url) }
            return true
        }
        currentURL = nil
        return false
    }

    private func stopAudio() {
        audio?.delegate = nil
        audio?.stop()
        audio = nil
    }

    private func advanceAfterEnd() {
        guard isPlaying else { return }
        if !next() { onStateChanged?() }
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async { [weak self] in
            guard let self, player === self.audio else { return }
            self.advanceAfterEnd()
        }
    }

    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        DispatchQueue.main.async { [weak self] in
            guard let self, player === self.audio else { return }
            self.advanceAfterEnd()
        }
    }
}
