import AppKit

/// Menu bar item. The menu is rebuilt lazily each time it opens, so idle cost is zero.
final class StatusMenu: NSObject, NSMenuDelegate {
    struct Actions {
        var settings: () -> Void
        var toggle: () -> Void
        var next: () -> Void
        var rescan: () -> Void
        var openFolder: () -> Void
        var quit: () -> Void
    }

    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let menu = NSMenu()
    private let actions: Actions
    private let state: () -> (isPlaying: Bool, title: String?)

    init(actions: Actions, state: @escaping () -> (isPlaying: Bool, title: String?)) {
        self.actions = actions
        self.state = state
        super.init()
        if let button = item.button {
            let image = NSImage(systemSymbolName: "music.note", accessibilityDescription: "LoFi HUD")
            image?.isTemplate = true
            button.image = image
            button.toolTip = "LoFi HUD Idle"
        }
        menu.delegate = self
        menu.autoenablesItems = false
        item.menu = menu
    }

    func update(tooltip: String) {
        item.button?.toolTip = String(tooltip.prefix(120))
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let (playing, title) = state()

        let header = NSMenuItem(title: title ?? "Nothing playing", action: nil, keyEquivalent: "")
        header.isEnabled = false
        if let title {
            header.attributedTitle = NSAttributedString(
                string: title,
                attributes: [.font: NSFont.systemFont(ofSize: 13, weight: .semibold)])
        }
        header.image = NSImage(
            systemSymbolName: playing ? "waveform" : (title == nil ? "music.note" : "pause.circle"),
            accessibilityDescription: nil)
        menu.addItem(header)
        menu.addItem(.separator())

        add(playing ? "Pause" : "Play", symbol: playing ? "pause.fill" : "play.fill", actions.toggle)
        add("Next Track", symbol: "forward.fill", actions.next)
        menu.addItem(.separator())
        add("Rescan Library", symbol: "arrow.clockwise", actions.rescan)
        add("Open Music Folder", symbol: "folder", actions.openFolder)
        menu.addItem(.separator())
        add("Settings…", symbol: "gearshape", key: ",", actions.settings)
        add("Quit LoFi HUD", symbol: nil, key: "q", actions.quit)
    }

    private func add(_ title: String, symbol: String?, key: String = "", _ action: @escaping () -> Void) {
        let mi = NSMenuItem(title: title, action: #selector(fire(_:)), keyEquivalent: key)
        mi.target = self
        mi.representedObject = action
        if let symbol { mi.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) }
        menu.addItem(mi)
    }

    @objc private func fire(_ sender: NSMenuItem) {
        (sender.representedObject as? () -> Void)?()
    }
}
