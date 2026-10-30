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
        case heart = "heart.fill"
        case heartSlash = "heart.slash"
        case moon = "moon.zzz.fill"
        case undo = "arrow.uturn.backward"
        case update = "arrow.down.circle.fill"
        case move = "arrow.up.and.down.and.arrow.left.and.right"
        case library = "music.note.list"
    }

    /// Song position at the moment the toast was shown; the HUD advances it live if `playing`.
    struct Track: Equatable {
        var elapsed: TimeInterval
        var duration: TimeInterval
        var playing: Bool
        var shownAt = Date()
    }

    var icon: Icon
    var badge: String
    var title: String
    var progress: Int? = nil
    var track: Track? = nil
    /// Label for a clickable button on the HUD (makes the HUD accept clicks while shown).
    var actionLabel: String? = nil

    static let resumed = Toast(icon: .play, badge: "PLAYBACK", title: "Resumed")
    static let paused = Toast(icon: .pause, badge: "PLAYBACK", title: "Paused")
    static let autoPaused = Toast(icon: .pause, badge: "AUTO-PAUSED", title: "Device Disconnected")
    static let folderEmpty = Toast(icon: .music, badge: "LIBRARY", title: "Folder Empty: Add Songs")
    static let scanning = Toast(icon: .library, badge: "LIBRARY", title: "Scanning Library…")
    static let alreadyRunning = Toast(icon: .check, badge: "ACTIVE", title: "Already Running in Background")
    static let noSong = Toast(icon: .music, badge: "LOFI HUD", title: "No Song Playing")
    static let removeFailed = Toast(icon: .error, badge: "ERROR", title: "Failed to remove file")
    static let undoFailed = Toast(icon: .error, badge: "ERROR", title: "Couldn’t restore the song")
    static let sleepOff = Toast(icon: .moon, badge: "SLEEP TIMER", title: "Off")
    static let sleepDone = Toast(icon: .moon, badge: "SLEEP TIMER", title: "Good night")
    static let positioning = Toast(
        icon: .move, badge: "HUD POSITION", title: "Drag me anywhere", actionLabel: "Done")

    static func nowPlaying(_ title: String, track: Track? = nil) -> Toast {
        Toast(icon: .music, badge: "NOW PLAYING", title: title, track: track)
    }
    static func removed(_ title: String, undoable: Bool) -> Toast {
        Toast(icon: .trash, badge: "REMOVED", title: title, actionLabel: undoable ? "Undo" : nil)
    }
    static func restored(_ title: String) -> Toast { Toast(icon: .undo, badge: "RESTORED", title: title) }
    static func favorited(_ title: String) -> Toast { Toast(icon: .heart, badge: "FAVORITED", title: title) }
    static func unfavorited(_ title: String) -> Toast { Toast(icon: .heartSlash, badge: "UNFAVORITED", title: title) }
    static func rescanned(_ count: Int) -> Toast {
        Toast(icon: .check, badge: "LIBRARY", title: "Library Rescanned: \(count) Tracks")
    }
    static func newTracks(_ count: Int) -> Toast {
        Toast(icon: .library, badge: "LIBRARY", title: "\(count) New Track\(count == 1 ? "" : "s") Added")
    }
    static func sleep(_ title: String) -> Toast { Toast(icon: .moon, badge: "SLEEP TIMER", title: title) }
    static func info(_ badge: String, _ title: String, icon: Icon = .check) -> Toast {
        Toast(icon: icon, badge: badge, title: title)
    }
    static func update(_ version: String) -> Toast {
        Toast(icon: .update, badge: "UPDATE AVAILABLE", title: "LoFi HUD \(version)", actionLabel: "View")
    }
    static func volume(_ value: Int) -> Toast {
        Toast(icon: value == 0 ? .muted : .volume, badge: "VOLUME", title: "\(value)%", progress: value)
    }
}

enum HUDPosition: String, CaseIterable {
    case topLeft = "Top Left", topCenter = "Top Center", topRight = "Top Right"
    case bottomLeft = "Bottom Left", bottomCenter = "Bottom Center", bottomRight = "Bottom Right"
    case center = "Center"
    case custom = "Custom"
}

/// Where the HUD goes: a preset or custom spot on a chosen display.
struct HUDPlacement {
    var position: String
    var display: String
    var customX: Double
    var customY: Double

    init(_ c: AppConfig) {
        position = c.hudPosition
        display = c.hudDisplay
        customX = c.hudCustomX
        customY = c.hudCustomY
    }

