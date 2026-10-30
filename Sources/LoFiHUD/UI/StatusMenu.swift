import AppKit

/// Menu bar item. The menu is rebuilt each time it opens, so idle cost is zero.
final class StatusMenu: NSObject, NSMenuDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let menu = NSMenu()
    private unowned let app: AppController
    private var isPlayingIcon: Bool?

    init(app: AppController) {
        self.app = app
        super.init()
        item.button?.toolTip = "LoFi HUD Idle"
        setIcon(playing: false)
        menu.delegate = self
        menu.autoenablesItems = false
        item.menu = menu
    }

    func update(tooltip: String, playing: Bool) {
        item.button?.toolTip = String(tooltip.prefix(120))
        setIcon(playing: playing)
    }

    private func setIcon(playing: Bool) {
        guard isPlayingIcon != playing else { return }
        isPlayingIcon = playing
        let image = NSImage(
            systemSymbolName: playing ? "waveform" : "music.note",
            accessibilityDescription: playing ? "LoFi HUD, playing" : "LoFi HUD")
        image?.isTemplate = true
        item.button?.image = image
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let player = app.player
        let playing = player.isPlaying
        let title = player.currentTitle
        let config = app.config

        menu.addItem(nowPlayingHeader(title: title, playing: playing))
        menu.addItem(volumeItem(config.volume))
        menu.addItem(.separator())

        add(playing ? "Pause" : "Play", symbol: playing ? "pause.fill" : "play.fill") { [app] in app.toggleAudio() }
        add("Next Track", symbol: "forward.fill") { [app] in app.nextTrack() }
        add("Previous Track", symbol: "backward.fill", enabled: title != nil) { [app] in app.previousTrack() }
        menu.addItem(.separator())

        let fav = app.isFavorite(player.currentURL)
        add(fav ? "Unfavorite" : "Favorite", symbol: fav ? "heart.slash" : "heart", enabled: title != nil) { [app] in
            app.toggleFavorite()
        }
        add("Remove Song", symbol: "trash", enabled: title != nil) { [app] in app.ignoreCurrentSong() }
        if let removed = app.lastRemoved {
            add("Undo Remove “\(removed.title.prefix(30))”", symbol: "arrow.uturn.backward") { [app] in app.undoRemove() }
        }
        let favOnly = add("Favorites Only", symbol: "heart.circle") { [app] in
            app.update { $0.favoritesOnly.toggle() }
        }
        favOnly.state = config.favoritesOnly ? .on : .off
        menu.addItem(.separator())

        menu.addItem(submenu("Sleep Timer", symbol: "moon.zzz", items: sleepItems()))
        menu.addItem(submenu("Ambient Noise", symbol: "wind", items: noiseItems(config)))
        menu.addItem(.separator())

        add("Rescan Library", symbol: "arrow.clockwise") { [app] in app.rescanLibrary() }
        add("Open Music Folder", symbol: "folder") { [app] in app.openMusicFolder() }
        menu.addItem(.separator())

        if let update = app.availableUpdate {
            add("Update Available: \(update.version)…", symbol: "arrow.down.circle.fill") {
                Updater.presentAvailable(update)
            }
        } else {
            add("Check for Updates…", symbol: "arrow.down.circle") { [app] in app.checkForUpdates(interactive: true) }
        }
        add("Settings…", symbol: "gearshape", key: ",") { [app] in app.openSettings() }
        add("Quit LoFi HUD", symbol: nil, key: "q") { [app] in app.quit() }
    }

    // MARK: Builders

    private func nowPlayingHeader(title: String?, playing: Bool) -> NSMenuItem {
        let header = NSMenuItem(title: title ?? "Nothing playing", action: nil, keyEquivalent: "")
        header.isEnabled = false
        header.image = NSImage(
            systemSymbolName: playing ? "waveform" : (title == nil ? "music.note" : "pause.circle"),
            accessibilityDescription: nil)
        guard let title else { return header }

        let text = NSMutableAttributedString(
            string: title, attributes: [.font: NSFont.systemFont(ofSize: 13, weight: .semibold)])
        var details: [String] = []
        let player = app.player
        if player.duration > 0 { details.append("\(Self.time(player.elapsed)) / \(Self.time(player.duration))") }
        if app.isFavorite(player.currentURL) { details.append("♥ Favorite") }
        if let sleep = app.sleepDescription { details.append(sleep) }
        if !details.isEmpty {
            text.append(NSAttributedString(
                string: "\n" + details.joined(separator: "  •  "),
                attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor]))
        }
        header.attributedTitle = text
        return header
    }

    private func volumeItem(_ volume: Int) -> NSMenuItem {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 240, height: 30))
        let low = NSImageView(image: NSImage(systemSymbolName: "speaker.fill", accessibilityDescription: nil)!)
        let high = NSImageView(image: NSImage(systemSymbolName: "speaker.wave.3.fill", accessibilityDescription: nil)!)
        low.contentTintColor = .secondaryLabelColor
        high.contentTintColor = .secondaryLabelColor
        low.frame = NSRect(x: 16, y: 7, width: 16, height: 16)
        high.frame = NSRect(x: 212, y: 7, width: 18, height: 16)
        let slider = NSSlider(value: Double(volume), minValue: 0, maxValue: 100, target: self, action: #selector(volumeChanged(_:)))
        slider.frame = NSRect(x: 36, y: 5, width: 170, height: 20)
        slider.isContinuous = true
        slider.setAccessibilityLabel("Volume")
        view.addSubview(low)
        view.addSubview(slider)
        view.addSubview(high)
        let item = NSMenuItem()
        item.view = view
        return item
    }

    @objc private func volumeChanged(_ sender: NSSlider) {
        app.setVolume(Int(sender.doubleValue.rounded()), showToast: false)
    }

    private func sleepItems() -> [NSMenuItem] {
        var items: [NSMenuItem] = []
        let off = item("Off") { [app] in app.setSleepTimer(minutes: nil) }
        off.state = app.sleep == .off ? .on : .off
        items.append(off)
        if let description = app.sleepDescription {
            let status = NSMenuItem(title: description, action: nil, keyEquivalent: "")
            status.isEnabled = false
            items.insert(status, at: 0)
            items.insert(.separator(), at: 1)
        }
        for minutes in [15, 30, 45, 60, 90] {
            items.append(item("\(minutes) Minutes") { [app] in app.setSleepTimer(minutes: minutes) })
        }
        let end = item("End of Current Song") { [app] in app.setSleepAtEndOfTrack() }
        end.state = app.sleep == .endOfTrack ? .on : .off
        end.isEnabled = app.player.currentURL != nil
        items.append(end)
        return items
    }

    private func noiseItems(_ config: AppConfig) -> [NSMenuItem] {
        var items = Noise.Kind.allCases.map { kind -> NSMenuItem in
            let mi = item(kind.label) { [app] in app.update { $0.noise = kind.rawValue } }
            mi.state = config.noise == kind.rawValue ? .on : .off
            return mi
        }
        items.append(.separator())
        let note = NSMenuItem(title: "Plays under the music while it’s playing", action: nil, keyEquivalent: "")
        note.isEnabled = false
        items.append(note)
        return items
    }

    private func submenu(_ title: String, symbol: String, items: [NSMenuItem]) -> NSMenuItem {
        let mi = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        mi.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        let sub = NSMenu(title: title)
        sub.autoenablesItems = false
        items.forEach(sub.addItem)
        mi.submenu = sub
        return mi
    }

    private func item(_ title: String, key: String = "", _ action: @escaping () -> Void) -> NSMenuItem {
        let mi = NSMenuItem(title: title, action: #selector(fire(_:)), keyEquivalent: key)
        mi.target = self
        mi.representedObject = action
        return mi
    }

    @discardableResult
    private func add(_ title: String, symbol: String?, key: String = "", enabled: Bool = true,
                     _ action: @escaping () -> Void) -> NSMenuItem {
        let mi = item(title, key: key, action)
        if let symbol { mi.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) }
        mi.isEnabled = enabled
        menu.addItem(mi)
        return mi
    }

    @objc private func fire(_ sender: NSMenuItem) {
        (sender.representedObject as? () -> Void)?()
    }

    static func time(_ t: TimeInterval) -> String {
        let s = max(0, Int(t))
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}
