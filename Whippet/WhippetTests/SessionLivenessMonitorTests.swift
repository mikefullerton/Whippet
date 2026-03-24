import XCTest
@testable import Whippet

final class SessionLivenessMonitorTests: XCTestCase {

    private var dbManager: DatabaseManager!
    private var monitor: SessionLivenessMonitor!
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("whippet-liveness-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let dbPath = tempDir.appendingPathComponent("test.db").path
        dbManager = try DatabaseManager(path: dbPath)
        monitor = SessionLivenessMonitor(databaseManager: dbManager)
    }

    override func tearDownWithError() throws {
        monitor.stop()
        monitor = nil
        dbManager.close()
        dbManager = nil
        try? FileManager.default.removeItem(at: tempDir)
    }

    // MARK: - Helper Methods

    /// Creates a session with a specific last_activity_at timestamp.
    @discardableResult
    private func createSession(
        sessionId: String,
        status: SessionStatus = .active,
        lastActivitySecondsAgo: TimeInterval = 0
    ) throws -> Session {
        let activityDate = Date().addingTimeInterval(-lastActivitySecondsAgo)
        let formatter = ISO8601DateFormatter()
        let timestamp = formatter.string(from: activityDate)

        let session = Session(
            sessionId: sessionId,
            cwd: "/Users/test/project",
            model: "opus",
            startedAt: timestamp,
            lastActivityAt: timestamp,
            lastTool: "Read",
            status: status
        )
        return try dbManager.upsertSession(session)
    }

    // MARK: - Default Timeout Tests

    func testDefaultTimeoutIs60Seconds() {
        XCTAssertEqual(SessionLivenessMonitor.defaultTimeoutSeconds, 60)
    }

    func testCurrentTimeoutReturnsDefaultWhenNoSetting() {
        let timeout = monitor.currentTimeout()
        XCTAssertEqual(timeout, SessionLivenessMonitor.defaultTimeoutSeconds)
    }

    // MARK: - Configurable Timeout Tests

    func testCurrentTimeoutReadsFromSettings() throws {
        try dbManager.setSetting(
            key: SessionLivenessMonitor.stalenessTimeoutKey,
            value: "120"
        )
        let timeout = monitor.currentTimeout()
        XCTAssertEqual(timeout, 120)
    }

    func testCurrentTimeoutIgnoresInvalidSettingValue() throws {
        try dbManager.setSetting(
            key: SessionLivenessMonitor.stalenessTimeoutKey,
            value: "not-a-number"
        )
        let timeout = monitor.currentTimeout()
        XCTAssertEqual(timeout, SessionLivenessMonitor.defaultTimeoutSeconds)
    }

    func testCurrentTimeoutIgnoresZeroValue() throws {
        try dbManager.setSetting(
            key: SessionLivenessMonitor.stalenessTimeoutKey,
            value: "0"
        )
        let timeout = monitor.currentTimeout()
        XCTAssertEqual(timeout, SessionLivenessMonitor.defaultTimeoutSeconds)
    }

    func testCurrentTimeoutIgnoresNegativeValue() throws {
        try dbManager.setSetting(
            key: SessionLivenessMonitor.stalenessTimeoutKey,
            value: "-30"
        )
        let timeout = monitor.currentTimeout()
        XCTAssertEqual(timeout, SessionLivenessMonitor.defaultTimeoutSeconds)
    }

    // MARK: - Staleness Detection Tests

    func testActiveSessionBeyondTimeoutMarkedStale() throws {
        // Create an active session with last activity 120 seconds ago
        try createSession(sessionId: "session-1", status: .active, lastActivitySecondsAgo: 120)

        // Run liveness check (default timeout is 60s)
        monitor.performLivenessCheck()

        // Verify session is now stale
        let session = try dbManager.fetchSession(bySessionId: "session-1")
        XCTAssertEqual(session?.status, .stale)
    }

    func testActiveSessionWithinTimeoutRemainsActive() throws {
        // Create an active session with activity 10 seconds ago (well within 60s timeout)
        try createSession(sessionId: "session-1", status: .active, lastActivitySecondsAgo: 10)

        // Run liveness check
        monitor.performLivenessCheck()

        // Verify session is still active
        let session = try dbManager.fetchSession(bySessionId: "session-1")
        XCTAssertEqual(session?.status, .active)
    }

    func testMultipleSessionsSomeGoStale() throws {
        // One session well past timeout
        try createSession(sessionId: "stale-session", status: .active, lastActivitySecondsAgo: 120)
        // One session within timeout
        try createSession(sessionId: "active-session", status: .active, lastActivitySecondsAgo: 10)

        monitor.performLivenessCheck()

        let staleSession = try dbManager.fetchSession(bySessionId: "stale-session")
        XCTAssertEqual(staleSession?.status, .stale)

        let activeSession = try dbManager.fetchSession(bySessionId: "active-session")
        XCTAssertEqual(activeSession?.status, .active)
    }

    func testEndedSessionNotAffectedByLivenessCheck() throws {
        // Create an ended session with old activity
        try createSession(sessionId: "ended-session", status: .ended, lastActivitySecondsAgo: 300)

        monitor.performLivenessCheck()

        // Ended session should remain ended (not become stale)
        let session = try dbManager.fetchSession(bySessionId: "ended-session")
        XCTAssertEqual(session?.status, .ended)
    }

