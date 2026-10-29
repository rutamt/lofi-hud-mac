import AppKit

/// Removes the login item, settings, and (optionally) the music library.
/// Music is preserved unless explicitly requested.
enum Uninstaller {
    /// - Parameter deleteMusic: `nil` asks the user (defaulting to Keep).
    static func run(deleteMusic: Bool?, showDialogs: Bool = true) {
        let config = ConfigStore.load()
        let musicDir = (config.musicDir as NSString).expandingTildeInPath
        let fm = FileManager.default
        let musicExists = fm.fileExists(atPath: musicDir)

        var deleteMusic = deleteMusic
        if deleteMusic == nil {
            if showDialogs && musicExists {
                let alert = NSAlert()
                alert.messageText = "Remove Music Library?"
                alert.informativeText = """
                    Do you also want to permanently delete your music folder and all downloaded songs?

                    Folder: \(musicDir)
                    """
                alert.alertStyle = .warning
                alert.addButton(withTitle: "Keep Music")
                alert.addButton(withTitle: "Delete Music").hasDestructiveAction = true
                deleteMusic = alert.runModal() == .alertSecondButtonReturn
            } else {
                deleteMusic = false
            }
        }

        LoginItem.unregister()

        let supportDir = Paths.appSupportDir
        if supportDir.standardizedFileURL.path != URL(fileURLWithPath: musicDir).standardizedFileURL.path {
            try? fm.removeItem(at: supportDir)
        }
        UserDefaults.standard.removePersistentDomain(forName: Paths.bundleID)

        if deleteMusic == true, musicExists {
            deleteLibrary(musicDir)
        }

        guard showDialogs else { return }
        let done = NSAlert()
        done.messageText = "LoFi HUD Uninstalled"
        if deleteMusic == true {
            done.informativeText = "Login item, settings, and your music library have been completely removed."
        } else if musicExists {
            done.informativeText = """
                Login item and settings have been cleanly removed.

                Your songs in \(musicDir) have been safely preserved.
                """
        } else {
            done.informativeText = "Login item and settings have been cleanly removed."
        }
        done.runModal()
    }

    /// Delete the library; for broad user folders only remove audio files, never the folder itself.
    private static func deleteLibrary(_ musicDir: String) {
        let fm = FileManager.default
        try? fm.removeItem(at: Paths.ignoredDir(for: musicDir))

        let home = fm.homeDirectoryForCurrentUser.standardizedFileURL.path.lowercased()
        let dangerous: Set<String> = [
            home, "/", home + "/desktop", home + "/documents", home + "/downloads", home + "/music",
        ]
        let target = URL(fileURLWithPath: musicDir).standardizedFileURL.path.lowercased()
        if dangerous.contains(target) {
            for url in Player.scan(musicDir) { try? fm.removeItem(at: url) }
        } else {
            try? fm.removeItem(atPath: musicDir)
        }
    }

    /// Move the running .app bundle to the Trash (only when installed as a bundle).
    static func trashAppBundle() {
        let bundle = Bundle.main.bundleURL
        guard bundle.pathExtension == "app" else { return }
        NSWorkspace.shared.recycle([bundle]) { _, _ in }
    }
}
