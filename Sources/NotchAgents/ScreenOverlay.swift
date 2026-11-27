import AppKit
import SwiftUI

/// Notch (or menu-bar) dimensions for one screen, and the panel size for each state.
struct NotchGeometry {
    let notchWidth: CGFloat
    let notchHeight: CGFloat
    /// One width for both states, so opening only ever grows downward from the top edge.
    static let width: CGFloat = 320
    private static let minWing: CGFloat = 52
    static let rowHeight: CGFloat = 46
    private static let listPadding: CGFloat = 16

    init(screen: NSScreen) {
        if screen.safeAreaInsets.top > 0, let l = screen.auxiliaryTopLeftArea, let r = screen.auxiliaryTopRightArea {
            notchWidth = screen.frame.width - l.width - r.width
            notchHeight = screen.safeAreaInsets.top
        } else {
            // No camera housing: a slim pill the height of the menu bar.
            let bar = screen.frame.maxY - screen.visibleFrame.maxY
            notchWidth = 180
            notchHeight = bar > 8 ? bar : 24
        }
    }

    var width: CGFloat { max(Self.width, notchWidth + Self.minWing * 2) }
    /// Space either side of the notch for the status dot and count.
    var sideWidth: CGFloat { (width - notchWidth) / 2 }

    func size(rows: Int, expanded: Bool) -> NSSize {
        guard expanded else { return NSSize(width: width, height: notchHeight) }
        let list = CGFloat(max(rows, 1)) * Self.rowHeight + Self.listPadding
        return NSSize(width: width, height: notchHeight + list)
    }
}

final class NotchModel: ObservableObject {
    @Published var expanded = false
}

/// Hosting view that reports hover via a tracking area, accepts the first click, and offers Quit.
final class HoverHostingView<Content: View>: NSHostingView<Content> {
    var onHover: ((Bool) -> Void)?
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }
    override func mouseEntered(with event: NSEvent) { onHover?(true) }
    override func mouseExited(with event: NSEvent) { onHover?(false) }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func rightMouseDown(with event: NSEvent) {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Quit Notch Agents", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }
}

final class Panel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// One overlay per physical screen. Owns its panel, geometry and hover state.
final class ScreenOverlay {
    let model = NotchModel()
    private let screen: NSScreen
    private let geometry: NotchGeometry
    private let panel: Panel
    private let store: AgentStore
    private var collapseWork: DispatchWorkItem?

    init(screen: NSScreen, store: AgentStore, open: @escaping (Agent) -> Void) {
        self.screen = screen
        self.store = store
        geometry = NotchGeometry(screen: screen)
        let host = HoverHostingView(rootView: NotchView(geometry: geometry, model: model, store: store, open: open))
        panel = Panel(contentRect: NSRect(origin: .zero, size: geometry.size(rows: 0, expanded: false)),
                      styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        host.sizingOptions = []   // the window, not SwiftUI content, decides the size
        panel.contentView = host
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.isMovable = false
        host.onHover = { [weak self] in self?.setExpanded($0) }
        reposition(animated: false)
        panel.orderFrontRegardless()
    }

    static let animationDuration = 0.3

    /// Sizes the window for the current state, pinned to the top edge of the screen.
    /// Animating the window itself (instead of the SwiftUI content) keeps the top fixed: origin.y and
    /// height interpolate together, so origin.y + height never moves.
    func reposition(animated: Bool) {
        let size = geometry.size(rows: store.agents.count, expanded: model.expanded)
        let f = screen.frame
        let frame = NSRect(x: f.midX - size.width / 2, y: f.maxY - size.height, width: size.width, height: size.height)
        guard animated else { panel.setFrame(frame, display: true); return }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = Self.animationDuration
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().setFrame(frame, display: true)
        }
    }

    /// Row count changed while open: grow or shrink the window to match.
    func repositionIfExpanded() { if model.expanded { reposition(animated: true) } }

    /// Expands immediately; collapses after a short delay so crossing the edge doesn't flicker.
    func setExpanded(_ on: Bool) {
        collapseWork?.cancel()
        if on {
            guard !model.expanded else { return }
            model.expanded = true
            reposition(animated: true)
        } else {
            let work = DispatchWorkItem { [weak self] in
                self?.model.expanded = false
                self?.reposition(animated: true)
            }
            collapseWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
        }
    }

    func close() { collapseWork?.cancel(); panel.orderOut(nil) }
}