    func testAlreadyStaleSessionNotAffected() throws {
        // Create a session already marked stale
        try createSession(sessionId: "stale-session", status: .stale, lastActivitySecondsAgo: 300)

        // Should not error or change anything
        monitor.performLivenessCheck()

        let session = try dbManager.fetchSession(bySessionId: "stale-session")
        XCTAssertEqual(session?.status, .stale)
    }

    // MARK: - Stale-to-Active Promotion Tests

    func testStaleSessionPromotedToActiveOnNewEvent() throws {
        // Create a stale session
        try createSession(sessionId: "session-1", status: .stale, lastActivitySecondsAgo: 120)

        // Simulate a new event arriving by upserting with active status
        let updatedSession = Session(
            sessionId: "session-1",
            cwd: "/Users/test/project",
            model: "opus",
            lastActivityAt: ISO8601DateFormatter().string(from: Date()),
            lastTool: "Edit",
            status: .active
        )
        try dbManager.upsertSession(updatedSession)

        // Verify session is now active
        let session = try dbManager.fetchSession(bySessionId: "session-1")
        XCTAssertEqual(session?.status, .active)
    }

    // MARK: - SessionEnd Tests

    func testSessionEndAlwaysMarksEnded() throws {
        // Create an active session
        try createSession(sessionId: "session-1", status: .active, lastActivitySecondsAgo: 5)

        // Mark it ended via updateSessionStatus (same as EventIngestionManager does)
        try dbManager.updateSessionStatus(sessionId: "session-1", status: .ended)

        // Verify it is ended
        let session = try dbManager.fetchSession(bySessionId: "session-1")
        XCTAssertEqual(session?.status, .ended)

        // Liveness check should not change it back
        monitor.performLivenessCheck()
        let sessionAfterCheck = try dbManager.fetchSession(bySessionId: "session-1")
        XCTAssertEqual(sessionAfterCheck?.status, .ended)
    }

    // MARK: - Custom Timeout Tests

    func testCustomTimeoutRespected() throws {
        // Set a short custom timeout of 30 seconds
        try dbManager.setSetting(
            key: SessionLivenessMonitor.stalenessTimeoutKey,
            value: "30"
        )

        // Session with activity 45 seconds ago (past 30s timeout)
        try createSession(sessionId: "session-1", status: .active, lastActivitySecondsAgo: 45)

        // Session with activity 15 seconds ago (within 30s timeout)
        try createSession(sessionId: "session-2", status: .active, lastActivitySecondsAgo: 15)

        monitor.performLivenessCheck()

        let session1 = try dbManager.fetchSession(bySessionId: "session-1")
        XCTAssertEqual(session1?.status, .stale, "Session past 30s custom timeout should be stale")

        let session2 = try dbManager.fetchSession(bySessionId: "session-2")
        XCTAssertEqual(session2?.status, .active, "Session within 30s custom timeout should be active")
    }

    // MARK: - Callback Tests

    func testOnSessionsMarkedStaleCallbackFired() throws {
        // Create an expired session
        try createSession(sessionId: "session-1", status: .active, lastActivitySecondsAgo: 120)

        let expectation = XCTestExpectation(description: "onSessionsMarkedStale called")
        var markedCount = 0

        monitor.onSessionsMarkedStale = { count in
            markedCount = count
            expectation.fulfill()
        }

        monitor.performLivenessCheck()

        wait(for: [expectation], timeout: 2.0)
        XCTAssertEqual(markedCount, 1)
    }

    func testOnSessionsMarkedStaleNotCalledWhenNoneStale() throws {
        // Create a fresh active session
        try createSession(sessionId: "session-1", status: .active, lastActivitySecondsAgo: 5)

        var callbackCalled = false
        monitor.onSessionsMarkedStale = { _ in
            callbackCalled = true
        }

        monitor.performLivenessCheck()

        // Give a brief moment for any async dispatch
        Thread.sleep(forTimeInterval: 0.1)
        XCTAssertFalse(callbackCalled)
    }

    // MARK: - Start / Stop Tests

    func testStartSetsIsRunning() {
        XCTAssertFalse(monitor.isRunning)
        monitor.start()
        XCTAssertTrue(monitor.isRunning)
    }

    func testStopClearsIsRunning() {
        monitor.start()
        XCTAssertTrue(monitor.isRunning)
        monitor.stop()
        XCTAssertFalse(monitor.isRunning)
    }

    func testStartIsIdempotent() {
        monitor.start()
        monitor.start()
        XCTAssertTrue(monitor.isRunning)
        monitor.stop()
        XCTAssertFalse(monitor.isRunning)
    }

    // MARK: - No Sessions Tests

    func testLivenessCheckWithNoSessionsDoesNothing() {
        // Should not crash or error with empty database
        monitor.performLivenessCheck()
    }

    // MARK: - Integration: Timer-based Staleness

    func testTimerEventuallyMarksStaleSessions() throws {
        // Create a session that is already past timeout
        try createSession(sessionId: "session-1", status: .active, lastActivitySecondsAgo: 120)

        // Use a very short check interval for testing by calling performLivenessCheck directly
        // (The actual timer uses a 10s interval which is too slow for unit tests)
        monitor.performLivenessCheck()

        let session = try dbManager.fetchSession(bySessionId: "session-1")
        XCTAssertEqual(session?.status, .stale)
    }
}
