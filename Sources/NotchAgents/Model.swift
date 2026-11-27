import Foundation

enum AgentState: Int, Comparable {
    case working = 0, needsYou = 1, idle = 2
    static func < (a: AgentState, b: AgentState) -> Bool { a.rawValue < b.rawValue }
}

enum Provider: String {
    case claude = "Claude", copilot = "Copilot"
}

/// One session from one desktop app, normalized.
struct Agent: Identifiable, Equatable {
    let provider: Provider
    let sessionId: String
    let title: String
    let project: String
    let detail: String
    let state: AgentState
    let lastActivity: Date
    /// Deep link that focuses this session in its desktop app.
    let url: URL?

    var id: String { "\(provider.rawValue):\(sessionId)" }
}

/// A source of agent sessions. Implementations are called from the store's queue only.
protocol AgentProvider {
    /// Every live or recent session. May skip anything idle since before `since`,
    /// but must never drop a working session.
    func sessions(since: Date) -> [Agent]
}

enum Config {
    /// How long a non-working session stays listed. Override with NOTCH_IDLE_HOURS.
    static let idleWindow: TimeInterval =
        (Double(ProcessInfo.processInfo.environment["NOTCH_IDLE_HOURS"] ?? "") ?? 12) * 3600
    static let pollInterval: TimeInterval = 2
    /// Most sessions listed; the panel is sized for exactly this many rows at most.
    static let maxRows = 10
    static let home = FileManager.default.homeDirectoryForCurrentUser
}
