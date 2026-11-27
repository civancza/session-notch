import Foundation

/// Claude Desktop: session metadata JSON files, plus the live transcript for "working".
/// - working: the session's transcript (.jsonl) was written in the last few seconds
/// - needsYou: the last turn summary says "blocked", or the transcript ends with an
///   AskUserQuestion / ExitPlanMode call that has no answer yet
final class ClaudeProvider: AgentProvider {
    private let sessionsRoot = Config.home.appendingPathComponent("Library/Application Support/Claude/claude-code-sessions")
    private let projectsRoot = Config.home.appendingPathComponent(".claude/projects")
    private static let liveWindow: TimeInterval = 6
    private static let blocked = "blocked"
    private static let askTools: Set<String> = ["AskUserQuestion", "ExitPlanMode"]
    private static let tailBytes = 512 * 1024

    private struct SessionFile: Decodable {
        struct Summary: Decodable { let status_category: String?; let status_detail: String? }
        let sessionId: String
        let cliSessionId: String?
        let title: String?
        let cwd: String?
        let isArchived: Bool?
        let lastActivityAt: Double?   // ms since epoch
        let postTurnSummary: Summary?
    }

    /// Parsed files keyed by path; re-parsed only when the file's mtime changes.
    private var cache: [URL: (mtime: Date, file: SessionFile)] = [:]
    /// Whether a transcript awaits an answer, keyed by transcript path; re-read only when it changes.
    private var awaiting: [URL: (mtime: Date, value: Bool)] = [:]

    func sessions(since: Date) -> [Agent] {
        let now = Date()
        var seen = Set<URL>()
        guard let files = FileManager.default.enumerator(at: sessionsRoot, includingPropertiesForKeys: [.contentModificationDateKey],
                                                         options: [.skipsHiddenFiles]) else { return [] }
        for case let url as URL in files {
            guard url.lastPathComponent.hasPrefix("local_"), url.pathExtension == "json",
                  let mtime = Self.mtime(url), mtime > since else { continue }
            seen.insert(url)
            if cache[url]?.mtime == mtime { continue }
            if let data = try? Data(contentsOf: url), let file = try? JSONDecoder().decode(SessionFile.self, from: data) {
                cache[url] = (mtime, file)
            }
        }
        cache = cache.filter { seen.contains($0.key) }

        return cache.values.map(\.file).filter { $0.isArchived != true }.map { f in
            let cwd = f.cwd ?? ""
            let transcript = transcript(cwd: cwd, cliId: f.cliSessionId)
            let transcriptMtime = Self.mtime(transcript)
            let live = transcriptMtime.map { now.timeIntervalSince($0) < Self.liveWindow } ?? false
            let blocked = f.postTurnSummary?.status_category == Self.blocked
                || isAwaitingAnswer(transcript, mtime: transcriptMtime)
            var comps = URLComponents(string: "claude://code/continue")!
            comps.queryItems = [URLQueryItem(name: "session", value: f.sessionId),
                                URLQueryItem(name: "source", value: "desktop_action")]
            return Agent(provider: .claude, sessionId: f.sessionId, title: f.title ?? "Untitled",
                         project: URL(fileURLWithPath: cwd).lastPathComponent,
                         detail: f.postTurnSummary?.status_detail ?? "",
                         state: live ? .working : (blocked ? .needsYou : .idle),
                         lastActivity: Date(timeIntervalSince1970: (f.lastActivityAt ?? 0) / 1000),
                         url: comps.url)
        }
    }

    /// Claude Code stores transcripts at projects/<cwd with non-alphanumerics → "-">/<cliSessionId>.jsonl
    private func transcript(cwd: String, cliId: String?) -> URL? {
        guard let cliId, !cliId.isEmpty else { return nil }
        let dir = cwd.replacingOccurrences(of: "[^A-Za-z0-9]", with: "-", options: .regularExpression)
        return projectsRoot.appendingPathComponent(dir).appendingPathComponent("\(cliId).jsonl")
    }

    /// True when the transcript's recent tail holds an ask-the-user tool call with no matching result.
    private func isAwaitingAnswer(_ url: URL?, mtime: Date?) -> Bool {
        guard let url, let mtime else { return false }
        if let hit = awaiting[url], hit.mtime == mtime { return hit.value }
        let value = Self.hasUnansweredAsk(url)
        awaiting[url] = (mtime, value)
        return value
    }

    private static func hasUnansweredAsk(_ url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        guard let size = try? handle.seekToEnd() else { return false }
        let start = size > UInt64(tailBytes) ? size - UInt64(tailBytes) : 0
        try? handle.seek(toOffset: start)
        guard let data = try? handle.readToEnd() else { return false }
        var asked = Set<String>(), answered = Set<String>()
        // A tail that starts mid-file begins with a partial line; drop it.
        for line in data.split(separator: UInt8(ascii: "\n")).dropFirst(start > 0 ? 1 : 0) {
            guard let obj = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                  let message = obj["message"] as? [String: Any],
                  let blocks = message["content"] as? [[String: Any]] else { continue }
            for block in blocks {
                switch block["type"] as? String {
                case "tool_use":
                    if let name = block["name"] as? String, askTools.contains(name), let id = block["id"] as? String { asked.insert(id) }
                case "tool_result":
                    if let id = block["tool_use_id"] as? String { answered.insert(id) }
                default: break
                }
            }
        }
        return !asked.subtracting(answered).isEmpty
    }

    private static func mtime(_ url: URL?) -> Date? {
        try? url?.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }
}
