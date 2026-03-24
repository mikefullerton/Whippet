import XCTest
@testable import Whippet

final class EventIngestionManagerTests: XCTestCase {

    private var dbManager: DatabaseManager!
    private var ingestionManager: EventIngestionManager!
    private var tempDir: URL!
    private var dropDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("whippet-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let dbPath = tempDir.appendingPathComponent("test.db").path
        dbManager = try DatabaseManager(path: dbPath)

        dropDir = tempDir.appendingPathComponent("session-events")
        try FileManager.default.createDirectory(at: dropDir, withIntermediateDirectories: true)

        ingestionManager = EventIngestionManager(
            dropDirectoryURL: dropDir,
            databaseManager: dbManager
        )
    }

    override func tearDownWithError() throws {
        ingestionManager.stop()
        ingestionManager = nil
        dbManager.close()
        dbManager = nil
        try? FileManager.default.removeItem(at: tempDir)
    }

    // MARK: - Helper Methods

    /// Creates a JSON event file in the drop directory.
    @discardableResult
    private func createEventFile(
        event: String,
        sessionId: String,
        timestamp: String = "2026-03-24T10:00:00Z",
        data: [String: Any] = [:],
        fileName: String? = nil
    ) throws -> URL {
        var json: [String: Any] = [
            "event": event,
            "session_id": sessionId,
            "timestamp": timestamp
        ]
        if !data.isEmpty {
            json["data"] = data
        }

        let jsonData = try JSONSerialization.data(withJSONObject: json, options: [.sortedKeys])
        let name = fileName ?? "\(timestamp)-\(UUID().uuidString).json"
        let fileURL = dropDir.appendingPathComponent(name)
        try jsonData.write(to: fileURL)
        return fileURL
    }

    /// Creates a malformed (non-JSON) file in the drop directory.
    @discardableResult
    private func createMalformedFile(fileName: String? = nil) throws -> URL {
        let name = fileName ?? "malformed-\(UUID().uuidString).json"
        let fileURL = dropDir.appendingPathComponent(name)
        try "this is not json {{{".write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL
    }

    // MARK: - Directory Setup Tests

    func testEnsureDirectoriesExist() throws {
        // Use a fresh directory that doesn't exist yet
        let freshDropDir = tempDir.appendingPathComponent("new-events")
        let manager = EventIngestionManager(
            dropDirectoryURL: freshDropDir,
            databaseManager: dbManager
        )

        try manager.ensureDirectoriesExist()

        let fm = FileManager.default
        XCTAssertTrue(fm.fileExists(atPath: freshDropDir.path), "Drop directory should be created")
        XCTAssertTrue(
            fm.fileExists(atPath: freshDropDir.appendingPathComponent("errors").path),
            "Errors subdirectory should be created"
        )
    }

    func testEnsureDirectoriesExistWhenAlreadyPresent() throws {
        // Directories already exist from setUp
        try ingestionManager.ensureDirectoriesExist()
        // Should not throw
        XCTAssertTrue(FileManager.default.fileExists(atPath: dropDir.path))
    }

    // MARK: - JSON Parsing Tests

    func testParseSessionStartEvent() throws {
        let json: [String: Any] = [
            "event": "SessionStart",
            "session_id": "sess-001",
            "timestamp": "2026-03-24T10:00:00Z",
            "data": [
                "cwd": "/Users/test/projects/myapp",
                "model": "claude-sonnet-4-20250514"
            ]
        ]
        let data = try JSONSerialization.data(withJSONObject: json)

        let eventFile = ingestionManager.parseEventFile(data: data, fileName: "test.json")

        XCTAssertNotNil(eventFile)
        XCTAssertEqual(eventFile?.event, "SessionStart")
        XCTAssertEqual(eventFile?.sessionId, "sess-001")
        XCTAssertEqual(eventFile?.timestamp, "2026-03-24T10:00:00Z")
        XCTAssertEqual(eventFile?.data["cwd"] as? String, "/Users/test/projects/myapp")
        XCTAssertEqual(eventFile?.data["model"] as? String, "claude-sonnet-4-20250514")
    }

