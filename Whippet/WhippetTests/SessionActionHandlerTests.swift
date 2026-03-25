import XCTest
@testable import Whippet

final class SessionActionHandlerTests: XCTestCase {

    private var databaseManager: DatabaseManager!
    private var handler: SessionActionHandler!
    private var tempDBPath: String!

    override func setUp() {
        super.setUp()
        tempDBPath = NSTemporaryDirectory() + "whippet_action_test_\(UUID().uuidString).db"
        databaseManager = try! DatabaseManager(path: tempDBPath)
        handler = SessionActionHandler(databaseManager: databaseManager)
    }

    override func tearDown() {
        handler = nil
        databaseManager.close()
        databaseManager = nil
        try? FileManager.default.removeItem(atPath: tempDBPath)
        super.tearDown()
    }

    // MARK: - Helper

    private func makeSession(
        sessionId: String = "test-session-123",
        cwd: String = "/Users/test/projects/MyApp",
        model: String = "claude-3-opus",
        status: SessionStatus = .active
    ) -> Session {
        Session(
            sessionId: sessionId,
            cwd: cwd,
            model: model,
            status: status
        )
    }

    // MARK: - SessionClickAction Tests

    func testAllActionCasesExist() {
        let allCases = SessionClickAction.allCases
        XCTAssertEqual(allCases.count, 7)
        XCTAssertTrue(allCases.contains(.openTerminal))
        XCTAssertTrue(allCases.contains(.activateWarp))
        XCTAssertTrue(allCases.contains(.activateWindow))
        XCTAssertTrue(allCases.contains(.openTranscript))
        XCTAssertTrue(allCases.contains(.copySessionId))
        XCTAssertTrue(allCases.contains(.customCommand))
        XCTAssertTrue(allCases.contains(.sendNotification))
    }

    func testActionRawValues() {
        XCTAssertEqual(SessionClickAction.openTerminal.rawValue, "open_terminal")
        XCTAssertEqual(SessionClickAction.activateWarp.rawValue, "activate_warp")
        XCTAssertEqual(SessionClickAction.activateWindow.rawValue, "activate_window")
        XCTAssertEqual(SessionClickAction.openTranscript.rawValue, "open_transcript")
        XCTAssertEqual(SessionClickAction.copySessionId.rawValue, "copy_session_id")
        XCTAssertEqual(SessionClickAction.customCommand.rawValue, "custom_command")
        XCTAssertEqual(SessionClickAction.sendNotification.rawValue, "send_notification")
    }

    func testActionDisplayNames() {
        XCTAssertEqual(SessionClickAction.openTerminal.displayName, "Open Terminal")
        XCTAssertEqual(SessionClickAction.activateWarp.displayName, "Activate in Warp")
        XCTAssertEqual(SessionClickAction.activateWindow.displayName, "Activate Window")
        XCTAssertEqual(SessionClickAction.openTranscript.displayName, "Open Transcript")
        XCTAssertEqual(SessionClickAction.copySessionId.displayName, "Copy Session ID")
        XCTAssertEqual(SessionClickAction.customCommand.displayName, "Run Custom Command")
        XCTAssertEqual(SessionClickAction.sendNotification.displayName, "Send Notification")
    }

    func testActionSystemImages() {
        for action in SessionClickAction.allCases {
            XCTAssertFalse(action.systemImage.isEmpty, "System image should not be empty for \(action)")
        }
    }

    // MARK: - Default Action Tests

    func testDefaultActionIsOpenTerminal() {
        XCTAssertEqual(handler.currentAction, .openTerminal)
    }

    func testSetAndGetAction() throws {
        try handler.setAction(.copySessionId)
        XCTAssertEqual(handler.currentAction, .copySessionId)

        try handler.setAction(.openTranscript)
        XCTAssertEqual(handler.currentAction, .openTranscript)
    }

    func testActionPersistsInDatabase() throws {
        try handler.setAction(.customCommand)

        // Create a new handler pointing to the same database
        let handler2 = SessionActionHandler(databaseManager: databaseManager)
        XCTAssertEqual(handler2.currentAction, .customCommand)
    }

