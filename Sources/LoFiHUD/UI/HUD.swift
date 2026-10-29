import AppKit
import SwiftUI

/// Structured toast content shown by the HUD.
struct Toast: Equatable {
    enum Icon: String {
        case play = "play.fill"
        case pause = "pause.fill"
        case volume = "speaker.wave.2.fill"
        case muted = "speaker.slash.fill"
        case trash = "trash.fill"
        case check = "checkmark"
        case error = "xmark"
        case music = "music.note"
    }

    var icon: Icon
    var badge: String
    var title: String
    var progress: Int? = nil

    static let resumed = Toast(icon: .play, badge: "PLAYBACK", title: "Resumed")
    static let paused = Toast(icon: .pause, badge: "PLAYBACK", title: "Paused")
    static let autoPaused = Toast(icon: .pause, badge: "AUTO-PAUSED", title: "Device Disconnected")
    static let folderEmpty = Toast(icon: .music, badge: "LIBRARY", title: "Folder Empty: Add MP3s")
    static let settingsSaved = Toast(icon: .check, badge: "SETTINGS", title: "Settings Saved!")
    static let alreadyRunning = Toast(icon: .check, badge: "ACTIVE", title: "Already Running in Background")
    static let noSong = Toast(icon: .music, badge: "LOFI HUD", title: "No Song Playing")
    static let removeFailed = Toast(icon: .error, badge: "ERROR", title: "Failed to remove file")

    static func nowPlaying(_ title: String) -> Toast { Toast(icon: .music, badge: "NOW PLAYING", title: title) }
    static func removed(_ title: String) -> Toast { Toast(icon: .trash, badge: "REMOVED", title: title) }
    static func rescanned(_ count: Int) -> Toast {
        Toast(icon: .check, badge: "LIBRARY", title: "Library Rescanned: \(count) Tracks")
    }
    static func volume(_ value: Int) -> Toast {
        Toast(icon: value == 0 ? .muted : .volume, badge: "VOLUME", title: "\(value)%", progress: value)
    }
}

enum HUDPosition: String, CaseIterable {
    case topLeft = "Top Left", topCenter = "Top Center", topRight = "Top Right"
    case bottomLeft = "Bottom Left", bottomCenter = "Bottom Center", bottomRight = "Bottom Right"
    case center = "Center"
}

final class HUDModel: ObservableObject {
    @Published var toast = Toast.noSong
    @Published var theme = Themes.resolve(nil)
    @Published var visible = false
}

/// Floating, click-through, non-activating overlay.
final class HUDController {
    private static let height: CGFloat = 68
    private static let margin: CGFloat = 24  // transparent room for the drop shadow
    private static let edgeInset = CGSize(width: 30, height: 40)

    private let model = HUDModel()
    private let panel: NSPanel
    private var hideWork: DispatchWorkItem?
    private var generation = 0