    func testParseSessionEndEvent() throws {
        let json: [String: Any] = [
            "event": "SessionEnd",
            "session_id": "sess-001",
            "timestamp": "2026-03-24T11:00:00Z",
            "data": [:]
        ]
        let data = try JSONSerialization.data(withJSONObject: json)

        let eventFile = ingestionManager.parseEventFile(data: data, fileName: "test.json")

        XCTAssertNotNil(eventFile)
        XCTAssertEqual(eventFile?.event, "SessionEnd")
        XCTAssertEqual(eventFile?.sessionId, "sess-001")
    }

    func testParsePreToolUseEvent() throws {
        let json: [String: Any] = [
            "event": "PreToolUse",
            "session_id": "sess-002",
            "timestamp": "2026-03-24T10:05:00Z",
            "data": [
                "tool": "Read"
            ]
        ]
        let data = try JSONSerialization.data(withJSONObject: json)

        let eventFile = ingestionManager.parseEventFile(data: data, fileName: "test.json")

        XCTAssertNotNil(eventFile)
        XCTAssertEqual(eventFile?.event, "PreToolUse")
        XCTAssertEqual(eventFile?.data["tool"] as? String, "Read")
    }

    func testParsePostToolUseEvent() throws {
        let json: [String: Any] = [
            "event": "PostToolUse",
            "session_id": "sess-002",
            "timestamp": "2026-03-24T10:05:01Z",
            "data": [
                "tool": "Edit"
            ]
        ]
        let data = try JSONSerialization.data(withJSONObject: json)

        let eventFile = ingestionManager.parseEventFile(data: data, fileName: "test.json")

        XCTAssertNotNil(eventFile)
        XCTAssertEqual(eventFile?.event, "PostToolUse")
        XCTAssertEqual(eventFile?.data["tool"] as? String, "Edit")
    }

    func testParseUserPromptSubmitEvent() throws {
        let json: [String: Any] = [
            "event": "UserPromptSubmit",
            "session_id": "sess-003",
            "timestamp": "2026-03-24T10:00:00Z",
            "data": [:]
        ]
        let data = try JSONSerialization.data(withJSONObject: json)

        let eventFile = ingestionManager.parseEventFile(data: data, fileName: "test.json")

        XCTAssertNotNil(eventFile)
        XCTAssertEqual(eventFile?.event, "UserPromptSubmit")
    }

    func testParseStopEvent() throws {
        let json: [String: Any] = [
            "event": "Stop",
            "session_id": "sess-003",
            "timestamp": "2026-03-24T10:30:00Z",
            "data": [:]
        ]
        let data = try JSONSerialization.data(withJSONObject: json)

        let eventFile = ingestionManager.parseEventFile(data: data, fileName: "test.json")

        XCTAssertNotNil(eventFile)
        XCTAssertEqual(eventFile?.event, "Stop")
    }

    func testParseNotificationEvent() throws {
        let json: [String: Any] = [
            "event": "Notification",
            "session_id": "sess-003",
            "timestamp": "2026-03-24T10:30:00Z",
            "data": [
                "message": "Task complete"
            ]
        ]
        let data = try JSONSerialization.data(withJSONObject: json)

        let eventFile = ingestionManager.parseEventFile(data: data, fileName: "test.json")

        XCTAssertNotNil(eventFile)
        XCTAssertEqual(eventFile?.event, "Notification")
        XCTAssertEqual(eventFile?.data["message"] as? String, "Task complete")
    }

    func testParseMalformedJsonReturnsNil() {
        let data = "this is not json".data(using: .utf8)!
        let eventFile = ingestionManager.parseEventFile(data: data, fileName: "bad.json")
        XCTAssertNil(eventFile)
    }

    func testParseMissingEventFieldReturnsNil() throws {
        let json: [String: Any] = [
            "session_id": "sess-001",
            "timestamp": "2026-03-24T10:00:00Z"
        ]
        let data = try JSONSerialization.data(withJSONObject: json)

        let eventFile = ingestionManager.parseEventFile(data: data, fileName: "test.json")
        XCTAssertNil(eventFile)
    }

    func testParseMissingSessionIdReturnsNil() throws {
        let json: [String: Any] = [
            "event": "SessionStart",
            "timestamp": "2026-03-24T10:00:00Z"
        ]
        let data = try JSONSerialization.data(withJSONObject: json)

        let eventFile = ingestionManager.parseEventFile(data: data, fileName: "test.json")
        XCTAssertNil(eventFile)
    }

