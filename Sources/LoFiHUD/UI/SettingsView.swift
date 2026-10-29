import AppKit
import SwiftUI

/// Hosts the singleton Settings window. Shows a Dock icon only while open.
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private unowned let app: AppController
    private var window: NSWindow?
    private var model: SettingsModel?

    init(app: AppController) { self.app = app }

    func open() {
        NSApp.setActivationPolicy(.regular)
        if let window {
            NSApp.activate()
            window.makeKeyAndOrderFront(nil)
            return
        }
        let model = SettingsModel(app: app)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 720),
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
        window.setContentSize(NSSize(width: 640, height: 720))
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
        model = nil
        window = nil
        NSApp.setActivationPolicy(.accessory)
    }
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
            }
        }
        .padding(4)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(t.color(t.surfaceAlt)))
        .padding(.horizontal, 22)
    }

    private func footer(_ t: Theme) -> some View {
        VStack(spacing: 10) {
            Button(action: model.save) {
                HStack(spacing: 6) {
                    if model.savedFlash { Image(systemName: "checkmark") }
                    Text(model.savedFlash ? "Saved!" : "Save & Apply")
                }
                .font(.system(size: 14, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .foregroundStyle(model.savedFlash ? Color.white : t.color(t.onAccent))
                .background(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(model.savedFlash ? Color.green : t.color(t.accent)))
                .contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle())
            .keyboardShortcut("s", modifiers: .command)

            HStack(spacing: 6) {
                Text("LoFi HUD v\(AppInfo.version) • Created by Rutam and Gemini")
                Text("•")
                UninstallLink(model: model, theme: t)
            }
            .font(.system(size: 11))
            .foregroundStyle(t.color(t.muted))
        }
        .padding(.horizontal, 22)
        .padding(.top, 12)
        .padding(.bottom, 16)
        .background(t.color(t.bg))
    }
}

enum AppInfo {
    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "2.0.0"
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
                    preview: [Themes.resolve("system_light"), Themes.resolve("harbor_night")],
                    selected: model.themeID == Themes.systemID, current: t
                ) { model.selectTheme(Themes.systemID) }
                ForEach(Themes.all) { theme in
                    ThemeChip(label: theme.label, preview: [theme], selected: model.themeID == theme.id, current: t) {
                        model.selectTheme(theme.id)
                    }
                }
            }
        }

        Card(title: "Overlay", symbol: "rectangle.on.rectangle", theme: t) {
            Row("HUD Position", theme: t) {
                Picker("", selection: $model.hudPosition) {
                    ForEach(HUDPosition.allCases, id: \.rawValue) { Text($0.rawValue).tag($0.rawValue) }
                }
                .labelsHidden().fixedSize()
            }
            Row("Action HUD Timeout", theme: t) {
                Picker("", selection: $model.hudTimeout) {
                    ForEach(model.timeoutOptions(including: model.hudTimeout), id: \.ms) { Text($0.label).tag($0.ms) }
                }
                .labelsHidden().fixedSize()
            }
            Row("Song Info Timeout", theme: t) {
                Picker("", selection: $model.hudSongTimeout) {
                    ForEach(model.timeoutOptions(including: model.hudSongTimeout), id: \.ms) { Text($0.label).tag($0.ms) }
                }
                .labelsHidden().fixedSize()
            }
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
            ToggleRow("Start LoFi HUD at login", isOn: $model.autostart, theme: t)
            ToggleRow("Auto-show Now Playing when the track changes", isOn: $model.showNowPlaying, theme: t)
            ToggleRow("Show volume and play/pause HUD", isOn: $model.showActions, theme: t)
            Row("Auto-Pause Device", theme: t) {
                Picker("", selection: $model.autopauseDevice) {
                    ForEach(model.deviceOptions, id: \.self) { Text($0).tag($0) }
                }
                .labelsHidden().fixedSize()
            }
            Text("Pauses playback when this output device disconnects, e.g. Bluetooth headphones.")
                .font(.system(size: 11))
                .foregroundStyle(t.color(t.muted))
        }

        Card(title: "Music Source", symbol: "folder", theme: t) {
            HStack(spacing: 8) {
                TextField("Music folder", text: $model.musicDir)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, design: .monospaced))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(RoundedRectangle(cornerRadius: 8).fill(t.color(t.surface)))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(t.color(t.border)))
                    .foregroundStyle(t.color(t.fg))
                PrimaryButton("Browse", theme: t, action: model.browse)
            }
            HStack(spacing: 8) {
                SecondaryButton("Open Folder", symbol: "folder", theme: t, action: model.openFolder)
                SecondaryButton("Rescan Library", symbol: "arrow.clockwise", theme: t, action: model.rescan)
                Spacer()
                Text("\(model.trackCount) track\(model.trackCount == 1 ? "" : "s")")
                    .font(.system(size: 12, weight: .medium).monospacedDigit())
                    .foregroundStyle(t.color(t.muted))
            }
            Text("Supports MP3, AAC/M4A, ALAC, FLAC, WAV and AIFF. Removed songs go to a sibling “Ignored_Lofi” folder.")
                .font(.system(size: 11))
                .foregroundStyle(t.color(t.muted))
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
                Text("Hotkeys work system-wide and don’t need Accessibility permission.")
                    .foregroundStyle(t.color(t.muted))
            }
            .font(.system(size: 12))

            ToggleRow(
                "Enable hardware media keys",
                subtitle: "Keyboard media keys, AirPods & Bluetooth headsets, Control Center",
                isOn: $model.enableHardwareKeys, theme: t)

            Row("Hold Modifier", theme: t) {
                Picker("", selection: $model.modKey) {
                    ForEach(SettingsModel.modifiers, id: \.id) { Text($0.label).tag($0.id) }
                }
                .labelsHidden().fixedSize()
            }

            Divider().overlay(t.color(t.border))

            ForEach(Hotkeys.Action.displayOrder, id: \.self) { action in
                Row(action.label, theme: t) {
                    KeyButton(
                        modifier: Hotkeys.modifierSymbol(model.modKey),
                        key: model.binds[action] ?? "",
                        capturing: model.capturing == action,
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

            if model.capturing != nil {
                Text("Press the new key. Esc cancels.")
                    .font(.system(size: 11))
                    .foregroundStyle(t.color(t.muted))
            }
            if !model.failedHotkeys.isEmpty {
                Warning(
                    "Couldn’t register: \(model.failedHotkeys.map(\.label).joined(separator: ", ")). "
                        + "The combo is a duplicate or already used by another app.",
                    theme: t)
            }
            if model.cmdShortcutWarning {
                Warning("⌘ combos like ⌘Q or ⌘C will override those shortcuts in every app.", theme: t)
            }
        }
    }
}

extension Hotkeys.Action {
    static let displayOrder: [Hotkeys.Action] = [.play, .next, .prev, .showSong, .ignore, .volUp, .volDown]
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
    }
}

private struct KeyButton: View {
    let modifier: String
    let key: String
    let capturing: Bool
    let theme: Theme
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if capturing {
                    Image(systemName: "record.circle").symbolEffect(.pulse)
                    Text("Press key…")
                } else {
                    KeyCap(modifier, theme: theme)
                    KeyCap(KeyCodes.display(key), theme: theme)
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
                    .strokeBorder(theme.color(theme.border), lineWidth: capturing ? 0 : 0.5))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
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
