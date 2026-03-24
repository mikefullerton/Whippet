import XCTest
@testable import Whippet

final class SessionListViewModelTests: XCTestCase {

    private var tempDatabasePath: String!
    private var databaseManager: DatabaseManager!
    private var viewModel: SessionListViewModel!

    override func setUp() {
        super.setUp()
        tempDatabasePath = NSTemporaryDirectory() + "whippet_test_viewmodel_\(UUID().uuidString).db"
        databaseManager = try! DatabaseManager(path: tempDatabasePath)
        viewModel = SessionListViewModel(databaseManager: databaseManager)
    }

    override func tearDown() {
        viewModel.stopListening()
        viewModel = nil
        databaseManager.close()
        try? FileManager.default.removeItem(atPath: tempDatabasePath)
        super.tearDown()
    }

    // MARK: - Empty State

    func testEmptyState() {
        XCTAssertTrue(viewModel.isEmpty)
        XCTAssertEqual(viewModel.sessionCount, 0)
        XCTAssertEqual(viewModel.activeSessionCount, 0)
        XCTAssertTrue(viewModel.groups.isEmpty)
    }

    // MARK: - Loading Sessions

    func testLoadSessionsFromDatabase() throws {
        // Insert test sessions
        try databaseManager.upsertSession(Session(
            sessionId: "session-1",
            cwd: "/Users/test/projects/Alpha",
            model: "claude-3.5-sonnet",
            startedAt: "2026-03-24T10:00:00Z",
            lastActivityAt: "2026-03-24T10:05:00Z",
            lastTool: "Read",
            status: .active
        ))

        try databaseManager.upsertSession(Session(
            sessionId: "session-2",
            cwd: "/Users/test/projects/Beta",
            model: "claude-3-opus",
            startedAt: "2026-03-24T09:00:00Z",
            lastActivityAt: "2026-03-24T09:30:00Z",
            lastTool: "Edit",
            status: .ended
        ))

        viewModel.loadSessions()

        XCTAssertFalse(viewModel.isEmpty)
        XCTAssertEqual(viewModel.sessionCount, 2)
        XCTAssertEqual(viewModel.activeSessionCount, 1)
        XCTAssertEqual(viewModel.groups.count, 2)
    }

    // MARK: - Grouping

    func testSessionsGroupedByProject() throws {
        // Two sessions in the same project
        try databaseManager.upsertSession(Session(
            sessionId: "session-1",
            cwd: "/Users/test/projects/Whippet",
            model: "claude-3.5-sonnet",
            status: .active
        ))

        try databaseManager.upsertSession(Session(
            sessionId: "session-2",
            cwd: "/Users/test/projects/Whippet",
            model: "claude-3-opus",
            status: .stale
        ))

        // One session in a different project
        try databaseManager.upsertSession(Session(
            sessionId: "session-3",
            cwd: "/Users/test/projects/OtherProject",
            model: "claude-3.5-sonnet",
            status: .ended
        ))

        viewModel.loadSessions()

        XCTAssertEqual(viewModel.groups.count, 2)

        // Find the Whippet group
        let whippetGroup = viewModel.groups.first { $0.projectName == "Whippet" }
        XCTAssertNotNil(whippetGroup)
        XCTAssertEqual(whippetGroup?.sessions.count, 2)
        XCTAssertTrue(whippetGroup?.hasActiveSessions ?? false)

        // Find the OtherProject group
        let otherGroup = viewModel.groups.first { $0.projectName == "OtherProject" }
        XCTAssertNotNil(otherGroup)
        XCTAssertEqual(otherGroup?.sessions.count, 1)
        XCTAssertFalse(otherGroup?.hasActiveSessions ?? true)
    }

    func testGroupsWithActiveSessionsSortedFirst() throws {
        // Create a group with only ended sessions (older activity)
        try databaseManager.upsertSession(Session(
            sessionId: "session-ended",
            cwd: "/Users/test/projects/EndedProject",
            model: "claude-3.5-sonnet",
            lastActivityAt: "2026-03-24T12:00:00Z",
            status: .ended
        ))

        // Create a group with an active session (older start time but active)
        try databaseManager.upsertSession(Session(
            sessionId: "session-active",
            cwd: "/Users/test/projects/ActiveProject",
            model: "claude-3.5-sonnet",
            lastActivityAt: "2026-03-24T08:00:00Z",
            status: .active
        ))

        viewModel.loadSessions()

        XCTAssertEqual(viewModel.groups.count, 2)
        // Active group should be first even though its activity is older
        XCTAssertEqual(viewModel.groups[0].projectName, "ActiveProject")
        XCTAssertEqual(viewModel.groups[1].projectName, "EndedProject")
    }

    func testSessionsWithEmptyCwdGroupedAsUnknown() throws {
        try databaseManager.upsertSession(Session(
            sessionId: "session-no-cwd",
            cwd: "",
            model: "claude-3.5-sonnet",
            status: .active
        ))

        viewModel.loadSessions()

        XCTAssertEqual(viewModel.groups.count, 1)
        XCTAssertEqual(viewModel.groups[0].projectName, "Unknown")
    }

    // MARK: - Session Counts