    func testParseMinimalValidJson() throws {
        // Only required fields: event and session_id
        let json: [String: Any] = [
            "event": "SessionStart",
            "session_id": "sess-minimal"
        ]
        let data = try JSONSerialization.data(withJSONObject: json)

        let eventFile = ingestionManager.parseEventFile(data: data, fileName: "test.json")

        XCTAssertNotNil(eventFile)
        XCTAssertEqual(eventFile?.event, "SessionStart")
        XCTAssertEqual(eventFile?.sessionId, "sess-minimal")
        // Timestamp should be auto-generated
        XCTAssertFalse(eventFile?.timestamp.isEmpty ?? true)
        // Data should be empty dict
        XCTAssertTrue(eventFile?.data.isEmpty ?? false)
    }

    func testParseMissingDataFieldDefaultsToEmptyDict() throws {
        let json: [String: Any] = [
            "event": "SessionStart",
            "session_id": "sess-001",
            "timestamp": "2026-03-24T10:00:00Z"
        ]
        let data = try JSONSerialization.data(withJSONObject: json)

        let eventFile = ingestionManager.parseEventFile(data: data, fileName: "test.json")

        XCTAssertNotNil(eventFile)
        XCTAssertTrue(eventFile?.data.isEmpty ?? false)
    }

    // MARK: - Event Ingestion Tests

