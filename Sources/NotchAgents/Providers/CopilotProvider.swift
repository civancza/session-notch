import Foundation
import SQLite3

/// GitHub Copilot desktop app: sessions live in ~/.copilot/data.db (opened read-only).
/// `is_running` is the live signal; `was_interrupted` surfaces as "needs you".
final class CopilotProvider: AgentProvider {
    private let path = Config.home.appendingPathComponent(".copilot/data.db").path
    private var db: OpaquePointer?
    private var warned = false

    private let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f
    }()

    private enum Col: Int32 { case id, title, running, interrupted, updated, workspace, branch }
    private static let sql = """
        SELECT s.id, COALESCE(s.title,'Untitled'), s.is_running, s.was_interrupted, s.updated_at,
               COALESCE(w.name,''), COALESCE(w.branch,'')
        FROM sessions s
        LEFT JOIN workspace_session_aliases a ON a.session_id = s.id
        LEFT JOIN workspaces w ON w.id = a.workspace_id
        WHERE s.archived_at IS NULL AND s.provisional = 0
          AND (s.is_running = 1 OR s.updated_at >= ?1)
        ORDER BY s.updated_at DESC
        """

    deinit { sqlite3_close(db) }

    func sessions(since: Date) -> [Agent] {
        guard let db = connection() else { return [] }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, Self.sql, -1, &stmt, nil) == SQLITE_OK else {
            warnOnce("prepare failed (schema changed?): \(String(cString: sqlite3_errmsg(db)))")
            return []
        }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, iso.string(from: since), -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))

        func text(_ c: Col) -> String { sqlite3_column_text(stmt, c.rawValue).map { String(cString: $0) } ?? "" }
        func flag(_ c: Col) -> Bool { sqlite3_column_int(stmt, c.rawValue) != 0 }

        var out: [Agent] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let running = flag(.running), interrupted = flag(.interrupted)
            let workspace = text(.workspace)
            out.append(Agent(provider: .copilot, sessionId: text(.id), title: text(.title),
                             project: workspace.isEmpty ? "Copilot" : workspace,
                             detail: interrupted && !running ? "Interrupted" : text(.branch),
                             state: running ? .working : (interrupted ? .needsYou : .idle),
                             lastActivity: iso.date(from: text(.updated)) ?? .distantPast,
                             url: URL(string: "ghapp://sessions/\(text(.id))")))
        }
        return out
    }

    private func connection() -> OpaquePointer? {
        if db == nil {
            guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
                if FileManager.default.fileExists(atPath: path) { warnOnce("cannot open \(path)") }
                sqlite3_close(db); db = nil; return nil
            }
            sqlite3_busy_timeout(db, 200)
        }
        return db
    }

    private func warnOnce(_ message: String) {
        guard !warned else { return }
        warned = true
        NSLog("NotchAgents/Copilot: %@", message)
    }
}
