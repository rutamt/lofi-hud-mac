import AppKit
import Carbon.HIToolbox

/// System-wide modifier+key hotkeys via Carbon `RegisterEventHotKey`.
///
/// Unlike an event tap this needs no Accessibility permission, and the OS consumes
/// matched keystrokes so they never leak into the focused app (no stray "œ" for ⌥Q).
/// Discrete actions fire once per physical press; volume keys auto-repeat while held
/// using the user's system key-repeat timing.
final class Hotkeys {
    enum Action: UInt32, CaseIterable {
        case volUp = 1, volDown, play, prev, next, showSong, ignore, favorite

        var repeats: Bool { self == .volUp || self == .volDown }

        var label: String {
            switch self {
            case .play: return "Play/Pause"
            case .next: return "Next Track"
            case .prev: return "Previous Track"
            case .showSong: return "Show Song Name"
            case .ignore: return "Remove/Ignore Song"
            case .favorite: return "Favorite Song"
            case .volUp: return "Volume Up"
            case .volDown: return "Volume Down"
            }
        }
    }

    var onAction: ((Action) -> Void)?
    /// Actions whose key combo could not be registered (duplicate or claimed by another app).
    private(set) var failed: [Action] = []

    private var refs: [EventHotKeyRef] = []
    private var handlerRef: EventHandlerRef?
    private var repeatTimer: Timer?
    private var repeatingAction: Action?
    private var lastConfig: AppConfig?
    private var isSuspended = false
    private static let signature: OSType = 0x4C4F_4649  // 'LOFI'

    init() {
        installHandler()
        // Re-resolve character keys when the keyboard layout changes.
        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
            object: nil, queue: .main
        ) { [weak self] _ in
            guard let self, let config = self.lastConfig, !self.refs.isEmpty else { return }
            self.register(config)
        }
    }

    static func binding(_ action: Action, in config: AppConfig) -> String {
        switch action {
        case .play: return config.keyPlay
        case .next: return config.keyNext
        case .prev: return config.keyPrev
        case .showSong: return config.keyShowSong
        case .ignore: return config.keyIgnore
        case .favorite: return config.keyFavorite
        case .volUp: return config.keyVolUp
        case .volDown: return config.keyVolDown
        }
    }

    static func combo(_ action: Action, in config: AppConfig) -> KeyCombo {
        KeyCombo(binding(action, in: config), defaultModifier: config.modKey)
    }

    static func setBinding(_ action: Action, _ combo: KeyCombo, in config: inout AppConfig) {
        let value = combo.stringValue
        switch action {
        case .play: config.keyPlay = value
        case .next: config.keyNext = value
        case .prev: config.keyPrev = value
        case .showSong: config.keyShowSong = value
        case .ignore: config.keyIgnore = value
        case .favorite: config.keyFavorite = value
        case .volUp: config.keyVolUp = value
        case .volDown: config.keyVolDown = value
        }
    }

    /// Whether another app (or macOS) already holds this combo. Call while our own are suspended.
    static func isAvailable(_ combo: KeyCombo) -> Bool {
        guard let code = KeyCodes.keyCode(for: combo.key) else { return false }
        var ref: EventHotKeyRef?
        let id = EventHotKeyID(signature: 0x4C4F_4654, id: 999)  // 'LOFT' probe
        let status = RegisterEventHotKey(
            UInt32(code), combo.carbonModifiers, id, GetApplicationEventTarget(),
            OptionBits(kEventHotKeyExclusive), &ref)
        if let ref { UnregisterEventHotKey(ref) }
        return status == noErr
    }

    /// Register every binding. Earlier actions in `Action.allCases` win on conflicts,
    /// matching the original matcher's precedence.
    func register(_ config: AppConfig) {
        unregisterAll()
        isSuspended = false
        lastConfig = config
        failed = []
        for action in Action.allCases {
            let combo = Self.combo(action, in: config)
            guard let code = KeyCodes.keyCode(for: combo.key) else {
                failed.append(action)
                continue
            }
            var ref: EventHotKeyRef?
            let id = EventHotKeyID(signature: Self.signature, id: action.rawValue)
            let status = RegisterEventHotKey(
                UInt32(code), combo.carbonModifiers, id, GetApplicationEventTarget(),
                OptionBits(kEventHotKeyExclusive), &ref)
            if status == noErr, let ref {
                refs.append(ref)
            } else {
                failed.append(action)
            }
        }
    }

    /// Apply new bindings now, or on `resume()` if currently suspended.
    func update(_ config: AppConfig) {
        if isSuspended {
            lastConfig = config
        } else {
            register(config)
        }
    }

    /// Temporarily release all hotkeys (used while capturing a new keybind).
    func suspend() {
        unregisterAll()
        isSuspended = true
    }

    func resume() {
        if let config = lastConfig { register(config) }
    }

    private func unregisterAll() {
        stopRepeat()
        refs.forEach { UnregisterEventHotKey($0) }
        refs.removeAll()
    }

    // MARK: Event handling

    private func installHandler() {
        var types = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased)),
        ]
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let event, let userData else { return OSStatus(eventNotHandledErr) }
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(
                event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            guard status == noErr, hotKeyID.signature == Hotkeys.signature,
                  let action = Action(rawValue: hotKeyID.id) else { return OSStatus(eventNotHandledErr) }
            let me = Unmanaged<Hotkeys>.fromOpaque(userData).takeUnretainedValue()
            if GetEventKind(event) == UInt32(kEventHotKeyPressed) {
                me.pressed(action)
            } else {
                me.released(action)
            }
            return noErr
        }, types.count, &types, selfPtr, &handlerRef)
    }

    private func pressed(_ action: Action) {
        onAction?(action)
        guard action.repeats else { return }
        stopRepeat()
        repeatingAction = action
        repeatTimer = Timer.scheduledTimer(withTimeInterval: NSEvent.keyRepeatDelay, repeats: false) {
            [weak self] _ in
            guard let self, self.repeatingAction == action else { return }
            self.repeatTimer = Timer.scheduledTimer(
                withTimeInterval: max(0.03, NSEvent.keyRepeatInterval), repeats: true
            ) { [weak self] _ in self?.onAction?(action) }
        }
    }

    private func released(_ action: Action) {
        if repeatingAction == action { stopRepeat() }
    }

    private func stopRepeat() {
        repeatTimer?.invalidate()
        repeatTimer = nil
        repeatingAction = nil
    }
}
