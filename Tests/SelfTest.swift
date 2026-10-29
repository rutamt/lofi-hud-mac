// Dependency-free test runner (works with Command Line Tools only; no XCTest/Testing macros).
// Run with: scripts/test.sh
import Foundation

var failures = 0
var passes = 0

func check(_ ok: @autoclosure () -> Bool, _ what: String, file: String = #file, line: Int = #line) {
    if ok() {
        passes += 1
    } else {
        failures += 1
        print("✗ \(what)  (\((file as NSString).lastPathComponent):\(line))")
    }
}

func tempURL() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("lofi-\(UUID().uuidString).json")
}

// MARK: Title cleaning
for (input, expected) in [
    ("y2mate.com - chill_beats-to_study.mp3", "Chill Beats To Study"),
    ("01 - Rainy Night.flac", "Rainy Night"),
    ("3. late night (Official Audio).m4a", "Late Night"),
    ("Snaptik_Coffee Shop [LOFI HIP HOP].wav", "Coffee Shop"),
    ("dont_stop [320 kbps] (HQ).mp3", "Dont Stop"),
    ("don't look back.mp3", "Don't Look Back"),
    ("___.mp3", "Unknown Track"),
] {
    let got = TitleCleaner.clean(filename: input)
    check(got == expected, "clean(\(input)) = \(got), expected \(expected)")
}

// MARK: Config compatibility with the Python build
do {
    let url = tempURL()
    defer { try? FileManager.default.removeItem(at: url) }
    try! """
        {"music_dir": "/tmp/LoFi", "mod_key": "ALT", "volume": 140, "theme": "Gruvbox Warm",
         "hud_position": "Top Left", "show_now_playing": false, "unknown_key": 1}
        """.write(to: url, atomically: true, encoding: .utf8)
    let c = ConfigStore.load(from: url)
    check(c.musicDir == "/tmp/LoFi", "music_dir read")
    check(c.modKey == "option", "alt → option")
    check(c.volume == 100, "volume clamped")
    check(c.theme == "gruvbox", "legacy theme label mapped")
    check(c.hudPosition == "Top Left", "hud_position read")
    check(c.showNowPlaying == false, "bool read")
    check(c.keyPlay == "q", "missing keys default")
    check(c.showDockIcon == true, "show_dock_icon defaults on for old configs")
}
do {
    let url = tempURL()
    defer { try? FileManager.default.removeItem(at: url) }
    var c = AppConfig.default
    c.volume = 70
    ConfigStore.save(c, to: url)
    let raw = try! String(contentsOf: url, encoding: .utf8)
    check(raw.contains("\"hud_song_timeout\""), "snake_case keys on disk")
    check(raw.contains("\"show_dock_icon\""), "show_dock_icon persisted")
    check(raw.contains("\"theme\" : \"system\""), "System (Auto) persists")
    check(ConfigStore.load(from: url) == c, "round trip")
}
do {
    let url = tempURL()
    let bak = url.appendingPathExtension("bak")
    defer { try? FileManager.default.removeItem(at: url); try? FileManager.default.removeItem(at: bak) }
    try! "{ not json".write(to: url, atomically: true, encoding: .utf8)
    check(ConfigStore.load(from: url) == .default, "corrupt → defaults")
    check(FileManager.default.fileExists(atPath: bak.path), "corrupt file backed up")
}

// MARK: Themes
check(Themes.canonicalID("Paper") == "latte", "legacy Paper → latte")
check(Themes.canonicalID("System (Auto)") == "system", "System (Auto) label")
check(Themes.canonicalID("nonsense") == "system", "unknown → system")
check(["harbor_night", "system_light"].contains(Themes.resolve("system").id), "system resolves")

// MARK: Key codes
check(KeyCodes.keyCode(for: "up") == 126, "up")
check(KeyCodes.keyCode(for: "space") == 49, "space")
check(KeyCodes.keyCode(for: "q") != nil, "q")
check(KeyCodes.keyCode(for: "2") != nil, "2")
check(KeyCodes.keyCode(for: "notakey") == nil, "invalid key")
check(KeyCodes.name(for: 126) == "up", "reverse up")
if let q = KeyCodes.keyCode(for: "q") { check(KeyCodes.name(for: q) == "q", "reverse q") }

// MARK: Library scan & paths
do {
    let fm = FileManager.default
    let root = fm.temporaryDirectory.appendingPathComponent("lofi-scan-\(UUID().uuidString)")
    defer { try? fm.removeItem(at: root) }
    try! fm.createDirectory(at: root.appendingPathComponent("sub/Ignored_Lofi"), withIntermediateDirectories: true)
    for name in ["a.mp3", "b.FLAC", "notes.txt", "sub/c.m4a", "sub/Ignored_Lofi/d.mp3"] {
        fm.createFile(atPath: root.appendingPathComponent(name).path, contents: Data())
    }
    let names = Set(Player.scan(root.path).map(\.lastPathComponent))
    check(names == ["a.mp3", "b.FLAC", "c.m4a"], "scan result \(names)")
}
check(Paths.ignoredDir(for: "/Users/x/Music/LoFi/").path == "/Users/x/Music/Ignored_Lofi", "Ignored_Lofi sibling")

print(failures == 0 ? "✓ all \(passes) checks passed" : "\(failures) failed, \(passes) passed")
exit(failures == 0 ? 0 : 1)
