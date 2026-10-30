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
    check(c.keyFavorite == "5" && c.crossfade == 0 && c.noise == "off", "new keys default")
    check(c.autoDarkTheme == "harbor_night" && c.accentMode == "theme", "theme options default")
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

do {
    let url = tempURL()
    defer { try? FileManager.default.removeItem(at: url) }
    try! #"{"crossfade": 99, "noise_volume": -4, "accent_mode": "rainbow", "auto_dark_theme": "nope"}"#
        .write(to: url, atomically: true, encoding: .utf8)
    let c = ConfigStore.load(from: url)
    check(c.crossfade == 12 && c.noiseVolume == 0, "numeric settings clamped")
    check(c.accentMode == "theme" && c.autoDarkTheme == "harbor_night", "invalid options reset")
}
do {
    let url = tempURL()
    defer { try? FileManager.default.removeItem(at: url) }
    var st = PlaybackState()
    st.order = ["/a.mp3", "/b.mp3"]
    st.current = "/b.mp3"
    st.position = 12.5
    st.favorites = ["/a.mp3"]
    st.save(to: url)
    check(PlaybackState.load(from: url) == st, "playback state round trip")
}

// MARK: Themes
check(Themes.all.count == 14, "14 preset themes")
check(Set(Themes.all.map(\.id)).count == Themes.all.count, "theme ids unique")
check(Themes.canonicalID("Dracula") == "dracula", "new theme label maps")
check(["mocha", "latte"].contains(Themes.resolve("system", light: "latte", dark: "mocha").id), "custom auto pair")
do {
    var c = AppConfig.default
    c.theme = "gruvbox"
    c.accentMode = "custom"
    c.customAccent = "#ffeb3b"
    let t = Themes.resolve(c)
    check(t.accent == "#ffeb3b", "custom accent applied")
    check(t.onAccent == "#1a1a1a", "light accent gets dark text")
    c.customAccent = "#1b3a8a"
    check(Themes.resolve(c).onAccent == "#ffffff", "dark accent gets white text")
}
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

// MARK: Key combos
check(KeyCombo("q", defaultModifier: "cmd").stringValue == "cmd+q", "legacy bare key uses mod_key")
check(KeyCombo("shift+option+q").stringValue == "option+shift+q", "combo canonical order")
check(KeyCombo("ctrl+option+shift+cmd+up").display == "⌃⌥⇧⌘↑", "combo display")
check(KeyCombo("cmd+q").isCommonShortcut, "⌘Q flagged")
check(!KeyCombo("option+q").isCommonShortcut, "⌥Q fine")
check(KeyCombo("option+=").key == "=", "symbol key parse")
do {
    var c = AppConfig.default
    c.modKey = "ctrl"
    Hotkeys.setBinding(.favorite, KeyCombo("cmd+shift+f"), in: &c)
    check(c.keyFavorite == "shift+cmd+f", "setBinding stores combo")
    check(Hotkeys.combo(.play, in: c).stringValue == "ctrl+q", "legacy binding resolved per action")
}

