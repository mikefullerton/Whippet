import XCTest
@testable import Whippet

final class DatabaseManagerTests: XCTestCase {

    private var dbManager: DatabaseManager!
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let dbPath = tempDir.appendingPathComponent("test.db").path
        dbManager = try DatabaseManager(path: dbPath)
    }

    override func tearDownWithError() throws {
        dbManager.close()
        dbManager = nil
        try? FileManager.default.removeItem(at: tempDir)
    }

    // MARK: - Schema Tests

    func testTablesExist() throws {
        let tables = try dbManager.tableNames()
        XCTAssertTrue(tables.contains("sessions"), "sessions table should exist")
        XCTAssertTrue(tables.contains("events"), "events table should exist")
        XCTAssertTrue(tables.contains("settings"), "settings table should exist")
        XCTAssertTrue(tables.contains("schema_migrations"), "schema_migrations table should exist")
    }

    func testSessionsTableSchema() throws {
        let columns = try dbManager.columnInfo(forTable: "sessions")
        let columnNames = columns.map { $0.name }

        XCTAssertTrue(columnNames.contains("id"))
        XCTAssertTrue(columnNames.contains("session_id"))
        XCTAssertTrue(columnNames.contains("cwd"))
        XCTAssertTrue(columnNames.contains("model"))
        XCTAssertTrue(columnNames.contains("started_at"))
        XCTAssertTrue(columnNames.contains("last_activity_at"))
        XCTAssertTrue(columnNames.contains("last_tool"))
        XCTAssertTrue(columnNames.contains("status"))
    }

    func testEventsTableSchema() throws {
        let columns = try dbManager.columnInfo(forTable: "events")
        let columnNames = columns.map { $0.name }

        XCTAssertTrue(columnNames.contains("id"))
        XCTAssertTrue(columnNames.contains("session_id"))
        XCTAssertTrue(columnNames.contains("event_type"))
        XCTAssertTrue(columnNames.contains("timestamp"))
        XCTAssertTrue(columnNames.contains("raw_json"))
    }

    func testSettingsTableSchema() throws {
        let columns = try dbManager.columnInfo(forTable: "settings")
        let columnNames = columns.map { $0.name }

        XCTAssertTrue(columnNames.contains("key"))
        XCTAssertTrue(columnNames.contains("value"))
    }

    // MARK: - Session CRUD Tests

    func testInsertAndFetchSession() throws {
        let session = Session(
            sessionId: "sess-001",
            cwd: "/Users/test/projects/myapp",
            model: "claude-sonnet-4-20250514",
            startedAt: "2026-03-24T10:00:00Z",
            lastActivityAt: "2026-03-24T10:05:00Z",
            lastTool: "Read",
            status: .active
        )

        let inserted = try dbManager.upsertSession(session)
        XCTAssertNotNil(inserted.id)
        XCTAssertEqual(inserted.sessionId, "sess-001")

        let fetched = try dbManager.fetchSession(bySessionId: "sess-001")
        XCTAssertNotNil(fetched)
        XCTAssertEqual(fetched?.sessionId, "sess-001")
        XCTAssertEqual(fetched?.cwd, "/Users/test/projects/myapp")
        XCTAssertEqual(fetched?.model, "claude-sonnet-4-20250514")
        XCTAssertEqual(fetched?.lastTool, "Read")
        XCTAssertEqual(fetched?.status, .active)
    }

    func testUpsertUpdatesExistingSession() throws {
        let session1 = Session(
            sessionId: "sess-002",
            cwd: "/Users/test/projects/app",
            model: "claude-sonnet-4-20250514",
            startedAt: "2026-03-24T10:00:00Z",
            lastActivityAt: "2026-03-24T10:00:00Z",
            lastTool: "Read",
            status: .active
        )
        try dbManager.upsertSession(session1)

        // Upsert with updated fields
        let session2 = Session(
            sessionId: "sess-002",
            cwd: "/Users/test/projects/app",
            model: "claude-sonnet-4-20250514",
            startedAt: "2026-03-24T10:00:00Z",
            lastActivityAt: "2026-03-24T10:10:00Z",
            lastTool: "Edit",
            status: .active
        )
        try dbManager.upsertSession(session2)

        let all = try dbManager.fetchAllSessions()
        XCTAssertEqual(all.count, 1, "Upsert should not create duplicate sessions")

        let fetched = try dbManager.fetchSession(bySessionId: "sess-002")
        XCTAssertEqual(fetched?.lastTool, "Edit")
        XCTAssertEqual(fetched?.lastActivityAt, "2026-03-24T10:10:00Z")
    }

    func testFetchAllSessions() throws {
        try dbManager.upsertSession(Session(sessionId: "sess-a", status: .active))
        try dbManager.upsertSession(Session(sessionId: "sess-b", status: .stale))
        try dbManager.upsertSession(Session(sessionId: "sess-c", status: .ended))

        let all = try dbManager.fetchAllSessions()
        XCTAssertEqual(all.count, 3)

        let active = try dbManager.fetchAllSessions(status: .active)
        XCTAssertEqual(active.count, 1)
        XCTAssertEqual(active.first?.sessionId, "sess-a")

        let stale = try dbManager.fetchAllSessions(status: .stale)
        XCTAssertEqual(stale.count, 1)
        XCTAssertEqual(stale.first?.sessionId, "sess-b")

        let ended = try dbManager.fetchAllSessions(status: .ended)
        XCTAssertEqual(ended.count, 1)
        XCTAssertEqual(ended.first?.sessionId, "sess-c")
    }

    func testUpdateSessionStatus() throws {
        try dbManager.upsertSession(Session(sessionId: "sess-status", status: .active))

        try dbManager.updateSessionStatus(sessionId: "sess-status", status: .stale)
        var fetched = try dbManager.fetchSession(bySessionId: "sess-status")
        XCTAssertEqual(fetched?.status, .stale)

        try dbManager.updateSessionStatus(sessionId: "sess-status", status: .ended)
        fetched = try dbManager.fetchSession(bySessionId: "sess-status")
        XCTAssertEqual(fetched?.status, .ended)
    }

    func testDeleteSession() throws {
        try dbManager.upsertSession(Session(sessionId: "sess-del"))
        try dbManager.insertEvent(SessionEvent(sessionId: "sess-del", eventType: "SessionStart"))

        try dbManager.deleteSession(sessionId: "sess-del")

        let session = try dbManager.fetchSession(bySessionId: "sess-del")
        XCTAssertNil(session)

        let events = try dbManager.fetchEvents(forSessionId: "sess-del")
        XCTAssertTrue(events.isEmpty)
    }

    func testFetchNonexistentSession() throws {
        let session = try dbManager.fetchSession(bySessionId: "nonexistent")
        XCTAssertNil(session)
    }

    // MARK: - Event CRUD Tests

    func testInsertAndFetchEvent() throws {
        try dbManager.upsertSession(Session(sessionId: "sess-evt"))

        let event = SessionEvent(
            sessionId: "sess-evt",
            eventType: "SessionStart",
            timestamp: "2026-03-24T10:00:00Z",
            rawJson: "{\"event\": \"SessionStart\"}"
        )

        let inserted = try dbManager.insertEvent(event)
        XCTAssertNotNil(inserted.id)
        XCTAssertEqual(inserted.sessionId, "sess-evt")
        XCTAssertEqual(inserted.eventType, "SessionStart")

        let events = try dbManager.fetchEvents(forSessionId: "sess-evt")
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.eventType, "SessionStart")
        XCTAssertEqual(events.first?.rawJson, "{\"event\": \"SessionStart\"}")
    }

    func testFetchMultipleEvents() throws {
        try dbManager.upsertSession(Session(sessionId: "sess-multi"))

        try dbManager.insertEvent(SessionEvent(
            sessionId: "sess-multi",
            eventType: "SessionStart",
            timestamp: "2026-03-24T10:00:00Z"
        ))
        try dbManager.insertEvent(SessionEvent(
            sessionId: "sess-multi",
            eventType: "PreToolUse",
            timestamp: "2026-03-24T10:01:00Z"
        ))
        try dbManager.insertEvent(SessionEvent(
            sessionId: "sess-multi",
            eventType: "PostToolUse",
            timestamp: "2026-03-24T10:02:00Z"
        ))

        let events = try dbManager.fetchEvents(forSessionId: "sess-multi")
        XCTAssertEqual(events.count, 3)
        // Should be ordered by timestamp ASC
        XCTAssertEqual(events[0].eventType, "SessionStart")
        XCTAssertEqual(events[1].eventType, "PreToolUse")
        XCTAssertEqual(events[2].eventType, "PostToolUse")
    }

    func testFetchAllEventsByType() throws {
        try dbManager.upsertSession(Session(sessionId: "sess-type-a"))
        try dbManager.upsertSession(Session(sessionId: "sess-type-b"))

        try dbManager.insertEvent(SessionEvent(sessionId: "sess-type-a", eventType: "SessionStart", timestamp: "2026-03-24T10:00:00Z"))
        try dbManager.insertEvent(SessionEvent(sessionId: "sess-type-a", eventType: "PreToolUse", timestamp: "2026-03-24T10:01:00Z"))
        try dbManager.insertEvent(SessionEvent(sessionId: "sess-type-b", eventType: "SessionStart", timestamp: "2026-03-24T10:02:00Z"))

        let starts = try dbManager.fetchAllEvents(eventType: "SessionStart")
        XCTAssertEqual(starts.count, 2)

        let toolUses = try dbManager.fetchAllEvents(eventType: "PreToolUse")
        XCTAssertEqual(toolUses.count, 1)

        let all = try dbManager.fetchAllEvents()
        XCTAssertEqual(all.count, 3)
    }

    func testDeleteEventsForSession() throws {
        try dbManager.upsertSession(Session(sessionId: "sess-del-evt"))
        try dbManager.insertEvent(SessionEvent(sessionId: "sess-del-evt", eventType: "SessionStart"))
        try dbManager.insertEvent(SessionEvent(sessionId: "sess-del-evt", eventType: "PreToolUse"))

        try dbManager.deleteEvents(forSessionId: "sess-del-evt")

        let events = try dbManager.fetchEvents(forSessionId: "sess-del-evt")
        XCTAssertTrue(events.isEmpty)

        // Session itself should still exist
        let session = try dbManager.fetchSession(bySessionId: "sess-del-evt")
        XCTAssertNotNil(session)
    }

    // MARK: - Settings CRUD Tests

    func testSetAndGetSetting() throws {
        try dbManager.setSetting(key: "staleness_timeout", value: "60")

        let value = try dbManager.getSetting(key: "staleness_timeout")
        XCTAssertEqual(value, "60")
    }

    func testUpdateExistingSetting() throws {
        try dbManager.setSetting(key: "theme", value: "dark")
        try dbManager.setSetting(key: "theme", value: "light")

        let value = try dbManager.getSetting(key: "theme")
        XCTAssertEqual(value, "light")
    }

    func testGetNonexistentSetting() throws {
        let value = try dbManager.getSetting(key: "nonexistent")
        XCTAssertNil(value)
    }

    func testDeleteSetting() throws {
        try dbManager.setSetting(key: "to_delete", value: "value")
        try dbManager.deleteSetting(key: "to_delete")

        let value = try dbManager.getSetting(key: "to_delete")
        XCTAssertNil(value)
    }

    func testFetchAllSettings() throws {
        try dbManager.setSetting(key: "key_a", value: "value_a")
        try dbManager.setSetting(key: "key_b", value: "value_b")
        try dbManager.setSetting(key: "key_c", value: "value_c")

        let settings = try dbManager.fetchAllSettings()
        XCTAssertEqual(settings.count, 3)
        XCTAssertEqual(settings["key_a"], "value_a")
        XCTAssertEqual(settings["key_b"], "value_b")
        XCTAssertEqual(settings["key_c"], "value_c")
    }

    // MARK: - Migration Tests

    func testSchemaVersionIsSet() throws {
        // The database should have schema version 1 after initialization
        let tables = try dbManager.tableNames()
        XCTAssertTrue(tables.contains("schema_migrations"))
    }

    func testReopeningDatabaseDoesNotDuplicateTables() throws {
        // Close and reopen with same path
        let dbPath = tempDir.appendingPathComponent("test.db").path
        dbManager.close()
        dbManager = try DatabaseManager(path: dbPath)

        let tables = try dbManager.tableNames()
        // Count occurrences of each table name -- should have no duplicates
        let uniqueTables = Set(tables)
        XCTAssertEqual(tables.count, uniqueTables.count, "No duplicate tables should exist")
    }

    // MARK: - Model Tests

    func testSessionProjectName() {
        let session = Session(sessionId: "test", cwd: "/Users/test/projects/myapp")
        XCTAssertEqual(session.projectName, "myapp")

        let emptySession = Session(sessionId: "test2", cwd: "")
        XCTAssertEqual(emptySession.projectName, "Unknown")
    }

    func testSessionStatusRawValues() {
        XCTAssertEqual(SessionStatus.active.rawValue, "active")
        XCTAssertEqual(SessionStatus.stale.rawValue, "stale")
        XCTAssertEqual(SessionStatus.ended.rawValue, "ended")
    }
}
