import Foundation
import SQLite3

/// Manages the SQLite database connection and provides CRUD operations for all tables.
final class DatabaseManager {

    // MARK: - Properties

    private var db: OpaquePointer?
    private let dbPath: String
    private let queue = DispatchQueue(label: "com.mikefullerton.whippet.database", qos: .userInitiated)

    /// The current schema version. Increment this when adding new migrations.
    static let currentSchemaVersion = 2

    // MARK: - Initialization

    /// Creates a DatabaseManager with the database at the specified path.
    /// If no path is given, uses the default Application Support location.
    init(path: String? = nil) throws {
        if let path = path {
            self.dbPath = path
        } else {
            self.dbPath = try DatabaseManager.defaultDatabasePath()
        }
        try openDatabase()
        try runMigrations()
        Log.database.info("Database ready at \(self.dbPath, privacy: .public)")
    }

    deinit {
        close()
    }

    // MARK: - Database Path

    /// Returns the default database path: ~/Library/Application Support/Whippet/whippet.db
    static func defaultDatabasePath() throws -> String {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        let whippetDir = appSupport.appendingPathComponent("Whippet")

        try FileManager.default.createDirectory(
            at: whippetDir,
            withIntermediateDirectories: true
        )

        return whippetDir.appendingPathComponent("whippet.db").path
    }

    // MARK: - Connection

    private func openDatabase() throws {
        Log.database.debug("Opening database at \(self.dbPath, privacy: .public)")
        let result = sqlite3_open(dbPath, &db)
        guard result == SQLITE_OK else {
            let message = String(cString: sqlite3_errmsg(db))
            Log.database.error("Failed to open database: \(message, privacy: .public)")
            throw DatabaseError.openFailed(message)
        }

        // Enable WAL mode for better concurrent read performance
        try execute("PRAGMA journal_mode=WAL")
        // Enable foreign keys
        try execute("PRAGMA foreign_keys=ON")
        Log.database.debug("Database opened — WAL mode enabled")
    }

    func close() {
        if let db = db {
            sqlite3_close(db)
            self.db = nil
            Log.database.info("Database connection closed")
        }
    }

    // MARK: - Migrations

    private func runMigrations() throws {
        // Create the migrations tracking table if it doesn't exist
        try execute("""
            CREATE TABLE IF NOT EXISTS schema_migrations (
                version INTEGER PRIMARY KEY,
                applied_at TEXT NOT NULL DEFAULT (datetime('now'))
            )
        """)

        let currentVersion = try schemaVersion()
        Log.database.debug("Current schema version: \(currentVersion)")

        if currentVersion < 1 {
            Log.database.info("Running migration 001: create tables")
            try migration001_createTables()
            Log.database.info("Migration 001 complete")
        }

        if currentVersion < 2 {
            Log.database.info("Running migration 002: add session metadata")
            try migration002_addSessionMetadata()
            Log.database.info("Migration 002 complete")
        }
    }