    init(position: String, display: String, customX: Double, customY: Double) {
        self.position = position
        self.display = display
        self.customX = customX
        self.customY = customY
    }
}

final class HUDModel: ObservableObject {
    @Published var toast = Toast.noSong
    @Published var theme = Themes.resolve(nil)
    @Published var visible = false
    @Published var draggable = false
    var onAction: (() -> Void)?
    var onDrag: ((_ ended: Bool) -> Void)?
}

/// Floating, non-activating overlay. Click-through unless it shows a button.
final class HUDController {
    private static let height: CGFloat = 68
    private static let margin: CGFloat = 24  // transparent room for the drop shadow
    private static let edgeInset = CGSize(width: 30, height: 40)

    private let model = HUDModel()
    private let panel: NSPanel
    private var hideWork: DispatchWorkItem?
    private var generation = 0
    private var dragOffset: NSPoint?
    private var positioningDone: ((_ display: String?, _ x: Double, _ y: Double) -> Void)?

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
        let host = FirstMouseHostingView(rootView: HUDView(model: model, margin: Self.margin))
        host.sizingOptions = []
        panel.contentView = host

        model.onDrag = { [weak self] ended in self?.dragged(ended: ended) }
    }

    var isPositioning: Bool { positioningDone != nil }

    func show(_ toast: Toast, theme: Theme, placement: HUDPlacement, duration: Int, onAction: (() -> Void)? = nil) {
        guard !isPositioning else { return }
        let width = Self.width(for: toast)
        let size = NSSize(width: width + Self.margin * 2, height: Self.height + Self.margin * 2)
        let frame = NSRect(origin: Self.origin(for: placement, size: size), size: size)

        generation += 1
        hideWork?.cancel()
        panel.setFrame(frame, display: false)
        panel.ignoresMouseEvents = toast.actionLabel == nil
        model.onAction = onAction
        model.draggable = false
        present(toast, theme: theme)

        // Give clickable toasts a little longer so there's time to reach the button.
        let ms = toast.actionLabel == nil ? duration : max(duration, 5000)
        let work = DispatchWorkItem { [weak self] in self?.hide() }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(max(300, ms)), execute: work)
    }

    /// Show a draggable HUD; `done` receives the display it ended on and its center as screen fractions.
    func beginPositioning(theme: Theme, placement: HUDPlacement,
                          done: @escaping (_ display: String?, _ x: Double, _ y: Double) -> Void) {
        generation += 1
        hideWork?.cancel()
        positioningDone = done
        let toast = Toast.positioning
        let size = NSSize(width: Self.width(for: toast) + Self.margin * 2, height: Self.height + Self.margin * 2)
        panel.setFrame(NSRect(origin: Self.origin(for: placement, size: size), size: size), display: false)
        panel.ignoresMouseEvents = false
        model.draggable = true
        model.onAction = { [weak self] in self?.endPositioning() }
        present(toast, theme: theme)
    }

    func endPositioning() {
        guard let done = positioningDone else { return }
        positioningDone = nil
        let box = panel.frame.insetBy(dx: Self.margin, dy: Self.margin)
        let center = NSPoint(x: box.midX, y: box.midY)
        let screen = NSScreen.screens.first { NSMouseInRect(center, $0.frame, false) } ?? Self.screen(for: "mouse")
        let vf = screen.visibleFrame
        done(screen.localizedName, Double((center.x - vf.minX) / vf.width), Double((center.y - vf.minY) / vf.height))
        model.draggable = false
        hide()
    }

    func hide() {
        hideWork?.cancel()
        hideWork = nil
        let gen = generation
        withAnimation(.easeIn(duration: 0.2)) { model.visible = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let self, self.generation == gen else { return }
            self.panel.orderOut(nil)
            self.panel.ignoresMouseEvents = true
            self.model.onAction = nil
        }
    }

    private func present(_ toast: Toast, theme: Theme) {
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
    }

    private func dragged(ended: Bool) {
        let mouse = NSEvent.mouseLocation
        if ended {
            dragOffset = nil
            return
        }
        if dragOffset == nil {
            dragOffset = NSPoint(x: mouse.x - panel.frame.minX, y: mouse.y - panel.frame.minY)
        }
        guard let offset = dragOffset else { return }
        panel.setFrameOrigin(NSPoint(x: mouse.x - offset.x, y: mouse.y - offset.y))
    }

    private static func width(for toast: Toast) -> CGFloat {
        if toast.progress != nil { return 300 }
        let font = NSFont.systemFont(ofSize: 14, weight: .semibold)
        let text = (toast.title as NSString).size(withAttributes: [.font: font]).width
        let button: CGFloat = toast.actionLabel == nil ? 0 : 74
        return min(440 + button, max(240, ceil(text) + 90 + button))
    }

    static func screen(for display: String) -> NSScreen {
        let fallback = NSScreen.main ?? NSScreen.screens.first!
        let mouseScreen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }
        switch display {
        case "primary": return NSScreen.screens.first ?? fallback
        case "mouse": return mouseScreen ?? fallback
        default: return NSScreen.screens.first { $0.localizedName == display } ?? mouseScreen ?? fallback
        }
    }

    private static func origin(for placement: HUDPlacement, size: NSSize) -> NSPoint {
        let vf = screen(for: placement.display).visibleFrame
        let m = margin
        let w = size.width - m * 2, h = size.height - m * 2
        let px = edgeInset.width, py = edgeInset.height
        let left = vf.minX + px, right = vf.maxX - w - px, midX = vf.midX - w / 2
        let top = vf.maxY - h - py, bottom = vf.minY + py, midY = vf.midY - h / 2

        let p: NSPoint
        switch HUDPosition(rawValue: placement.position) ?? .bottomCenter {
        case .topLeft: p = NSPoint(x: left, y: top)
        case .topCenter: p = NSPoint(x: midX, y: top)
        case .topRight: p = NSPoint(x: right, y: top)
        case .bottomLeft: p = NSPoint(x: left, y: bottom)
        case .bottomRight: p = NSPoint(x: right, y: bottom)
        case .center: p = NSPoint(x: midX, y: midY)
        case .bottomCenter: p = NSPoint(x: midX, y: bottom)
        case .custom:
            let cx = vf.minX + vf.width * placement.customX, cy = vf.minY + vf.height * placement.customY
            p = NSPoint(x: min(max(cx - w / 2, vf.minX), vf.maxX - w),
                        y: min(max(cy - h / 2, vf.minY), vf.maxY - h))
        }
        return NSPoint(x: round(p.x - m), y: round(p.y - m))
    }
}