    // MARK: - Custom Command Template Tests

    func testDefaultCustomCommandTemplate() {
        let template = handler.customCommandTemplate
        XCTAssertEqual(template, "echo $SESSION_ID $CWD $MODEL")
    }

    func testSetAndGetCustomCommandTemplate() throws {
        let template = "open -a 'Visual Studio Code' $CWD"
        try handler.setCustomCommandTemplate(template)
        XCTAssertEqual(handler.customCommandTemplate, template)
    }

    func testCustomCommandTemplatePersistsInDatabase() throws {
        let template = "echo $MODEL > /tmp/model.txt"
        try handler.setCustomCommandTemplate(template)

        let handler2 = SessionActionHandler(databaseManager: databaseManager)
        XCTAssertEqual(handler2.customCommandTemplate, template)
    }

    // MARK: - Variable Substitution Tests

    func testVariableSubstitution() {
        let session = makeSession()
        let template = "echo $SESSION_ID at $CWD using $MODEL"
        let result = handler.substituteVariables(in: template, session: session)
        // Values are shell-escaped with single quotes for injection protection
        XCTAssertEqual(result, "echo 'test-session-123' at '/Users/test/projects/MyApp' using 'claude-3-opus'")
    }

    func testVariableSubstitutionWithNoVariables() {
        let session = makeSession()
        let template = "echo hello world"
        let result = handler.substituteVariables(in: template, session: session)
        XCTAssertEqual(result, "echo hello world")
    }

    func testVariableSubstitutionWithEmptyFields() {
        let session = makeSession(cwd: "", model: "")
        let template = "echo $SESSION_ID $CWD $MODEL"
        let result = handler.substituteVariables(in: template, session: session)
        XCTAssertEqual(result, "echo 'test-session-123' '' ''")
    }

    func testVariableSubstitutionMultipleOccurrences() {
        let session = makeSession(sessionId: "abc")
        let template = "$SESSION_ID-$SESSION_ID"
        let result = handler.substituteVariables(in: template, session: session)
        XCTAssertEqual(result, "'abc'-'abc'")
    }

    // MARK: - Copy Session ID Tests

    func testCopySessionIdAction() {
        let session = makeSession(sessionId: "copy-test-id-456")
        let result = handler.execute(action: .copySessionId, for: session)

        switch result {
        case .success:
            let pasteboard = NSPasteboard.general
            let content = pasteboard.string(forType: .string)
            XCTAssertEqual(content, "copy-test-id-456")
        case .failure(let error):
            XCTFail("Copy session ID should succeed, got error: \(error)")
        }
    }

    // MARK: - Custom Command Tests

