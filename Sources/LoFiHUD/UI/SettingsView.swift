import AppKit
import SwiftUI

/// Hosts the singleton Settings window. Shows a Dock icon only while open (unless disabled).
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private unowned let app: AppController
    private var window: NSWindow?
    private var model: SettingsModel?

    init(app: AppController) { self.app = app }

    func open() {
        NSApp.setActivationPolicy(app.config.showDockIcon ? .regular : .accessory)
        if let window {
            NSApp.activate()
            window.makeKeyAndOrderFront(nil)
            return
        }
        let model = SettingsModel(app: app)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 740),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false)
        window.title = "LoFi HUD Settings"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 560, height: 560)
        let host = NSHostingView(rootView: SettingsView(model: model))
        host.sizingOptions = [.minSize]
        window.contentView = host
        window.setContentSize(NSSize(width: 640, height: 740))
        window.delegate = self
        if !window.setFrameUsingName("LoFiHUDSettings") { window.center() }
        window.setFrameAutosaveName("LoFiHUDSettings")

        model.onAppearanceChange = { [weak window] theme in
            window?.appearance = NSAppearance(named: theme.isLight ? .aqua : .darkAqua)
            window?.backgroundColor = NSColor(hex: theme.bg)
        }
        model.onAppearanceChange?(model.theme)

        self.window = window
        self.model = model
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        model?.endCapture(resumeHotkeys: true)
        if app.isPositioningHUD { app.endHUDPositioning() }
        model = nil
        window = nil
        NSApp.setActivationPolicy(.accessory)
    }

    /// Apply a changed Dock icon preference while the window is open.
    func refreshDockIcon() {
        guard let window else { return }
        NSApp.setActivationPolicy(app.config.showDockIcon ? .regular : .accessory)
        // Switching policy can deactivate the app; keep Settings in front.
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    func libraryChanged() { model?.libraryChanged() }
    func devicesChanged() { model?.refreshDevices() }
    func configChangedExternally() { model?.syncFromApp() }
}

// MARK: - Root view

struct SettingsView: View {
    @ObservedObject var model: SettingsModel
    @Namespace private var tabNS

    var body: some View {
        let t = model.theme
        VStack(spacing: 0) {
            header(t)
            tabBar(t)
            ScrollView {
                VStack(spacing: 14) {
                    switch model.tab {
                    case .appearance: AppearanceTab(model: model)
                    case .playback: PlaybackTab(model: model)
                    case .controls: ControlsTab(model: model)
                    }
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.automatic)
            footer(t)
        }
        .background(t.color(t.bg).ignoresSafeArea())
        .tint(t.color(t.accent))
        .environment(\.colorScheme, t.colorScheme)
        .animation(.easeInOut(duration: 0.2), value: t.id)
    }

    private func header(_ t: Theme) -> some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(LinearGradient(
                        colors: [t.color(t.accent), t.color(t.accentHover)],
                        startPoint: .topLeading, endPoint: .bottomTrailing))
                Image(systemName: "music.note")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(t.color(t.onAccent))
            }
            .frame(width: 44, height: 44)
            .shadow(color: t.color(t.accent).opacity(0.35), radius: 8, y: 3)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text("LoFi HUD")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(t.color(t.fg))
                Text("Playback, overlay, and hotkeys")
                    .font(.system(size: 13))
                    .foregroundStyle(t.color(t.muted))
            }
            Spacer()
        }
        .padding(.horizontal, 22)
        .padding(.top, 38)
        .padding(.bottom, 14)
    }

    private func tabBar(_ t: Theme) -> some View {
        HStack(spacing: 4) {
            ForEach(SettingsModel.Tab.allCases) { tab in
                let selected = model.tab == tab
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { model.tab = tab }
                } label: {
                    Label(tab.rawValue, systemImage: tab.symbol)
                        .font(.system(size: 13, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .foregroundStyle(selected ? t.color(t.onAccent) : t.color(t.fg).opacity(0.8))
                        .background {
                            if selected {
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .fill(t.color(t.accent))
                                    .matchedGeometryEffect(id: "tab", in: tabNS)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(4)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(t.color(t.surfaceAlt)))
        .padding(.horizontal, 22)
    }

    private func footer(_ t: Theme) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: model.savedFlash ? "checkmark.circle.fill" : "checkmark.circle")
                    .foregroundStyle(model.savedFlash ? Color.green : t.color(t.muted))
                Text(model.savedFlash ? "Saved" : "Changes apply instantly")
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(t.color(t.fg).opacity(0.8))
            .accessibilityElement(children: .combine)

            HStack(spacing: 6) {
                Text("LoFi HUD v\(AppInfo.version) • Created by Rutam and Gemini")
                Text("•")
                UninstallLink(model: model, theme: t)
            }
            .font(.system(size: 11))
            .foregroundStyle(t.color(t.muted))
        }
        .padding(.horizontal, 22)
        .padding(.top, 10)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity)
        .background(t.color(t.bg))
    }
}