/// Lets the first click on the HUD's button work without activating the app.
private final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
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
                    Bar(fraction: Double(p) / 100, theme: theme, height: 6)
                        .padding(.top, 3)
                } else {
                    Text(toast.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(theme.color(theme.fg))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    if let track = toast.track, track.duration > 0 {
                        TrackBar(track: track, theme: theme)
                    }
                }
            }

            if let label = toast.actionLabel {
                Button {
                    model.onAction?()
                } label: {
                    Text(label)
                        .font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .foregroundStyle(theme.color(theme.onAccent))
                        .background(Capsule().fill(accent))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(label)
            }
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background { GlassBackground(theme: theme, shape: shape) }
        .clipShape(shape)
        .overlay(shape.strokeBorder(
            model.draggable ? accent : Color.white.opacity(theme.isLight ? 0.5 : 0.14),
            style: StrokeStyle(lineWidth: model.draggable ? 2 : 1, dash: model.draggable ? [6, 4] : [])))
        .shadow(color: .black.opacity(theme.isLight ? 0.16 : 0.35), radius: 14, y: 6)
        .contentShape(shape)
        .gesture(
            DragGesture(minimumDistance: 1)
                .onChanged { _ in if model.draggable { model.onDrag?(false) } }
                .onEnded { _ in if model.draggable { model.onDrag?(true) } },
            including: model.draggable ? .all : .subviews)
        .scaleEffect(model.visible ? 1 : 0.94)
        .opacity(model.visible ? 1 : 0)
        .padding(margin)
        .environment(\.colorScheme, theme.colorScheme)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(toast.badge.capitalized): \(toast.title)")
    }
}

private struct Bar: View {
    let fraction: Double
    let theme: Theme
    let height: CGFloat

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(theme.color(theme.fg).opacity(0.14))
                Capsule().fill(theme.color(theme.accent))
                    .frame(width: max(0, geo.size.width * CGFloat(min(1, max(0, fraction)))))
            }
        }
        .frame(height: height)
    }
}

/// Thin song-position bar that keeps moving while the HUD is visible.
private struct TrackBar: View {
    let track: Toast.Track
    let theme: Theme

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            let live = track.playing ? context.date.timeIntervalSince(track.shownAt) : 0
            Bar(fraction: (track.elapsed + live) / track.duration, theme: theme, height: 3)
                .animation(.linear(duration: 0.5), value: context.date)
        }
        .frame(height: 3)
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