    func testCustomCommandExecution() throws {
        let tempFile = NSTemporaryDirectory() + "whippet_cmd_test_\(UUID().uuidString).txt"
        defer { try? FileManager.default.removeItem(atPath: tempFile) }

        try handler.setCustomCommandTemplate("echo $SESSION_ID > \(tempFile)")
        let session = makeSession(sessionId: "cmd-test-789")
        let result = handler.execute(action: .customCommand, for: session)

        // Command runs async on background queue; execute returns .success immediately
        switch result {
        case .success:
            // Wait briefly for background command to complete
            let expectation = XCTestExpectation(description: "Command writes file")
            DispatchQueue.global().asyncAfter(deadline: .now() + 1.0) {
                expectation.fulfill()
            }
            wait(for: [expectation], timeout: 3.0)
            let content = try String(contentsOfFile: tempFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
            XCTAssertEqual(content, "cmd-test-789")
        case .failure(let error):
            XCTFail("Custom command should succeed, got error: \(error)")
        }
    }

    func testCustomCommandWithAllVariables() throws {
        let tempFile = NSTemporaryDirectory() + "whippet_cmd_test_\(UUID().uuidString).txt"
        defer { try? FileManager.default.removeItem(atPath: tempFile) }

        // Template wraps vars in literal single quotes; substituteVariables also adds shell escaping
        try handler.setCustomCommandTemplate("echo $SESSION_ID $CWD $MODEL > \(tempFile)")
        let session = makeSession()
        let result = handler.execute(action: .customCommand, for: session)

        switch result {
        case .success:
            let expectation = XCTestExpectation(description: "Command writes file")
            DispatchQueue.global().asyncAfter(deadline: .now() + 1.0) {
                expectation.fulfill()
            }
            wait(for: [expectation], timeout: 3.0)
            let content = try String(contentsOfFile: tempFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
            XCTAssertEqual(content, "test-session-123 /Users/test/projects/MyApp claude-3-opus")
        case .failure(let error):
            XCTFail("Custom command should succeed, got error: \(error)")
        }
    }

    func testCustomCommandFailureReturnsSuccessAsync() throws {
        // Since custom commands now run async, execute always returns .success
        // Failures are logged but not returned synchronously
        try handler.setCustomCommandTemplate("exit 1")
        let session = makeSession()
        let result = handler.execute(action: .customCommand, for: session)

        switch result {
        case .success:
            break // Expected — command runs async
        case .failure:
            XCTFail("Custom command should return success (runs async)")
        }
    }

    // MARK: - Open Terminal Error Tests

    func testOpenTerminalWithEmptyPath() {
        let session = makeSession(cwd: "")
        let result = handler.execute(action: .openTerminal, for: session)

        switch result {
        case .success:
            XCTFail("Should fail with empty path")
        case .failure(let error):
            switch error {
            case .directoryNotFound:
                break // expected
            default:
                XCTFail("Expected directoryNotFound error, got \(error)")
            }
        }
    }

    func testOpenTerminalWithNonexistentPath() {
        let session = makeSession(cwd: "/nonexistent/path/that/does/not/exist")
        let result = handler.execute(action: .openTerminal, for: session)

        switch result {
        case .success:
            XCTFail("Should fail with nonexistent path")
        case .failure(let error):
            switch error {
            case .directoryNotFound:
                break // expected
            default:
                XCTFail("Expected directoryNotFound error, got \(error)")
            }
        }
    }

    // MARK: - Open Transcript Error Tests

    func testOpenTranscriptFileNotFound() {
        let session = makeSession(sessionId: "nonexistent-session-id-999")
        let result = handler.execute(action: .openTranscript, for: session)

        switch result {
        case .success:
            XCTFail("Should fail when transcript doesn't exist")
        case .failure(let error):
            switch error {
            case .transcriptNotFound:
                break // expected
            default:
                XCTFail("Expected transcriptNotFound error, got \(error)")
            }
        }
    }

    // MARK: - Action via Configured Setting Tests

    func testExecuteUsesConfiguredAction() throws {
        try handler.setAction(.copySessionId)

        let session = makeSession(sessionId: "configured-action-test")
        let result = handler.execute(for: session)

        switch result {
        case .success:
            let pasteboard = NSPasteboard.general
            let content = pasteboard.string(forType: .string)
            XCTAssertEqual(content, "configured-action-test")
        case .failure(let error):
            XCTFail("Execute should use configured action and succeed, got error: \(error)")
        }
    }

    // MARK: - SessionActionError Tests

    func testErrorDescriptions() {
        let errors: [SessionActionError] = [
            .directoryNotFound("/test/path"),
            .transcriptNotFound("/test/transcript"),
            .commandFailed("something went wrong"),
            .notificationFailed("notification error"),
            .noActionConfigured,
        ]

        for error in errors {
            XCTAssertNotNil(error.errorDescription, "Error should have a description: \(error)")
            XCTAssertFalse(error.errorDescription!.isEmpty, "Error description should not be empty: \(error)")
        }
    }

    func testDirectoryNotFoundErrorContainsPath() {
        let error = SessionActionError.directoryNotFound("/my/path")
        XCTAssertTrue(error.localizedDescription.contains("/my/path"))
    }

    func testTranscriptNotFoundErrorContainsPath() {
        let error = SessionActionError.transcriptNotFound("/my/transcript")
        XCTAssertTrue(error.localizedDescription.contains("/my/transcript"))
    }

    func testCommandFailedErrorContainsMessage() {
        let error = SessionActionError.commandFailed("bad command")
        XCTAssertTrue(error.localizedDescription.contains("bad command"))
    }
}