// MARK: - Tabs

private struct AppearanceTab: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        let t = model.theme
        Card(title: "Theme", symbol: "swatchpalette", theme: t) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 10)], spacing: 10) {
                ThemeChip(
                    label: Themes.systemLabel,
                    preview: [Themes.preset(model.draft.autoLightTheme)!, Themes.preset(model.draft.autoDarkTheme)!],
                    selected: model.draft.theme == Themes.systemID, current: t
                ) { model.selectTheme(Themes.systemID) }
                ForEach(Themes.all) { theme in
                    ThemeChip(label: theme.label, preview: [theme], selected: model.draft.theme == theme.id, current: t) {
                        model.selectTheme(theme.id)
                    }
                }
            }
            if model.draft.theme == Themes.systemID {
                Row("Light Mode Theme", theme: t) {
                    Picker("Light Mode Theme", selection: $model.draft.autoLightTheme) {
                        ForEach(Themes.lightThemes) { Text($0.label).tag($0.id) }
                    }
                    .labelsHidden().fixedSize()
                }
                Row("Dark Mode Theme", theme: t) {
                    Picker("Dark Mode Theme", selection: $model.draft.autoDarkTheme) {
                        ForEach(Themes.darkThemes) { Text($0.label).tag($0.id) }
                    }
                    .labelsHidden().fixedSize()
                }
            }
            Row("Accent Color", theme: t) {
                HStack(spacing: 8) {
                    if model.draft.accentMode == "custom" {
                        ColorPicker("Custom accent", selection: model.customAccent, supportsOpacity: false)
                            .labelsHidden()
                    }
                    Picker("Accent Color", selection: $model.draft.accentMode) {
                        Text("Theme").tag("theme")
                        Text("macOS").tag("system")
                        Text("Custom").tag("custom")
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }
            }
        }

        Card(title: "Overlay", symbol: "rectangle.on.rectangle", theme: t) {
            Row("HUD Position", theme: t) {
                HStack(spacing: 8) {
                    SecondaryButton("Drag to Place…", symbol: "hand.draw", theme: t, action: model.positionHUD)
                    Picker("HUD Position", selection: $model.draft.hudPosition) {
                        ForEach(HUDPosition.allCases, id: \.rawValue) { Text($0.rawValue).tag($0.rawValue) }
                    }
                    .labelsHidden().fixedSize()
                }
            }
            Row("Display", theme: t) {
                Picker("Display", selection: $model.draft.hudDisplay) {
                    ForEach(model.displayOptions, id: \.tag) { Text($0.label).tag($0.tag) }
                }
                .labelsHidden().fixedSize()
            }
            Row("Action HUD Timeout", theme: t) {
                Picker("Action HUD Timeout", selection: $model.draft.hudTimeout) {
                    ForEach(model.timeoutOptions(including: model.draft.hudTimeout), id: \.ms) { Text($0.label).tag($0.ms) }
                }
                .labelsHidden().fixedSize()
            }
            Row("Song Info Timeout", theme: t) {
                Picker("Song Info Timeout", selection: $model.draft.hudSongTimeout) {
                    ForEach(model.timeoutOptions(including: model.draft.hudSongTimeout), id: \.ms) { Text($0.label).tag($0.ms) }
                }
                .labelsHidden().fixedSize()
            }
            ToggleRow("Show song progress on Now Playing", isOn: $model.draft.showSongProgress, theme: t)
            HStack {
                Spacer()
                SecondaryButton("Preview HUD", symbol: "eye", theme: t, action: model.previewHUD)
            }
        }
    }
}

