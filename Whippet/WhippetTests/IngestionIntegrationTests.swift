import XCTest
@testable import Whippet

/// Integration tests for the full ingestion pipeline:
/// hook writes JSON file → EventIngestionManager detects → parses → inserts into DB → deletes file.
final class IngestionIntegrationTests: XCTestCase {

    private var tempDir: URL!
    private var errorsDir: URL!
    private var databaseManager: DatabaseManager!
    private var ingestionManager: EventIngestionManager!
    private var tempDBPath: String!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("whippet-ingestion-test-\(UUID().uuidString)")
        errorsDir = tempDir.appendingPathComponent("errors")
        try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        tempDBPath = NSTemporaryDirectory() + "whippet_ingestion_test_\(UUID().uuidString).db"
        databaseManager = try! DatabaseManager(path: tempDBPath)
        ingestionManager = EventIngestionManager(dropDirectoryURL: tempDir, databaseManager: databaseManager)
    }

    override func tearDown() {
        ingestionManager.stop()
        ingestionManager = nil
        databaseManager.close()
        databaseManager = nil
        try? FileManager.default.removeItem(at: tempDir)
        try? FileManager.default.removeItem(atPath: tempDBPath)
        super.tearDown()
    }

    // MARK: - Helpers

    /// Writes a valid event JSON file to the drop directory and returns the file URL.
    @discardableResult
    private func writeEventFile(
        event: String = "PreToolUse",
        sessionId: String = "test-session-001",
        cwd: String = "/tmp/test-project",
        extraData: [String: Any] = [:]
    ) -> URL {
        var data: [String: Any] = ["cwd": cwd]
        for (k, v) in extraData { data[k] = v }

        let payload: [String: Any] = [
            "event": event,
            "session_id": sessionId,
            "timestamp": ISO8601DateFormatter().string(from: Date()),
            "data": data
        ]
        let jsonData = try! JSONSerialization.data(withJSONObject: payload)
        let fileName = "\(Int(Date().timeIntervalSince1970 * 1000))-\(UUID().uuidString.prefix(8)).json"
        let fileURL = tempDir.appendingPathComponent(fileName)
        try! jsonData.write(to: fileURL)
        // Backdate so the file passes the minimumFileAge check
        let past = Date().addingTimeInterval(-2)
        try? FileManager.default.setAttributes([.modificationDate: past], ofItemAtPath: fileURL.path)
        return fileURL
    }

    /// Writes an empty file to the drop directory.
    @discardableResult
    private func writeEmptyFile() -> URL {
        let fileName = "\(Int(Date().timeIntervalSince1970 * 1000))-\(UUID().uuidString.prefix(8)).json"
        let fileURL = tempDir.appendingPathComponent(fileName)
        FileManager.default.createFile(atPath: fileURL.path, contents: Data())
        // Backdate so it passes the age check
        let past = Date().addingTimeInterval(-10)
        try? FileManager.default.setAttributes([.modificationDate: past], ofItemAtPath: fileURL.path)
        return fileURL
    }

    /// Writes a malformed (non-JSON) file to the drop directory.
    @discardableResult
    private func writeMalformedFile() -> URL {
        let fileName = "\(Int(Date().timeIntervalSince1970 * 1000))-\(UUID().uuidString.prefix(8)).json"
        let fileURL = tempDir.appendingPathComponent(fileName)
        try! "this is not json".data(using: .utf8)!.write(to: fileURL)
        let past = Date().addingTimeInterval(-2)
        try? FileManager.default.setAttributes([.modificationDate: past], ofItemAtPath: fileURL.path)
        return fileURL
    }

    private func jsonFileCount() -> Int {
        let contents = try? FileManager.default.contentsOfDirectory(
            at: tempDir, includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
        )
        return contents?.filter { $0.pathExtension == "json" }.count ?? 0
    }

    private func errorsFileCount() -> Int {
        let contents = try? FileManager.default.contentsOfDirectory(
            at: errorsDir, includingPropertiesForKeys: nil
        )
        return contents?.count ?? 0
    }

    // MARK: - Tests

    func testValidFileIsIngestedAndDeleted() throws {
        let fileURL = writeEventFile()
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))

        ingestionManager.processExistingFiles()

        // File should be deleted
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path), "Consumed file should be deleted")

        // Session should exist in DB
        let sessions = try databaseManager.fetchAllSessions()
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions[0].sessionId, "test-session-001")
    }

    func testMultipleFilesAllDeleted() throws {
        for i in 0..<10 {
            writeEventFile(sessionId: "session-\(i)")
        }
        XCTAssertEqual(jsonFileCount(), 10)

        ingestionManager.processExistingFiles()

        XCTAssertEqual(jsonFileCount(), 0, "All files should be deleted after processing")
        let sessions = try databaseManager.fetchAllSessions()
        XCTAssertEqual(sessions.count, 10)
    }

    func testEmptyFileIsDeleted() {
        let fileURL = writeEmptyFile()
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))

        ingestionManager.processExistingFiles()

        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path), "Empty file should be deleted")
    }

    func testMalformedFileMovedToErrors() {
        let fileURL = writeMalformedFile()
        let fileName = fileURL.lastPathComponent

        ingestionManager.processExistingFiles()

        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path), "Malformed file should be removed from drop dir")
        let errorFile = errorsDir.appendingPathComponent(fileName)
        XCTAssertTrue(FileManager.default.fileExists(atPath: errorFile.path), "Malformed file should be in errors dir")
    }

    func testSessionStartCreatesActiveSession() throws {
        writeEventFile(event: "SessionStart", sessionId: "start-test", extraData: ["model": "claude-3.5-sonnet"])

        ingestionManager.processExistingFiles()

        let session = try databaseManager.fetchSession(bySessionId: "start-test")
        XCTAssertNotNil(session)
        XCTAssertEqual(session?.status, .active)
        XCTAssertEqual(session?.model, "claude-3.5-sonnet")
    }

    func testSessionEndMarksSessionEnded() throws {
        writeEventFile(event: "SessionStart", sessionId: "end-test")
        ingestionManager.processExistingFiles()

        writeEventFile(event: "SessionEnd", sessionId: "end-test")
        ingestionManager.processExistingFiles()

        let session = try databaseManager.fetchSession(bySessionId: "end-test")
        XCTAssertEqual(session?.status, .ended)
    }

    func testUserPromptUpdatesSummary() throws {
        writeEventFile(event: "SessionStart", sessionId: "prompt-test")
        ingestionManager.processExistingFiles()

        writeEventFile(event: "UserPromptSubmit", sessionId: "prompt-test", extraData: ["prompt": "fix the login bug"])
        ingestionManager.processExistingFiles()

        let session = try databaseManager.fetchSession(bySessionId: "prompt-test")
        XCTAssertEqual(session?.summary, "fix the login bug")
    }

    func testMixOfValidEmptyAndMalformedFiles() throws {
        writeEventFile(sessionId: "good-1")
        writeEventFile(sessionId: "good-2")
        writeEmptyFile()
        writeEmptyFile()
        writeMalformedFile()

        XCTAssertEqual(jsonFileCount(), 5)

        ingestionManager.processExistingFiles()

        // 2 valid consumed + 2 empty deleted + 1 malformed moved to errors = 0 remaining
        XCTAssertEqual(jsonFileCount(), 0, "All files should be cleaned up")
        XCTAssertEqual(errorsFileCount(), 1, "Malformed file should be in errors")
        let sessions = try databaseManager.fetchAllSessions()
        XCTAssertEqual(sessions.count, 2, "Only valid events should create sessions")
    }

    func testFileWatcherDetectsNewFiles() throws {
        try ingestionManager.start()

        let expectation = expectation(description: "File processed")

        // Write a file after the watcher is running
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) {
            self.writeEventFile(sessionId: "watcher-test")
        }

        // Wait for processing
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            let sessions = try? self.databaseManager.fetchAllSessions()
            if sessions?.contains(where: { $0.sessionId == "watcher-test" }) == true {
                expectation.fulfill()
            }
        }

        waitForExpectations(timeout: 5.0)

        // File should have been deleted
        XCTAssertEqual(jsonFileCount(), 0)
    }

    func testHighVolumeProcessing() throws {
        // Simulate a burst of 100 events
        for i in 0..<100 {
            writeEventFile(event: "PreToolUse", sessionId: "burst-session", extraData: ["tool": "Read-\(i)"])
        }
        XCTAssertEqual(jsonFileCount(), 100)

        ingestionManager.processExistingFiles()

        XCTAssertEqual(jsonFileCount(), 0, "All 100 files should be deleted")
        let events = try databaseManager.fetchEvents(forSessionId: "burst-session")
        XCTAssertEqual(events.count, 100)
    }
}