    private func schemaVersion() throws -> Int {
        let sql = "SELECT COALESCE(MAX(version), 0) FROM schema_migrations"
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }

        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed(lastErrorMessage)
        }

        guard sqlite3_step(stmt) == SQLITE_ROW else {
            return 0
        }

        return Int(sqlite3_column_int(stmt, 0))
    }

    private func migration001_createTables() throws {
        try execute("""
            CREATE TABLE IF NOT EXISTS sessions (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                session_id TEXT NOT NULL UNIQUE,
                cwd TEXT NOT NULL DEFAULT '',
                model TEXT NOT NULL DEFAULT '',
                started_at TEXT NOT NULL DEFAULT (datetime('now')),
                last_activity_at TEXT NOT NULL DEFAULT (datetime('now')),
                last_tool TEXT NOT NULL DEFAULT '',
                status TEXT NOT NULL DEFAULT 'active' CHECK(status IN ('active', 'stale', 'ended'))
            )
        """)

        try execute("""
            CREATE INDEX IF NOT EXISTS idx_sessions_session_id ON sessions(session_id)
        """)

        try execute("""
            CREATE INDEX IF NOT EXISTS idx_sessions_status ON sessions(status)
        """)

        try execute("""
            CREATE TABLE IF NOT EXISTS events (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                session_id TEXT NOT NULL,
                event_type TEXT NOT NULL,
                timestamp TEXT NOT NULL DEFAULT (datetime('now')),
                raw_json TEXT NOT NULL DEFAULT '{}',
                FOREIGN KEY (session_id) REFERENCES sessions(session_id)
            )
        """)

        try execute("""
            CREATE INDEX IF NOT EXISTS idx_events_session_id ON events(session_id)
        """)

        try execute("""
            CREATE INDEX IF NOT EXISTS idx_events_event_type ON events(event_type)
        """)

        try execute("""
            CREATE TABLE IF NOT EXISTS settings (
                key TEXT PRIMARY KEY,
                value TEXT NOT NULL
            )
        """)

        try execute("INSERT INTO schema_migrations (version) VALUES (1)")
    }

    private func migration002_addSessionMetadata() throws {
        try execute("ALTER TABLE sessions ADD COLUMN git_branch TEXT NOT NULL DEFAULT ''")
        try execute("ALTER TABLE sessions ADD COLUMN summary TEXT NOT NULL DEFAULT ''")
        try execute("INSERT INTO schema_migrations (version) VALUES (2)")
    }

    // MARK: - SQL Helpers

    private var lastErrorMessage: String {
        if let db = db {
            return String(cString: sqlite3_errmsg(db))
        }
        return "Database not open"
    }

    @discardableResult
    func execute(_ sql: String) throws -> Int32 {
        var errorMessage: UnsafeMutablePointer<CChar>?
        let result = sqlite3_exec(db, sql, nil, nil, &errorMessage)
        if result != SQLITE_OK {
            let message = errorMessage.map { String(cString: $0) } ?? "Unknown error"
            sqlite3_free(errorMessage)
            Log.database.error("SQL execution failed: \(message, privacy: .public)")
            throw DatabaseError.executionFailed(message)
        }
        return result
    }

    // MARK: - Session CRUD

    /// Inserts a new session or updates an existing one (upsert).
    @discardableResult
    func upsertSession(_ session: Session) throws -> Session {
        let sql = """
            INSERT INTO sessions (session_id, cwd, model, started_at, last_activity_at, last_tool, status, git_branch, summary)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(session_id) DO UPDATE SET
                cwd = CASE WHEN excluded.cwd != '' THEN excluded.cwd ELSE sessions.cwd END,
                model = CASE WHEN excluded.model != '' THEN excluded.model ELSE sessions.model END,
                last_activity_at = excluded.last_activity_at,
                last_tool = CASE WHEN excluded.last_tool != '' THEN excluded.last_tool ELSE sessions.last_tool END,
                status = excluded.status,
                git_branch = CASE WHEN excluded.git_branch != '' THEN excluded.git_branch ELSE sessions.git_branch END,
                summary = CASE WHEN excluded.summary != '' THEN excluded.summary ELSE sessions.summary END
        """

        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }

        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed(lastErrorMessage)
        }

        sqlite3_bind_text(stmt, 1, (session.sessionId as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 2, (session.cwd as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 3, (session.model as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 4, (session.startedAt as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 5, (session.lastActivityAt as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 6, (session.lastTool as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 7, (session.status.rawValue as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 8, (session.gitBranch as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 9, (session.summary as NSString).utf8String, -1, nil)

        guard sqlite3_step(stmt) == SQLITE_DONE else {
            Log.database.error("Upsert session failed for \(session.sessionId, privacy: .public): \(self.lastErrorMessage, privacy: .public)")
            throw DatabaseError.executionFailed(lastErrorMessage)
        }

        Log.database.debug("Upserted session \(session.sessionId, privacy: .public) status=\(session.status.rawValue, privacy: .public)")

        // Return the session with its database ID
        if let fetched = try fetchSession(bySessionId: session.sessionId) {
            return fetched
        }
        return session
    }

    /// Fetches a session by its unique session_id string.
    func fetchSession(bySessionId sessionId: String) throws -> Session? {
        let sql = "SELECT id, session_id, cwd, model, started_at, last_activity_at, last_tool, status, git_branch, summary FROM sessions WHERE session_id = ?"

        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }

        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed(lastErrorMessage)
        }

        sqlite3_bind_text(stmt, 1, (sessionId as NSString).utf8String, -1, nil)

        guard sqlite3_step(stmt) == SQLITE_ROW else {
            return nil
        }

        return sessionFromRow(stmt)
    }

    /// Fetches all sessions, optionally filtered by status.
    func fetchAllSessions(status: SessionStatus? = nil) throws -> [Session] {
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }

        if let status = status {
            let sql = "SELECT id, session_id, cwd, model, started_at, last_activity_at, last_tool, status, git_branch, summary FROM sessions WHERE status = ? ORDER BY last_activity_at DESC"

            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw DatabaseError.prepareFailed(lastErrorMessage)
            }

            sqlite3_bind_text(stmt, 1, (status.rawValue as NSString).utf8String, -1, nil)
        } else {
            let sql = "SELECT id, session_id, cwd, model, started_at, last_activity_at, last_tool, status, git_branch, summary FROM sessions ORDER BY last_activity_at DESC"

            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw DatabaseError.prepareFailed(lastErrorMessage)
            }
        }

        var sessions: [Session] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            sessions.append(sessionFromRow(stmt))
        }
        return sessions
    }

    /// Updates the status of a session.
    func updateSessionStatus(sessionId: String, status: SessionStatus) throws {
        Log.database.debug("Updating session \(sessionId, privacy: .public) → \(status.rawValue, privacy: .public)")
        let sql = "UPDATE sessions SET status = ?, last_activity_at = datetime('now') WHERE session_id = ?"

        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }

        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed(lastErrorMessage)
        }

        sqlite3_bind_text(stmt, 1, (status.rawValue as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 2, (sessionId as NSString).utf8String, -1, nil)

        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw DatabaseError.executionFailed(lastErrorMessage)
        }
    }

    /// Updates the summary of a session.
    func updateSessionSummary(sessionId: String, summary: String) throws {
        let sql = "UPDATE sessions SET summary = ? WHERE session_id = ?"

        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }

        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed(lastErrorMessage)
        }

        sqlite3_bind_text(stmt, 1, (summary as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 2, (sessionId as NSString).utf8String, -1, nil)

        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw DatabaseError.executionFailed(lastErrorMessage)
        }
    }

    /// Updates the git branch of a session.
    func updateSessionGitBranch(sessionId: String, gitBranch: String) throws {
        let sql = "UPDATE sessions SET git_branch = ? WHERE session_id = ?"

        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }

        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed(lastErrorMessage)
        }

        sqlite3_bind_text(stmt, 1, (gitBranch as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 2, (sessionId as NSString).utf8String, -1, nil)

        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw DatabaseError.executionFailed(lastErrorMessage)
        }
    }

    /// Deletes a session and all its associated events.
    func deleteSession(sessionId: String) throws {
        Log.database.info("Deleting session \(sessionId, privacy: .public) and its events")
        // Delete events first (foreign key dependency)
        let deleteEventsSql = "DELETE FROM events WHERE session_id = ?"
        var evtStmt: OpaquePointer?
        defer { sqlite3_finalize(evtStmt) }
        guard sqlite3_prepare_v2(db, deleteEventsSql, -1, &evtStmt, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed(lastErrorMessage)
        }
        sqlite3_bind_text(evtStmt, 1, (sessionId as NSString).utf8String, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        guard sqlite3_step(evtStmt) == SQLITE_DONE else {
            throw DatabaseError.executionFailed(lastErrorMessage)
        }

        // Then delete the session
        let deleteSessionSql = "DELETE FROM sessions WHERE session_id = ?"
        var sessStmt: OpaquePointer?
        defer { sqlite3_finalize(sessStmt) }
        guard sqlite3_prepare_v2(db, deleteSessionSql, -1, &sessStmt, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed(lastErrorMessage)
        }
        sqlite3_bind_text(sessStmt, 1, (sessionId as NSString).utf8String, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        guard sqlite3_step(sessStmt) == SQLITE_DONE else {
            throw DatabaseError.executionFailed(lastErrorMessage)
        }
    }

    /// Fetches active sessions that are past the given timeout (about to be marked stale).
    /// Used by the liveness monitor to know which sessions will transition to stale.
    func fetchActiveSessionsPastTimeout(_ seconds: TimeInterval) throws -> [Session] {
        let sql = """
            SELECT id, session_id, cwd, model, started_at, last_activity_at, last_tool, status, git_branch, summary
            FROM sessions
            WHERE status = 'active'
            AND datetime(last_activity_at, '+' || ? || ' seconds') < datetime('now')
        """

        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }

        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed(lastErrorMessage)
        }

        let secondsStr = String(max(0, Int(seconds)))
        sqlite3_bind_text(stmt, 1, (secondsStr as NSString).utf8String, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))

        var sessions: [Session] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            sessions.append(sessionFromRow(stmt))
        }
        return sessions
    }

    /// Marks sessions as stale if they have no activity within the given timeout interval.
    func markStaleSessions(olderThan seconds: TimeInterval) throws -> Int {
        let sql = """
            UPDATE sessions SET status = 'stale'
            WHERE status = 'active'
            AND datetime(last_activity_at, '+' || ? || ' seconds') < datetime('now')
        """

        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }

        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed(lastErrorMessage)
        }

        let secondsStr = String(max(0, Int(seconds)))
        sqlite3_bind_text(stmt, 1, (secondsStr as NSString).utf8String, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))

        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw DatabaseError.executionFailed(lastErrorMessage)
        }
        let count = Int(sqlite3_changes(db))
        if count > 0 {
            Log.database.debug("Marked \(count) session(s) as stale (timeout: \(Int(seconds))s)")
        }
        return count
    }

    private func sessionFromRow(_ stmt: OpaquePointer?) -> Session {
        Session(
            id: Int(sqlite3_column_int64(stmt, 0)),
            sessionId: String(cString: sqlite3_column_text(stmt, 1)),
            cwd: String(cString: sqlite3_column_text(stmt, 2)),
            model: String(cString: sqlite3_column_text(stmt, 3)),
            startedAt: String(cString: sqlite3_column_text(stmt, 4)),
            lastActivityAt: String(cString: sqlite3_column_text(stmt, 5)),
            lastTool: String(cString: sqlite3_column_text(stmt, 6)),
            status: SessionStatus(rawValue: String(cString: sqlite3_column_text(stmt, 7))) ?? .active,
            gitBranch: String(cString: sqlite3_column_text(stmt, 8)),
            summary: String(cString: sqlite3_column_text(stmt, 9))
        )
    }

    // MARK: - Event CRUD

    /// Inserts a new event.
    @discardableResult
    func insertEvent(_ event: SessionEvent) throws -> SessionEvent {
        let sql = """
            INSERT INTO events (session_id, event_type, timestamp, raw_json)
            VALUES (?, ?, ?, ?)
        """

        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }

        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed(lastErrorMessage)
        }

        sqlite3_bind_text(stmt, 1, (event.sessionId as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 2, (event.eventType as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 3, (event.timestamp as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 4, (event.rawJson as NSString).utf8String, -1, nil)

        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw DatabaseError.executionFailed(lastErrorMessage)
        }

        let lastId = Int(sqlite3_last_insert_rowid(db))
        return SessionEvent(
            id: lastId,
            sessionId: event.sessionId,
            eventType: event.eventType,
            timestamp: event.timestamp,
            rawJson: event.rawJson
        )
    }

    /// Fetches events for a given session.
    func fetchEvents(forSessionId sessionId: String) throws -> [SessionEvent] {
        let sql = "SELECT id, session_id, event_type, timestamp, raw_json FROM events WHERE session_id = ? ORDER BY timestamp ASC"

        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }

        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed(lastErrorMessage)
        }

        sqlite3_bind_text(stmt, 1, (sessionId as NSString).utf8String, -1, nil)

        var events: [SessionEvent] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            events.append(eventFromRow(stmt))
        }
        return events
    }

    /// Fetches all events, optionally filtered by event type.
    func fetchAllEvents(eventType: String? = nil) throws -> [SessionEvent] {
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }

        if let eventType = eventType {
            let sql = "SELECT id, session_id, event_type, timestamp, raw_json FROM events WHERE event_type = ? ORDER BY timestamp DESC"

            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw DatabaseError.prepareFailed(lastErrorMessage)
            }

            sqlite3_bind_text(stmt, 1, (eventType as NSString).utf8String, -1, nil)
        } else {
            let sql = "SELECT id, session_id, event_type, timestamp, raw_json FROM events ORDER BY timestamp DESC"

            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw DatabaseError.prepareFailed(lastErrorMessage)
            }
        }

        var events: [SessionEvent] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            events.append(eventFromRow(stmt))
        }
        return events
    }

    /// Deletes events for a given session.
    func deleteEvents(forSessionId sessionId: String) throws {
        let sql = "DELETE FROM events WHERE session_id = ?"

        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }

        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed(lastErrorMessage)
        }

        sqlite3_bind_text(stmt, 1, (sessionId as NSString).utf8String, -1, nil)

        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw DatabaseError.executionFailed(lastErrorMessage)
        }
    }

    private func eventFromRow(_ stmt: OpaquePointer?) -> SessionEvent {
        SessionEvent(
            id: Int(sqlite3_column_int64(stmt, 0)),
            sessionId: String(cString: sqlite3_column_text(stmt, 1)),
            eventType: String(cString: sqlite3_column_text(stmt, 2)),
            timestamp: String(cString: sqlite3_column_text(stmt, 3)),
            rawJson: String(cString: sqlite3_column_text(stmt, 4))
        )
    }

    // MARK: - Settings CRUD

    /// Gets a setting value by key.
    func getSetting(key: String) throws -> String? {
        let sql = "SELECT value FROM settings WHERE key = ?"

        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }

        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed(lastErrorMessage)
        }

        sqlite3_bind_text(stmt, 1, (key as NSString).utf8String, -1, nil)

        guard sqlite3_step(stmt) == SQLITE_ROW else {
            return nil
        }

        return String(cString: sqlite3_column_text(stmt, 0))
    }

    /// Sets a setting value (insert or update).
    func setSetting(key: String, value: String) throws {
        let sql = """
            INSERT INTO settings (key, value) VALUES (?, ?)
            ON CONFLICT(key) DO UPDATE SET value = excluded.value
        """

        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }

        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed(lastErrorMessage)
        }

        sqlite3_bind_text(stmt, 1, (key as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 2, (value as NSString).utf8String, -1, nil)

        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw DatabaseError.executionFailed(lastErrorMessage)
        }
    }

    /// Deletes a setting by key.
    func deleteSetting(key: String) throws {
        let sql = "DELETE FROM settings WHERE key = ?"

        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }

        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed(lastErrorMessage)
        }

        sqlite3_bind_text(stmt, 1, (key as NSString).utf8String, -1, nil)

        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw DatabaseError.executionFailed(lastErrorMessage)
        }
    }

    /// Fetches all settings as a dictionary.
    func fetchAllSettings() throws -> [String: String] {
        let sql = "SELECT key, value FROM settings ORDER BY key"

        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }

        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed(lastErrorMessage)
        }

        var settings: [String: String] = [:]
        while sqlite3_step(stmt) == SQLITE_ROW {
            let key = String(cString: sqlite3_column_text(stmt, 0))
            let value = String(cString: sqlite3_column_text(stmt, 1))
            settings[key] = value
        }
        return settings
    }

    // MARK: - Schema Inspection (for testing)

    /// Returns the names of all tables in the database.
    func tableNames() throws -> [String] {
        let sql = "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name"

        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }

        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed(lastErrorMessage)
        }

        var names: [String] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            names.append(String(cString: sqlite3_column_text(stmt, 0)))
        }
        return names
    }

    /// Returns column info for a given table.
    func columnInfo(forTable table: String) throws -> [(name: String, type: String, notNull: Bool)] {
        // Validate table name: only allow alphanumeric and underscore to prevent injection
        guard table.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" }) else {
            throw DatabaseError.prepareFailed("Invalid table name: \(table)")
        }
        let sql = "PRAGMA table_info(\(table))"

        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }

        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed(lastErrorMessage)
        }

        var columns: [(name: String, type: String, notNull: Bool)] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let name = String(cString: sqlite3_column_text(stmt, 1))
            let type = String(cString: sqlite3_column_text(stmt, 2))
            let notNull = sqlite3_column_int(stmt, 3) != 0
            columns.append((name: name, type: type, notNull: notNull))
        }
        return columns
    }
}