private struct PlaybackTab: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        let t = model.theme
        Card(title: "Behavior & System", symbol: "slider.horizontal.3", theme: t) {
            ToggleRow("Start LoFi HUD at login", isOn: $model.draft.autostart, theme: t)
            ToggleRow(
                "Show Dock icon while Settings is open",
                subtitle: "LoFi HUD always lives in the menu bar; this only affects the Dock",
                isOn: $model.draft.showDockIcon, theme: t)
            ToggleRow("Auto-show Now Playing when the track changes", isOn: $model.draft.showNowPlaying, theme: t)
            ToggleRow("Show volume and play/pause HUD", isOn: $model.draft.showActions, theme: t)
            Row("Auto-Pause On Disconnect", theme: t) {
                Picker("Auto-Pause On Disconnect", selection: $model.autopauseSelection) {
                    ForEach(model.autopauseOptions, id: \.tag) { Text($0.label).tag($0.tag) }
                }
                .labelsHidden().fixedSize()
            }
            Caption("Pauses when the output device disconnects, e.g. Bluetooth headphones. "
                    + "“Whichever Device Is Playing” works with any headphones.", theme: t)
            HStack {
                ToggleRow("Check for updates daily", isOn: $model.draft.checkForUpdates, theme: t)
                SecondaryButton("Check Now", symbol: "arrow.down.circle", theme: t, action: model.checkForUpdates)
            }
        }

        Card(title: "Sound", symbol: "waveform", theme: t) {
            Row("Crossfade", theme: t) {
                HStack(spacing: 10) {
                    Slider(value: Binding(
                        get: { Double(model.draft.crossfade) },
                        set: { model.draft.crossfade = Int($0.rounded()) }), in: 0...12, step: 1)
                        .frame(width: 180)
                        .accessibilityLabel("Crossfade seconds")
                    Text(model.draft.crossfade == 0 ? "Off (gapless)" : "\(model.draft.crossfade) s")
                        .font(.system(size: 12, weight: .medium).monospacedDigit())
                        .foregroundStyle(t.color(t.muted))
                        .frame(width: 84, alignment: .trailing)
                }
            }
            Row("Ambient Noise", theme: t) {
                Picker("Ambient Noise", selection: $model.draft.noise) {
                    ForEach(Noise.Kind.allCases, id: \.rawValue) { Text($0.label).tag($0.rawValue) }
                }
                .labelsHidden().fixedSize()
            }
            if model.draft.noise != Noise.Kind.off.rawValue {
                Row("Noise Volume", theme: t) {
                    Slider(value: Binding(
                        get: { Double(model.draft.noiseVolume) },
                        set: { model.draft.noiseVolume = Int($0.rounded()) }), in: 0...100)
                        .frame(width: 180)
                        .accessibilityLabel("Noise volume")
                }
            }
            ToggleRow(
                "Favorites only",
                subtitle: "Shuffle just the songs you’ve favorited (\(model.favoritesCount) so far)",
                isOn: $model.draft.favoritesOnly, theme: t)
            Caption("Set a sleep timer from the menu bar icon.", theme: t)
        }

        Card(title: "Music Source", symbol: "folder", theme: t) {
            HStack(spacing: 8) {
                TextField("Music folder", text: $model.musicDirText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, design: .monospaced))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(RoundedRectangle(cornerRadius: 8).fill(t.color(t.surface)))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(t.color(t.border)))
                    .foregroundStyle(t.color(t.fg))
                    .onSubmit(model.applyMusicDir)
                if model.musicDirEdited {
                    PrimaryButton("Apply", theme: t, action: model.applyMusicDir)
                } else {
                    PrimaryButton("Browse", theme: t, action: model.browse)
                }
            }
            HStack(spacing: 8) {
                SecondaryButton("Open Folder", symbol: "folder", theme: t, action: model.openFolder)
                SecondaryButton("Rescan Library", symbol: "arrow.clockwise", theme: t, action: model.rescan)
                Spacer()
                Text("\(model.trackCount) track\(model.trackCount == 1 ? "" : "s")")
                    .font(.system(size: 12, weight: .medium).monospacedDigit())
                    .foregroundStyle(t.color(t.muted))
            }
            Caption("Supports MP3, AAC/M4A, ALAC, FLAC, WAV, AIFF and CAF. New files are picked up automatically. "
                    + "Removed songs go to a sibling “Ignored_Lofi” folder.", theme: t)
        }
    }
}