    func testSessionCountsAreAccurate() throws {
        try databaseManager.upsertSession(Session(sessionId: "s1", cwd: "/a", status: .active))
        try databaseManager.upsertSession(Session(sessionId: "s2", cwd: "/b", status: .active))
        try databaseManager.upsertSession(Session(sessionId: "s3", cwd: "/c", status: .stale))
        try databaseManager.upsertSession(Session(sessionId: "s4", cwd: "/d", status: .ended))

        viewModel.loadSessions()

        XCTAssertEqual(viewModel.sessionCount, 4)
        XCTAssertEqual(viewModel.activeSessionCount, 2)
    }

    // MARK: - Real-time Updates via Notification

    func testNotificationTriggersReload() throws {
        // Start with empty state
        XCTAssertTrue(viewModel.isEmpty)

        // Insert a session directly into the database
        try databaseManager.upsertSession(Session(
            sessionId: "session-new",
            cwd: "/Users/test/projects/NewProject",
            model: "claude-3.5-sonnet",
            status: .active
        ))

        // Post the notification that the ingestion layer would post
        let expectation = expectation(description: "View model updates after notification")

        // Give the notification time to propagate and the view model to update
        SessionListViewModel.notifySessionsChanged()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if !self.viewModel.isEmpty {
                expectation.fulfill()
            }
        }

        waitForExpectations(timeout: 2.0)

        XCTAssertFalse(viewModel.isEmpty)
        XCTAssertEqual(viewModel.sessionCount, 1)
        XCTAssertEqual(viewModel.activeSessionCount, 1)
    }

    // MARK: - Session Group

    func testSessionGroupIdentifiable() throws {
        let group = SessionGroup(
            id: "TestProject",
            projectName: "TestProject",
            sessions: [
                Session(sessionId: "s1", cwd: "/test/TestProject", status: .active),
                Session(sessionId: "s2", cwd: "/test/TestProject", status: .ended)
            ]
        )

        XCTAssertEqual(group.id, "TestProject")
        XCTAssertTrue(group.hasActiveSessions)
    }

    func testSessionGroupNoActiveSessions() {
        let group = SessionGroup(
            id: "DoneProject",
            projectName: "DoneProject",
            sessions: [
                Session(sessionId: "s1", cwd: "/test/DoneProject", status: .ended),
                Session(sessionId: "s2", cwd: "/test/DoneProject", status: .stale)
            ]
        )

        XCTAssertFalse(group.hasActiveSessions)
    }

    // MARK: - Multiple Projects Grouping

    func testMultipleProjectsGroupCorrectly() throws {
        let projects = ["Alpha", "Beta", "Gamma"]
        var sessionIndex = 0

        for project in projects {
            for i in 0..<3 {
                sessionIndex += 1
                try databaseManager.upsertSession(Session(
                    sessionId: "session-\(sessionIndex)",
                    cwd: "/Users/test/projects/\(project)",
                    model: "claude-3.5-sonnet",
                    status: i == 0 ? .active : .ended
                ))
            }
        }

        viewModel.loadSessions()

        XCTAssertEqual(viewModel.groups.count, 3)
        XCTAssertEqual(viewModel.sessionCount, 9)
        XCTAssertEqual(viewModel.activeSessionCount, 3)

        // Each group should have 3 sessions
        for group in viewModel.groups {
            XCTAssertEqual(group.sessions.count, 3, "Group \(group.projectName) should have 3 sessions")
        }
    }

    // MARK: - Sessions Sorted Within Groups

    func testSessionsSortedByLastActivityWithinGroup() throws {
        try databaseManager.upsertSession(Session(
            sessionId: "old-session",
            cwd: "/Users/test/projects/Project",
            lastActivityAt: "2026-03-24T08:00:00Z",
            status: .ended
        ))

        try databaseManager.upsertSession(Session(
            sessionId: "new-session",
            cwd: "/Users/test/projects/Project",
            lastActivityAt: "2026-03-24T12:00:00Z",
            status: .active
        ))

        try databaseManager.upsertSession(Session(
            sessionId: "mid-session",
            cwd: "/Users/test/projects/Project",
            lastActivityAt: "2026-03-24T10:00:00Z",
            status: .stale
        ))

        viewModel.loadSessions()

        XCTAssertEqual(viewModel.groups.count, 1)
        let sessions = viewModel.groups[0].sessions
        XCTAssertEqual(sessions.count, 3)

        // Should be sorted newest first
        XCTAssertEqual(sessions[0].sessionId, "new-session")
        XCTAssertEqual(sessions[1].sessionId, "mid-session")
        XCTAssertEqual(sessions[2].sessionId, "old-session")
    }

    // MARK: - Project Name Derivation

    func testProjectNameDerivedFromCwd() {
        let session = Session(sessionId: "s1", cwd: "/Users/test/projects/MyProject")
        XCTAssertEqual(session.projectName, "MyProject")
    }

    func testProjectNameForEmptyCwd() {
        let session = Session(sessionId: "s1", cwd: "")
        XCTAssertEqual(session.projectName, "Unknown")
    }

    func testProjectNameForRootPath() {
        let session = Session(sessionId: "s1", cwd: "/")
        XCTAssertEqual(session.projectName, "/")
    }
}
