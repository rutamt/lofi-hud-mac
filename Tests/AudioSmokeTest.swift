// Real-audio smoke test for Player (AVAudioEngine). Plays quiet tones through the default output.
// Run with: scripts/test.sh --audio
import AVFoundation

var failures = 0
var passes = 0

func check(_ ok: @autoclosure () -> Bool, _ what: String, line: Int = #line) {
    if ok() {
        passes += 1
        print("  ✓ \(what)")
    } else {
        failures += 1
        print("  ✗ \(what)  (line \(line))")
    }
}

/// Spin the main run loop (timers, main-queue callbacks) for `seconds`.
func wait(_ seconds: TimeInterval) {
    RunLoop.main.run(until: Date().addingTimeInterval(seconds))
}

/// Write a quiet sine tone. Mixed sample rates and channel counts exercise deck reconnection.
func tone(_ url: URL, seconds: Double, freq: Double, rate: Double = 44_100, channels: AVAudioChannelCount = 2) {
    let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: channels)!
    let file = try! AVAudioFile(forWriting: url, settings: format.settings)
    let frames = AVAudioFrameCount(seconds * rate)
    let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
    buf.frameLength = frames
    for ch in 0..<Int(channels) {
        for i in 0..<Int(frames) { buf.floatChannelData![ch][i] = Float(sin(2 * .pi * freq * Double(i) / rate) * 0.02) }
    }
    try! file.write(from: buf)
}

let fm = FileManager.default
let root = fm.temporaryDirectory.appendingPathComponent("lofi-audio-\(UUID().uuidString)")
let music = root.appendingPathComponent("LoFi")
try! fm.createDirectory(at: music, withIntermediateDirectories: true)
defer { try? fm.removeItem(at: root) }

tone(music.appendingPathComponent("a.caf"), seconds: 2.0, freq: 440)
tone(music.appendingPathComponent("b.caf"), seconds: 2.0, freq: 550)
tone(music.appendingPathComponent("c.caf"), seconds: 2.0, freq: 660)
fm.createFile(atPath: music.appendingPathComponent("broken.mp3").path, contents: Data("not audio".utf8))

let files = Library.scan(music.path)
let player = Player(volume: 30)
var started: [URL] = []
player.onTrackStarted = { started.append($0) }
var stateChanges = 0
player.onStateChanged = { stateChanges += 1 }

print("Basic transport")
player.setLibrary(files)
check(player.songs.count == 4, "library loaded (4 files incl. broken)")
check(player.play(), "play starts")
wait(0.6)
check(player.isPlaying && player.currentURL != nil, "playing with a current track")
check(player.currentURL?.lastPathComponent != "broken.mp3", "undecodable file skipped")
player.next(); player.next(); player.next()
check(!player.songs.contains { $0.lastPathComponent == "broken.mp3" }, "undecodable file dropped from the queue")
check(player.playable.count == 3, "playable count excludes it")
wait(0.6)
check(player.elapsed > 0.3, "elapsed advances (\(String(format: "%.2f", player.elapsed)))")
check(player.duration > 1.9 && player.duration < 2.1, "duration read")

player.pause()
let frozen = player.elapsed
wait(0.4)
check(abs(player.elapsed - frozen) < 0.01, "elapsed frozen while paused")
player.play()
wait(0.3)
check(player.elapsed > frozen && player.elapsed < frozen + 0.6, "resume continues from the same spot")

print("Gapless auto-advance")
let first = player.currentURL
started.removeAll()
wait(2.4)
check(player.currentURL != first, "advanced to the next track on its own")
check(started.count >= 1, "onTrackStarted fired for the transition")
check(player.isPlaying, "still playing after transition")

print("Gap measurement")
// Tap the output and find the longest run of silent frames across one track change.
final class GapMeter: @unchecked Sendable {
    let lock = NSLock()
    var run = 0, longest = 0, frames = 0
    func feed(_ buf: AVAudioPCMBuffer) {
        guard let d = buf.floatChannelData else { return }
        lock.lock(); defer { lock.unlock() }
        for i in 0..<Int(buf.frameLength) {
            if abs(d[0][i]) < 1e-5 { run += 1; longest = max(longest, run) } else { run = 0 }
        }
        frames += Int(buf.frameLength)
    }
}
let meter = GapMeter()
player.next()
wait(0.3)
player.outputMixer.installTap(onBus: 0, bufferSize: 1024, format: nil) { buf, _ in meter.feed(buf) }
let gapFirst = player.currentURL
let gapStart = Date()
while player.currentURL == gapFirst && Date().timeIntervalSince(gapStart) < 3 { wait(0.05) }
wait(0.5)
player.outputMixer.removeTap(onBus: 0)
let rate = player.outputMixer.outputFormat(forBus: 0).sampleRate
let gapMs = Double(meter.longest) / rate * 1000
check(meter.frames > 0, "tap received audio")
check(gapMs < 3, "gapless: longest silence across the transition \(String(format: "%.2f", gapMs)) ms")

