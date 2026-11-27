import AppKit
import Combine

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = AgentStore()
    private var overlays: [ScreenOverlay] = []
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ n: Notification) {
        NSApp.setActivationPolicy(.accessory)
        rebuildOverlays()
        store.$agents.receive(on: DispatchQueue.main).sink { [weak self] _ in
            self?.overlays.forEach { $0.repositionIfExpanded() }
        }.store(in: &cancellables)
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in self?.rebuildOverlays() }
        store.start()
        if CommandLine.arguments.contains("--expanded") { overlays.forEach { $0.setExpanded(true) } }
    }

    /// Screens come and go (dock/undock, sleep); recreate one overlay per current screen.
    private func rebuildOverlays() {
        overlays.forEach { $0.close() }
        overlays = NSScreen.screens.map { ScreenOverlay(screen: $0, store: store) { [weak self] in self?.open($0) } }
    }

    private func open(_ agent: Agent) {
        if let url = agent.url { NSWorkspace.shared.open(url) }
        overlays.forEach { $0.setExpanded(false) }
    }
}

if CommandLine.arguments.contains("--dump") {
    for a in AgentStore().collect() { print("\(a.state)\t\(a.provider.rawValue)\t\(a.sessionId)\t\(a.project)\t\(a.title)") }
    exit(0)
}
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
