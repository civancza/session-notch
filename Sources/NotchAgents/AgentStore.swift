import Foundation
import Combine

/// Polls every provider, applies the one listing policy, and publishes the result.
final class AgentStore: ObservableObject {
    @Published private(set) var agents: [Agent] = []

    private let providers: [AgentProvider]
    private let queue = DispatchQueue(label: "notch.store", qos: .utility)
    private var timer: DispatchSourceTimer?

    init(providers: [AgentProvider] = [ClaudeProvider(), CopilotProvider()]) {
        self.providers = providers
    }

    func start() {
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now(), repeating: Config.pollInterval, leeway: .milliseconds(300))
        t.setEventHandler { [weak self] in
            guard let self else { return }
            let result = self.collect()
            DispatchQueue.main.async { if self.agents != result { self.agents = result } }
        }
        t.resume()
        timer = t
    }

    /// Listing policy, in one place: working sessions always show; anything else
    /// only while recent. Working first, then needs-you, then idle; newest first within each.
    func collect(now: Date = Date()) -> [Agent] {
        let since = now.addingTimeInterval(-Config.idleWindow)
        return providers.flatMap { $0.sessions(since: since) }
            .filter { $0.state == .working || $0.lastActivity >= since }
            .sorted { ($0.state, $1.lastActivity) < ($1.state, $0.lastActivity) }
            .prefix(Config.maxRows).map { $0 }
    }
}
