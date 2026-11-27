import Foundation

/// Fixed sample sessions (`--demo`), for screenshots and for trying the widget without any desktop app.
struct DemoProvider: AgentProvider {
    func sessions(since: Date) -> [Agent] {
        let now = Date()
        func agent(_ provider: Provider, _ id: String, _ title: String, _ project: String,
                   _ state: AgentState, minutesAgo: Double = 0) -> Agent {
            Agent(provider: provider, sessionId: id, title: title, project: project, detail: "",
                  state: state, lastActivity: now.addingTimeInterval(-minutesAgo * 60), url: nil)
        }
        return [
            agent(.claude, "b", "Refactor payment service", "storefront", .working),
            agent(.copilot, "a", "Add dark mode to settings", "mobile-app", .working),
            agent(.claude, "c", "Which database to use?", "inventory-api", .needsYou, minutesAgo: 3),
            agent(.claude, "d", "Fix flaky login test", "storefront", .idle, minutesAgo: 25),
            agent(.copilot, "e", "Write release notes", "docs-site", .idle, minutesAgo: 95),
        ]
    }
}
