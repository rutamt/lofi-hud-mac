import Foundation
import MediaPlayer

/// Hardware media keys, AirPods/Bluetooth headset buttons, and Control Center
/// via the system Now Playing interface. No Accessibility permission required.
final class MediaKeys {
    enum Command { case toggle, play, pause, next, prev }

    static let debounce: TimeInterval = 0.3

    var onCommand: ((Command) -> Void)?
    private var lastPress = Date.distantPast
    private var targets: [(MPRemoteCommand, Any)] = []

    var isEnabled = false {
        didSet {
            guard isEnabled != oldValue else { return }
            isEnabled ? attach() : detach()
        }
    }

    private func attach() {
        let center = MPRemoteCommandCenter.shared()
        let pairs: [(MPRemoteCommand, Command)] = [
            (center.togglePlayPauseCommand, .toggle),
            (center.playCommand, .play),
            (center.pauseCommand, .pause),
            (center.nextTrackCommand, .next),
            (center.previousTrackCommand, .prev),
        ]
        for (command, kind) in pairs {
            command.isEnabled = true
            let token = command.addTarget { [weak self] _ in
                self?.handle(kind)
                return .success
            }
            targets.append((command, token))
        }
        for unused in [center.skipForwardCommand, center.skipBackwardCommand,
                       center.changePlaybackPositionCommand, center.seekForwardCommand,
                       center.seekBackwardCommand] {
            unused.isEnabled = false
        }
    }

    private func detach() {
        for (command, token) in targets {
            command.removeTarget(token)
            command.isEnabled = false
        }
        targets.removeAll()
    }

    private func handle(_ command: Command) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isEnabled else { return }
            let now = Date()
            guard now.timeIntervalSince(self.lastPress) >= Self.debounce else { return }
            self.lastPress = now
            self.onCommand?(command)
        }
    }

    /// Publish the current track to Control Center / the Now Playing widget.
    func updateNowPlaying(title: String?, isPlaying: Bool, elapsed: TimeInterval, duration: TimeInterval) {
        let center = MPNowPlayingInfoCenter.default()
        guard let title else {
            center.nowPlayingInfo = nil
            center.playbackState = .stopped
            return
        }
        center.nowPlayingInfo = [
            MPMediaItemPropertyTitle: title,
            MPMediaItemPropertyArtist: "LoFi HUD",
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: elapsed,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
        ]
        center.playbackState = isPlaying ? .playing : .paused
    }
}