// MARK: Play queue
do {
    let files = (0..<6).map { URL(fileURLWithPath: "/m/\($0).mp3") }
    var q = PlayQueue(files: files)
    check(q.count == 6 && Set(q.order) == Set(files), "queue holds all files")
    check(q.current == nil && q.nextIndex() == 0, "fresh queue starts at 0")

    // Walk a full cycle; the wrap reshuffle must not repeat the last song.
    var played: [URL] = []
    for _ in 0..<6 { q.select(q.nextIndex()!, remember: true); played.append(q.current!) }
    check(Set(played).count == 6, "one cycle plays every song once")
    let last = q.current!
    let n1 = q.nextIndex()!
    let n2 = q.nextIndex()!
    check(n1 == n2, "nextIndex is idempotent across the wrap")
    q.select(n1, remember: true)
    check(q.current != last, "no repeat across reshuffle")
    check(q.previousIndex().map { q.order[$0] } == last, "previous follows history across reshuffle")

    // Saved order and current are restored.
    let saved = Array(files.reversed())
    let r = PlayQueue(files: files, savedOrder: saved, current: files[2])
    check(r.order == saved && r.current == files[2], "restore order and current")
    let extra = URL(fileURLWithPath: "/m/new.mp3")
    let r2 = PlayQueue(files: files + [extra], savedOrder: saved, current: nil)
    check(r2.order.prefix(6) == saved[...] && r2.order.last == extra, "new file appended to saved order")

    // Merge keeps the current song and only adds new ones after it.
    var m = PlayQueue(files: files, savedOrder: files, current: files[3])
    m.merge(files + [extra], playing: files[3])
    check(m.current == files[3], "merge keeps current")
    check(m.order.firstIndex(of: extra)! > 3, "new song lands in the upcoming part")
    m.merge(files.filter { $0 != files[1] }, playing: files[3])
    check(!m.order.contains(files[1]) && m.current == files[3], "merge drops deleted files")

    // Removing the current song makes the next song slide in.
    var d = PlayQueue(files: files, savedOrder: files, current: files[2])
    d.remove(files[2])
    check(d.order[d.nextIndex()!] == files[3], "after removing current, next is the following song")
    d.insertAsCurrent(files[2])
    check(d.current == files[2], "undo re-inserts as current")

    // Filtered queue whose playing song isn't in the set.
    var f = PlayQueue(files: files, savedOrder: files, current: files[4])
    f.merge([files[0], files[5]], playing: files[4])
    check(f.current == nil && f.order[f.nextIndex()!] == files[5], "filtered queue continues after anchor")
}

// MARK: Library scan & paths
do {
    let fm = FileManager.default
    let root = fm.temporaryDirectory.appendingPathComponent("lofi-scan-\(UUID().uuidString)")
    defer { try? fm.removeItem(at: root) }
    try! fm.createDirectory(at: root.appendingPathComponent("sub/Ignored_Lofi"), withIntermediateDirectories: true)
    for name in ["a.mp3", "b.FLAC", "notes.txt", "sub/c.m4a", "sub/Ignored_Lofi/d.mp3"] {
        fm.createFile(atPath: root.appendingPathComponent(name).path, contents: Data())
    }
    fm.createFile(atPath: root.appendingPathComponent("e.ogg").path, contents: Data())
    let names = Set(Library.scan(root.path).map(\.lastPathComponent))
    check(names == ["a.mp3", "b.FLAC", "c.m4a"], "scan result \(names)")

    let ignored = root.appendingPathComponent("ign")
    try! fm.createDirectory(at: ignored, withIntermediateDirectories: true)
    check(Paths.uniqueDestination(in: ignored, for: "x.mp3").lastPathComponent == "x.mp3", "unique: free name")
    fm.createFile(atPath: ignored.appendingPathComponent("x.mp3").path, contents: Data())
    fm.createFile(atPath: ignored.appendingPathComponent("x 2.mp3").path, contents: Data())
    check(Paths.uniqueDestination(in: ignored, for: "x.mp3").lastPathComponent == "x 3.mp3", "unique: never overwrites")
}
check(Paths.ignoredDir(for: "/Users/x/Music/LoFi/").path == "/Users/x/Music/Ignored_Lofi", "Ignored_Lofi sibling")

// MARK: Updates
check(Updater.isNewer("2.10.0", than: "2.9.1"), "numeric version compare")
check(!Updater.isNewer("2.1.0", than: "2.1"), "equal versions")
check(!Updater.isNewer("2.0.9", than: "2.1.0"), "older version")
do {
    let json = #"{"tag_name":"v2.2.0","html_url":"https://github.com/x/y/releases/tag/v2.2.0","assets":[{"name":"LoFiHUD_v2.2.0.dmg","browser_download_url":"https://github.com/x/y/releases/download/v2.2.0/LoFiHUD_v2.2.0.dmg"}]}"#
    let r = Updater.parse(Data(json.utf8))
    check(r?.version == "2.2.0" && r?.dmg?.lastPathComponent == "LoFiHUD_v2.2.0.dmg", "release parse")
}

print(failures == 0 ? "✓ all \(passes) checks passed" : "\(failures) failed, \(passes) passed")
exit(failures == 0 ? 0 : 1)