    func testIngestSessionStartCreatesSession() throws {
        let eventFile = EventFile(
            event: "SessionStart",
            sessionId: "sess-ingest-001",
            timestamp: "2026-03-24T10:00:00Z",
            data: [
                "cwd": "/Users/test/projects/app",
                "model": "claude-sonnet-4-20250514"
            ],
            rawJson: "{}"
        )

        try ingestionManager.ingestEvent(eventFile, rawData: "{}".data(using: .utf8)!)

        let session = try dbManager.fetchSession(bySessionId: "sess-ingest-001")
        XCTAssertNotNil(session)
        XCTAssertEqual(session?.cwd, "/Users/test/projects/app")
        XCTAssertEqual(session?.model, "claude-sonnet-4-20250514")
        XCTAssertEqual(session?.status, .active)

        let events = try dbManager.fetchEvents(forSessionId: "sess-ingest-001")
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.eventType, "SessionStart")
    }

    func testIngestSessionEndMarksSessionEnded() throws {
        // First create the session
        let startEvent = EventFile(
            event: "SessionStart",
            sessionId: "sess-end-001",
            timestamp: "2026-03-24T10:00:00Z",
            data: ["cwd": "/Users/test/app"],
            rawJson: "{}"
        )
        try ingestionManager.ingestEvent(startEvent, rawData: "{}".data(using: .utf8)!)

        // Then end it
        let endEvent = EventFile(
            event: "SessionEnd",
            sessionId: "sess-end-001",
            timestamp: "2026-03-24T11:00:00Z",
            data: [:],
            rawJson: "{}"
        )
        try ingestionManager.ingestEvent(endEvent, rawData: "{}".data(using: .utf8)!)

        let session = try dbManager.fetchSession(bySessionId: "sess-end-001")
        XCTAssertEqual(session?.status, .ended)

        let events = try dbManager.fetchEvents(forSessionId: "sess-end-001")
        XCTAssertEqual(events.count, 2)
    }

    func testIngestToolUseUpdatesLastTool() throws {
        // Create session
        let startEvent = EventFile(
            event: "SessionStart",
            sessionId: "sess-tool-001",
            timestamp: "2026-03-24T10:00:00Z",
            data: ["cwd": "/Users/test/app"],
            rawJson: "{}"
        )
        try ingestionManager.ingestEvent(startEvent, rawData: "{}".data(using: .utf8)!)

        // Tool use event
        let toolEvent = EventFile(
            event: "PostToolUse",
            sessionId: "sess-tool-001",
            timestamp: "2026-03-24T10:05:00Z",
            data: ["tool": "Edit"],
            rawJson: "{}"
        )
        try ingestionManager.ingestEvent(toolEvent, rawData: "{}".data(using: .utf8)!)

        let session = try dbManager.fetchSession(bySessionId: "sess-tool-001")
        XCTAssertEqual(session?.lastTool, "Edit")
        XCTAssertEqual(session?.lastActivityAt, "2026-03-24T10:05:00Z")
    }

    func testIngestMultipleEventsForSameSession() throws {
        let events = [
            ("SessionStart", "2026-03-24T10:00:00Z", ["cwd": "/test", "model": "claude-sonnet-4-20250514"] as [String: Any]),
            ("PreToolUse", "2026-03-24T10:01:00Z", ["tool": "Read"] as [String: Any]),
            ("PostToolUse", "2026-03-24T10:01:01Z", ["tool": "Read"] as [String: Any]),
            ("PreToolUse", "2026-03-24T10:02:00Z", ["tool": "Edit"] as [String: Any]),
            ("PostToolUse", "2026-03-24T10:02:01Z", ["tool": "Edit"] as [String: Any]),
        ]

        for (eventType, timestamp, data) in events {
            let ef = EventFile(
                event: eventType,
                sessionId: "sess-multi-001",
                timestamp: timestamp,
                data: data,
                rawJson: "{}"
            )
            try ingestionManager.ingestEvent(ef, rawData: "{}".data(using: .utf8)!)
        }

        let session = try dbManager.fetchSession(bySessionId: "sess-multi-001")
        XCTAssertNotNil(session)
        XCTAssertEqual(session?.lastTool, "Edit")
        XCTAssertEqual(session?.lastActivityAt, "2026-03-24T10:02:01Z")

        let dbEvents = try dbManager.fetchEvents(forSessionId: "sess-multi-001")
        XCTAssertEqual(dbEvents.count, 5)
    }

    // MARK: - File Processing Integration Tests

    func testProcessFileInsertsEventAndDeletesFile() throws {
        let fileURL = try createEventFile(
            event: "SessionStart",
            sessionId: "sess-file-001",
            data: ["cwd": "/Users/test/app", "model": "claude-sonnet-4-20250514"]
        )

        // Wait briefly for file to age past minimumFileAge
        Thread.sleep(forTimeInterval: EventIngestionManager.minimumFileAge + 0.05)

        ingestionManager.processFile(at: fileURL)

        // Verify event is in database
        let events = try dbManager.fetchEvents(forSessionId: "sess-file-001")
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.eventType, "SessionStart")

        // Verify session was created
        let session = try dbManager.fetchSession(bySessionId: "sess-file-001")
        XCTAssertNotNil(session)
        XCTAssertEqual(session?.cwd, "/Users/test/app")

        // Verify file was deleted
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
    }

    func testProcessMalformedFileMovesToErrors() throws {
        let fileURL = try createMalformedFile(fileName: "bad-event.json")

        // Wait briefly for file to age
        Thread.sleep(forTimeInterval: EventIngestionManager.minimumFileAge + 0.05)

        ingestionManager.processFile(at: fileURL)

        // File should be moved to errors/
        let errorFile = ingestionManager.errorsDirectoryURL.appendingPathComponent("bad-event.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: errorFile.path))

        // Original should be gone
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
    }

    func testProcessExistingFilesProcessesAllJsonFiles() throws {
        // Create multiple event files
        try createEventFile(
            event: "SessionStart",
            sessionId: "sess-batch-001",
            timestamp: "2026-03-24T10:00:00Z",
            data: ["cwd": "/app1"],
            fileName: "001-start.json"
        )
        try createEventFile(
            event: "SessionStart",
            sessionId: "sess-batch-002",
            timestamp: "2026-03-24T10:01:00Z",
            data: ["cwd": "/app2"],
            fileName: "002-start.json"
        )
        try createEventFile(
            event: "PreToolUse",
            sessionId: "sess-batch-001",
            timestamp: "2026-03-24T10:02:00Z",
            data: ["tool": "Read"],
            fileName: "003-tool.json"
        )

        // Wait briefly for files to age
        Thread.sleep(forTimeInterval: EventIngestionManager.minimumFileAge + 0.05)

        ingestionManager.processExistingFiles()

        // Verify all sessions created
        let session1 = try dbManager.fetchSession(bySessionId: "sess-batch-001")
        XCTAssertNotNil(session1)
        let session2 = try dbManager.fetchSession(bySessionId: "sess-batch-002")
        XCTAssertNotNil(session2)

        // Verify all events ingested
        let events1 = try dbManager.fetchEvents(forSessionId: "sess-batch-001")
        XCTAssertEqual(events1.count, 2)
        let events2 = try dbManager.fetchEvents(forSessionId: "sess-batch-002")
        XCTAssertEqual(events2.count, 1)

        // Verify all files deleted
        let remaining = try FileManager.default.contentsOfDirectory(
            at: dropDir,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
        ).filter { $0.pathExtension == "json" }
        XCTAssertEqual(remaining.count, 0)
    }

    func testNonJsonFilesAreIgnored() throws {
        // Create a non-JSON file
        let textFile = dropDir.appendingPathComponent("readme.txt")
        try "not a json file".write(to: textFile, atomically: true, encoding: .utf8)

        // Create a valid JSON event file
        try createEventFile(
            event: "SessionStart",
            sessionId: "sess-ignore-001",
            fileName: "event.json"
        )

        Thread.sleep(forTimeInterval: EventIngestionManager.minimumFileAge + 0.05)

        ingestionManager.processExistingFiles()

        // The text file should still be there
        XCTAssertTrue(FileManager.default.fileExists(atPath: textFile.path))

        // The JSON event should have been processed
        let session = try dbManager.fetchSession(bySessionId: "sess-ignore-001")
        XCTAssertNotNil(session)
    }

    // MARK: - Stress Test

    func testRapidFileIngestion() throws {
        // Drop 50 files rapidly
        let fileCount = 50
        for i in 0..<fileCount {
            let timestamp = String(format: "2026-03-24T10:%02d:00Z", i)
            let sessionId = "sess-stress-\(i % 5)" // 5 different sessions
            let eventType = i % 5 == 0 ? "SessionStart" : "PreToolUse"
            let data: [String: Any] = i % 5 == 0
                ? ["cwd": "/project-\(i % 5)", "model": "claude-sonnet-4-20250514"]
                : ["tool": "Tool-\(i)"]

            try createEventFile(
                event: eventType,
                sessionId: sessionId,
                timestamp: timestamp,
                data: data,
                fileName: String(format: "%03d-event.json", i)
            )
        }

        // Wait for files to age
        Thread.sleep(forTimeInterval: EventIngestionManager.minimumFileAge + 0.05)

        // Process all at once
        ingestionManager.processExistingFiles()

        // Verify all events were consumed
        let allEvents = try dbManager.fetchAllEvents()
        XCTAssertEqual(allEvents.count, fileCount, "All \(fileCount) events should be ingested")

        // Verify all sessions exist (5 unique sessions)
        let allSessions = try dbManager.fetchAllSessions()
        XCTAssertEqual(allSessions.count, 5, "5 unique sessions should exist")

        // Verify all files are deleted
        let remainingFiles = try FileManager.default.contentsOfDirectory(
            at: dropDir,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
        ).filter { $0.pathExtension == "json" }
        XCTAssertEqual(remainingFiles.count, 0, "All files should be deleted after ingestion")
    }

    // MARK: - File Watcher Integration Test

    func testStartCreatesDirectoriesAndProcessesExistingFiles() throws {
        // Create fresh manager with new directory
        let freshDropDir = tempDir.appendingPathComponent("watch-test")
        try FileManager.default.createDirectory(at: freshDropDir, withIntermediateDirectories: true)

        let manager = EventIngestionManager(
            dropDirectoryURL: freshDropDir,
            databaseManager: dbManager
        )

        // Put a file in before starting
        let json: [String: Any] = [
            "event": "SessionStart",
            "session_id": "sess-watch-001",
            "timestamp": "2026-03-24T10:00:00Z",
            "data": ["cwd": "/app"]
        ]
        let data = try JSONSerialization.data(withJSONObject: json)
        let fileURL = freshDropDir.appendingPathComponent("pre-existing.json")
        try data.write(to: fileURL)

        Thread.sleep(forTimeInterval: EventIngestionManager.minimumFileAge + 0.05)

        try manager.start()

        // The pre-existing file should have been processed
        let session = try dbManager.fetchSession(bySessionId: "sess-watch-001")
        XCTAssertNotNil(session)

        XCTAssertTrue(manager.isRunning)

        manager.stop()
        XCTAssertFalse(manager.isRunning)
    }

    func testFileWatcherDetectsNewFiles() throws {
        try ingestionManager.start()

        let expectation = XCTestExpectation(description: "Event ingested callback")
        ingestionManager.onEventsIngested = {
            expectation.fulfill()
        }

        // Wait a moment then drop a file
        Thread.sleep(forTimeInterval: 0.2)

        let json: [String: Any] = [
            "event": "SessionStart",
            "session_id": "sess-dynamic-001",
            "timestamp": "2026-03-24T12:00:00Z",
            "data": ["cwd": "/dynamic-app"]
        ]
        let data = try JSONSerialization.data(withJSONObject: json)
        let fileURL = dropDir.appendingPathComponent("dynamic-event.json")
        try data.write(to: fileURL)

        wait(for: [expectation], timeout: 5.0)

        let session = try dbManager.fetchSession(bySessionId: "sess-dynamic-001")
        XCTAssertNotNil(session, "Session should be created from dynamically dropped file")
        XCTAssertEqual(session?.cwd, "/dynamic-app")
    }

    // MARK: - Concurrent Write Handling

    func testEmptyFileIsSkipped() throws {
        // Create an empty file (simulating a file still being written)
        let fileURL = dropDir.appendingPathComponent("empty.json")
        try "".write(to: fileURL, atomically: true, encoding: .utf8)

        Thread.sleep(forTimeInterval: EventIngestionManager.minimumFileAge + 0.05)

        ingestionManager.processFile(at: fileURL)

        // File should still exist (not deleted, not moved to errors)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))

        // No events should be in the database
        let allEvents = try dbManager.fetchAllEvents()
        XCTAssertEqual(allEvents.count, 0)
    }

    // MARK: - EventType Enum Tests

    func testEventTypeRawValues() {
        XCTAssertEqual(EventType.sessionStart.rawValue, "SessionStart")
        XCTAssertEqual(EventType.sessionEnd.rawValue, "SessionEnd")
        XCTAssertEqual(EventType.userPromptSubmit.rawValue, "UserPromptSubmit")
        XCTAssertEqual(EventType.preToolUse.rawValue, "PreToolUse")
        XCTAssertEqual(EventType.postToolUse.rawValue, "PostToolUse")
        XCTAssertEqual(EventType.stop.rawValue, "Stop")
        XCTAssertEqual(EventType.subagentStart.rawValue, "SubagentStart")
        XCTAssertEqual(EventType.subagentStop.rawValue, "SubagentStop")
        XCTAssertEqual(EventType.notification.rawValue, "Notification")
    }

    func testAllEventTypesCovered() {
        XCTAssertEqual(EventType.allCases.count, 9, "All 9 hook event types should be enumerated")
    }

    // MARK: - Edge Cases

    func testMissingDataFieldInJson() throws {
        let fileURL = try createEventFile(
            event: "SessionStart",
            sessionId: "sess-nodata-001",
            timestamp: "2026-03-24T10:00:00Z"
        )

        Thread.sleep(forTimeInterval: EventIngestionManager.minimumFileAge + 0.05)

        ingestionManager.processFile(at: fileURL)

        let session = try dbManager.fetchSession(bySessionId: "sess-nodata-001")
        XCTAssertNotNil(session, "Session should be created even without data field")
        XCTAssertEqual(session?.cwd, "")
        XCTAssertEqual(session?.model, "")
    }

    func testJsonArrayIsRejected() throws {
        let fileURL = dropDir.appendingPathComponent("array.json")
        let data = try JSONSerialization.data(withJSONObject: ["not", "a", "dict"])
        try data.write(to: fileURL)

        Thread.sleep(forTimeInterval: EventIngestionManager.minimumFileAge + 0.05)

        ingestionManager.processFile(at: fileURL)

        // Should be moved to errors
        let errorFile = ingestionManager.errorsDirectoryURL.appendingPathComponent("array.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: errorFile.path))
    }
}