print("Next / previous")
let beforeNext = player.currentURL
player.next()
wait(0.2)
let afterNext = player.currentURL
check(afterNext != beforeNext, "next changes track")
player.previous()
wait(0.2)
check(player.currentURL == beforeNext, "previous returns to the song before")

print("Crossfade")
player.crossfade = 1.0
player.next()
let cfStart = Date()
let cfFirst = player.currentURL
var switchedAfter: TimeInterval?
while Date().timeIntervalSince(cfStart) < 3 {
    wait(0.05)
    if player.currentURL != cfFirst { switchedAfter = Date().timeIntervalSince(cfStart); break }
}
check(switchedAfter != nil, "crossfade transition happened")
if let s = switchedAfter { check(s < 1.5, "next track starts ~1 s early (\(String(format: "%.2f", s)) s)") }
wait(1.2)
check(player.isPlaying, "playing after crossfade completes")
player.crossfade = 0

print("Merge keeps playing")
let playingNow = player.currentURL
// 48 kHz mono: forces a deck reconnect with a different format.
tone(music.appendingPathComponent("d.caf"), seconds: 2.0, freq: 770, rate: 48_000, channels: 1)
let added = player.mergeLibrary(Library.scan(music.path))
check(added == 1, "merge reports 1 new file")
check(player.currentURL == playingNow && player.isPlaying, "merge didn't interrupt playback")

print("Mixed formats")
for _ in 0..<6 where player.currentURL?.lastPathComponent != "d.caf" { player.next() }
check(player.currentURL?.lastPathComponent == "d.caf", "reached the 48 kHz mono file")
wait(0.4)
check(player.isPlaying && player.elapsed > 0.2, "48 kHz mono plays (\(String(format: "%.2f", player.elapsed)))")
let mixedFrom = player.currentURL
let mixedStart = Date()
while player.currentURL == mixedFrom && Date().timeIntervalSince(mixedStart) < 3 { wait(0.05) }
check(player.currentURL != mixedFrom && player.isPlaying, "gapless hand-off across formats")

print("Ignore and undo")
let ignoredDir = Paths.ignoredDir(for: music.path)
try! fm.createDirectory(at: ignoredDir, withIntermediateDirectories: true)
let victim = player.currentURL!
fm.createFile(atPath: ignoredDir.appendingPathComponent(victim.lastPathComponent).path, contents: Data("older".utf8))
let removed = player.ignoreCurrent(musicDir: music.path)
check(removed != nil, "ignore succeeded")
check(!fm.fileExists(atPath: victim.path), "file moved out of the library")
check(fm.contents(atPath: ignoredDir.appendingPathComponent(victim.lastPathComponent).path) == Data("older".utf8),
      "existing file in Ignored_Lofi not overwritten")
check(removed?.moved.lastPathComponent.contains(" 2.") == true, "moved under a unique name")
check(player.isPlaying && player.currentURL != victim, "continued with another track")
if let removed {
    check(player.undo(removed), "undo succeeded")
    check(fm.fileExists(atPath: victim.path), "file restored")
    check(player.currentURL == victim && player.isPlaying, "restored song is playing again")
}

print("Stop after current")
player.stopAfterCurrent = true
let sacStart = Date()
while player.isPlaying && Date().timeIntervalSince(sacStart) < 3 { wait(0.05) }
check(!player.isPlaying, "paused at end of track")
check(stateChanges >= 1, "onStateChanged fired")
check(player.currentURL != nil && player.elapsed == 0, "next song cued at 0:00")
check(player.play(), "can resume afterwards")
wait(0.2)

print("Noise and sleep fade")
player.setNoise(.brown, volume: 10)
wait(0.3)
player.setNoise(.pink, volume: 10)
wait(0.3)
player.setNoise(.off, volume: 10)
check(player.isPlaying, "noise layer toggles without disturbing playback")
var faded = false
player.fadeOutAndPause(over: 0.5) { faded = true }
wait(0.8)
check(faded && !player.isPlaying, "sleep fade pauses")

print("Restore saved position")
let resumeURL = files.first { $0.lastPathComponent == "c.caf" }!
player.setLibrary(Library.scan(music.path), savedOrder: [], current: resumeURL, position: 1.2)
check(player.currentURL == resumeURL && !player.isPlaying, "restored paused on saved track")
player.play()
wait(0.2)
check(player.currentURL == resumeURL && player.elapsed >= 1.2, "resumed at saved position (\(String(format: "%.2f", player.elapsed)))")
player.stop()

print(failures == 0 ? "✓ all \(passes) audio checks passed" : "\(failures) failed, \(passes) passed")
exit(failures == 0 ? 0 : 1)