    init() {
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 100),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        let host = NSHostingView(rootView: HUDView(model: model, margin: Self.margin))
        host.sizingOptions = []
        panel.contentView = host
    }

    func show(_ toast: Toast, theme: Theme, position: String, duration: Int) {
        let width = Self.width(for: toast)
        let size = NSSize(width: width + Self.margin * 2, height: Self.height + Self.margin * 2)
        let frame = NSRect(origin: Self.origin(for: position, size: size), size: size)

        generation += 1
        hideWork?.cancel()
        panel.setFrame(frame, display: false)

        if model.visible {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                model.theme = theme
                model.toast = toast
            }
        } else {
            model.theme = theme
            model.toast = toast
            panel.orderFrontRegardless()
            withAnimation(.easeOut(duration: 0.18)) { model.visible = true }
        }

        let work = DispatchWorkItem { [weak self] in self?.hide() }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(max(300, duration)), execute: work)
    }

    func hide() {
        hideWork?.cancel()
        hideWork = nil
        let gen = generation
        withAnimation(.easeIn(duration: 0.2)) { model.visible = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let self, self.generation == gen else { return }
            self.panel.orderOut(nil)
        }
    }

    private static func width(for toast: Toast) -> CGFloat {
        if toast.progress != nil { return 300 }
        let font = NSFont.systemFont(ofSize: 14, weight: .semibold)
        let text = (toast.title as NSString).size(withAttributes: [.font: font]).width
        return min(420, max(240, ceil(text) + 90))
    }

    private static func origin(for position: String, size: NSSize) -> NSPoint {
        let vf = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let m = margin
        let w = size.width - m * 2, h = size.height - m * 2
        let px = edgeInset.width, py = edgeInset.height
        let left = vf.minX + px, right = vf.maxX - w - px, midX = vf.midX - w / 2
        let top = vf.maxY - h - py, bottom = vf.minY + py, midY = vf.midY - h / 2

        let p: NSPoint
        switch HUDPosition(rawValue: position) ?? .bottomCenter {
        case .topLeft: p = NSPoint(x: left, y: top)
        case .topCenter: p = NSPoint(x: midX, y: top)
        case .topRight: p = NSPoint(x: right, y: top)
        case .bottomLeft: p = NSPoint(x: left, y: bottom)
        case .bottomRight: p = NSPoint(x: right, y: bottom)
        case .center: p = NSPoint(x: midX, y: midY)
        case .bottomCenter: p = NSPoint(x: midX, y: bottom)
        }
        return NSPoint(x: round(p.x - m), y: round(p.y - m))
    }
}

// MARK: - View

struct HUDView: View {
    @ObservedObject var model: HUDModel
    let margin: CGFloat

    var body: some View {
        let theme = model.theme
        let toast = model.toast
        let accent = theme.color(theme.accent)
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)

        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(accent.opacity(theme.isLight ? 0.14 : 0.2))
                Image(systemName: toast.icon.rawValue)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(accent)
                    .contentTransition(.symbolEffect(.replace))
            }
            .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(toast.badge)
                        .font(.system(size: 10, weight: .bold))
                        .tracking(0.8)
                        .foregroundStyle(accent)
                    Spacer(minLength: 8)
                    if let p = toast.progress {
                        Text("\(p)%")
                            .font(.system(size: 10, weight: .bold).monospacedDigit())
                            .foregroundStyle(theme.color(theme.muted))
                            .contentTransition(.numericText(value: Double(p)))
                    }
                }
                if let p = toast.progress {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(theme.color(theme.fg).opacity(0.14))
                            Capsule().fill(accent)
                                .frame(width: max(0, geo.size.width * CGFloat(p) / 100))
                        }
                    }
                    .frame(height: 6)
                    .padding(.top, 3)
                } else {
                    Text(toast.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(theme.color(theme.fg))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background { GlassBackground(theme: theme, shape: shape) }
        .clipShape(shape)
        .overlay(shape.strokeBorder(Color.white.opacity(theme.isLight ? 0.5 : 0.14), lineWidth: 1))
        .shadow(color: .black.opacity(theme.isLight ? 0.16 : 0.35), radius: 14, y: 6)
        .scaleEffect(model.visible ? 1 : 0.94)
        .opacity(model.visible ? 1 : 0)
        .padding(margin)
        .environment(\.colorScheme, theme.colorScheme)
    }
}

private struct GlassBackground<S: Shape>: View {
    let theme: Theme
    let shape: S

    var body: some View {
        if #available(macOS 26.0, *) {
            Color.clear
                .glassEffect(.regular.tint(theme.color(theme.bg).opacity(theme.isLight ? 0.5 : 0.62)), in: shape)
        } else {
            ZStack {
                VisualEffect(material: theme.isLight ? .popover : .hudWindow)
                theme.color(theme.bg).opacity(0.55)
            }
        }
    }
}

struct VisualEffect: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = material
        v.blendingMode = .behindWindow
        v.state = .active
        return v
    }
    func updateNSView(_ v: NSVisualEffectView, context: Context) { v.material = material }
}