private struct ControlsTab: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        let t = model.theme
        Card(title: "Hotkeys", symbol: "command", theme: t) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "checkmark.seal.fill").foregroundStyle(Color.green)
                Text("Hotkeys work system-wide and don’t need Accessibility permission. "
                     + "Click a shortcut, then press the new combo.")
                    .foregroundStyle(t.color(t.muted))
            }
            .font(.system(size: 12))

            ToggleRow(
                "Enable hardware media keys",
                subtitle: "Keyboard media keys, AirPods & Bluetooth headsets, Control Center",
                isOn: $model.draft.enableHardwareKeys, theme: t)

            Divider().overlay(t.color(t.border))

            ForEach(Hotkeys.Action.displayOrder, id: \.self) { action in
                let problem = model.problem(for: action)
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(action.label)
                            .font(.system(size: 13))
                            .foregroundStyle(t.color(t.fg))
                        if let problem {
                            Label(problem, systemImage: "exclamationmark.triangle.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(Color.orange)
                        }
                    }
                    Spacer(minLength: 12)
                    KeyButton(
                        action: action,
                        combo: model.combo(action),
                        capturing: model.capturing == action,
                        conflict: problem != nil,
                        theme: t
                    ) {
                        if model.capturing == action {
                            model.endCapture(resumeHotkeys: true)
                        } else {
                            model.startCapture(action)
                        }
                    }
                }
            }

            if let hint = model.captureHint {
                Warning(hint, theme: t)
            } else if model.capturing != nil {
                Caption("Press the new combo. Esc cancels.", theme: t)
            }
            HStack {
                Caption("Next, previous, show, remove, favorite and volume only act while music is playing.", theme: t)
                Spacer()
                SecondaryButton("Reset to Defaults", symbol: "arrow.counterclockwise", theme: t, action: model.resetHotkeys)
            }
        }
    }
}

extension Hotkeys.Action {
    static let displayOrder: [Hotkeys.Action] = [.play, .next, .prev, .showSong, .ignore, .favorite, .volUp, .volDown]
}

// MARK: - Components

private struct Card<Content: View>: View {
    let title: String
    let symbol: String
    let theme: Theme
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(theme.color(theme.fg))
                .accessibilityAddTraits(.isHeader)
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(theme.color(theme.surfaceAlt)))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(theme.color(theme.border).opacity(0.6), lineWidth: 0.5))
    }
}

private struct Row<Control: View>: View {
    let label: String
    let theme: Theme
    @ViewBuilder var control: Control

    init(_ label: String, theme: Theme, @ViewBuilder control: () -> Control) {
        self.label = label
        self.theme = theme
        self.control = control()
    }

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(theme.color(theme.fg))
            Spacer(minLength: 12)
            control
        }
    }
}

private struct Caption: View {
    let text: String
    let theme: Theme
    init(_ text: String, theme: Theme) {
        self.text = text
        self.theme = theme
    }

    var body: some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(theme.color(theme.muted))
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct ToggleRow: View {
    let label: String
    var subtitle: String? = nil
    @Binding var isOn: Bool
    let theme: Theme

    init(_ label: String, subtitle: String? = nil, isOn: Binding<Bool>, theme: Theme) {
        self.label = label
        self.subtitle = subtitle
        self._isOn = isOn
        self.theme = theme
    }

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 13))
                    .foregroundStyle(theme.color(theme.fg))
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(theme.color(theme.muted))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .toggleStyle(.switch)
        .controlSize(.small)
    }
}

