import Foundation

/// Filesystem locations. Kept identical to the Python build so existing
/// settings and music folders carry over untouched.
enum Paths {
    static let bundleID = "com.rutamt.lofihud"

    /// Developer override: `LOFIHUD_HOME=/some/dir` isolates config and skips
    /// system integration (login items), so test runs never touch a real install.
    static let devHome = ProcessInfo.processInfo.environment["LOFIHUD_HOME"].flatMap { $0.isEmpty ? nil : $0 }

    static var appSupportDir: URL {
        let dir = devHome.map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support/LoFiHUD", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static var configURL: URL { appSupportDir.appendingPathComponent("config.json") }
    static var lockURL: URL { appSupportDir.appendingPathComponent("lofi_hud.lock") }

    static var defaultMusicDir: String {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Music/LoFi", isDirectory: true).path
    }

    /// Legacy LaunchAgent written by the Python build.
    static var legacyLaunchAgent: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/com.rutamt.lofihud.plist")
    }

    /// Sibling `Ignored_Lofi` folder next to the configured music directory.
    static func ignoredDir(for musicDir: String) -> URL {
        URL(fileURLWithPath: (musicDir as NSString).standardizingPath)
            .deletingLastPathComponent()
            .appendingPathComponent("Ignored_Lofi", isDirectory: true)
    }

    static func ensureDirectory(_ path: String) {
        guard !path.isEmpty else { return }
        try? FileManager.default.createDirectory(
            atPath: (path as NSString).expandingTildeInPath, withIntermediateDirectories: true)
    }
}