private struct ThemeChip: View {
    let label: String
    let preview: [Theme]
    let selected: Bool
    let current: Theme
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 0) {
                    ForEach(preview) { p in
                        ZStack(alignment: .bottomLeading) {
                            p.color(p.bg)
                            HStack(spacing: 3) {
                                Circle().fill(p.color(p.accent)).frame(width: 9, height: 9)
                                Capsule().fill(p.color(p.fg).opacity(0.7)).frame(width: 22, height: 4)
                            }
                            .padding(7)
                        }
                    }
                }
                .frame(height: 40)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08)))

                HStack {
                    Text(label)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(current.color(current.fg))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    if selected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(current.color(current.accent))
                    }
                }
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(current.color(current.surface)))
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(
                        selected ? current.color(current.accent) : current.color(current.border),
                        lineWidth: selected ? 2 : 0.5))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label) theme")
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}

private struct KeyButton: View {
    let action: Hotkeys.Action
    let combo: KeyCombo
    let capturing: Bool
    let conflict: Bool
    let theme: Theme
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 4) {
                if capturing {
                    Image(systemName: "record.circle").symbolEffect(.pulse)
                    Text("Press combo…")
                } else {
                    ForEach(combo.modifierSymbols, id: \.self) { KeyCap($0, theme: theme) }
                    KeyCap(KeyCodes.display(combo.key), theme: theme)
                }
            }
            .font(.system(size: 12, weight: .semibold))
            .frame(minWidth: 120)
            .padding(.vertical, 5)
            .padding(.horizontal, 8)
            .foregroundStyle(capturing ? Color.white : theme.color(theme.fg))
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(capturing ? theme.color(theme.danger) : theme.color(theme.surface)))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(conflict ? Color.orange : theme.color(theme.border),
                                  lineWidth: capturing ? 0 : (conflict ? 1.5 : 0.5)))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel("\(action.label) shortcut")
        .accessibilityValue(capturing ? "Recording, press the new combo" : spoken)
        .accessibilityHint("Activate to record a new shortcut")
    }

    private var spoken: String {
        var parts: [String] = []
        if combo.modifiers.contains(.control) { parts.append("Control") }
        if combo.modifiers.contains(.option) { parts.append("Option") }
        if combo.modifiers.contains(.shift) { parts.append("Shift") }
        if combo.modifiers.contains(.command) { parts.append("Command") }
        parts.append(combo.key.count == 1 ? combo.key.uppercased() : combo.key.replacingOccurrences(of: "_", with: " "))
        return parts.joined(separator: " ")
    }
}

private struct KeyCap: View {
    let text: String
    let theme: Theme
    init(_ text: String, theme: Theme) {
        self.text = text
        self.theme = theme
    }

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .frame(minWidth: 22)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(theme.color(theme.surfaceAlt)))
    }
}

private struct PrimaryButton: View {
    let title: String
    let theme: Theme
    let action: () -> Void
    init(_ title: String, theme: Theme, action: @escaping () -> Void) {
        self.title = title
        self.theme = theme
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .foregroundStyle(theme.color(theme.onAccent))
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(theme.color(theme.accent)))
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
    }
}

private struct SecondaryButton: View {
    let title: String
    let symbol: String
    let theme: Theme
    let action: () -> Void
    init(_ title: String, symbol: String, theme: Theme, action: @escaping () -> Void) {
        self.title = title
        self.symbol = symbol
        self.theme = theme
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.system(size: 12, weight: .medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .foregroundStyle(theme.color(theme.fg))
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(theme.color(theme.surface)))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(theme.color(theme.border), lineWidth: 0.5))
                .contentShape(Rectangle())
                .fixedSize()
        }
        .buttonStyle(PressableStyle())
    }
}

private struct Warning: View {
    let text: String
    let theme: Theme
    init(_ text: String, theme: Theme) {
        self.text = text
        self.theme = theme
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Color.orange)
            Text(text).foregroundStyle(theme.color(theme.fg))
        }
        .font(.system(size: 11))
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.12)))
    }
}

private struct UninstallLink: View {
    @ObservedObject var model: SettingsModel
    let theme: Theme

    var body: some View {
        Button("Uninstall", action: model.confirmUninstall)
            .buttonStyle(.plain)
            .underline()
            .foregroundStyle(model.uninstallHover ? theme.color(theme.danger) : theme.color(theme.muted))
            .onHover { model.uninstallHover = $0 }
    }
}

private struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
