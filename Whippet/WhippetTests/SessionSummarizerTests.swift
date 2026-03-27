import XCTest
@testable import Whippet

final class SessionSummarizerTests: XCTestCase {

    // MARK: - Event Distillation

    func testDistillEvent_SessionStart() {
        let event = SessionEvent(
            sessionId: "test-1",
            eventType: "SessionStart",
            rawJson: #"{"event":"SessionStart","session_id":"test-1","data":{"cwd":"/Users/user/project","model":"sonnet"}}"#
        )

        let result = SessionSummarizer.distillEvent(event)
        XCTAssertTrue(result.contains("[SessionStart]"))
        XCTAssertTrue(result.contains("cwd=/Users/user/project"))
        XCTAssertTrue(result.contains("model=sonnet"))
    }

    func testDistillEvent_UserPromptSubmit() {
        let prompt = String(repeating: "a", count: 600)
        let event = SessionEvent(
            sessionId: "test-1",
            eventType: "UserPromptSubmit",
            rawJson: #"{"event":"UserPromptSubmit","session_id":"test-1","data":{"cwd":"/tmp","prompt":"\#(prompt)"}}"#
        )

        let result = SessionSummarizer.distillEvent(event)
        XCTAssertTrue(result.contains("[UserPrompt]"))
        // Should be truncated to 500 chars
        XCTAssertTrue(result.count < 600)
    }

    func testDistillEvent_PreToolUse_WithFilePath() {
        let event = SessionEvent(
            sessionId: "test-1",
            eventType: "PreToolUse",
            rawJson: #"{"event":"PreToolUse","session_id":"test-1","data":{"tool":"Read","tool_input":{"file_path":"/src/main.swift"}}}"#
        )

        let result = SessionSummarizer.distillEvent(event)
        XCTAssertTrue(result.contains("[Tool:Read]"))
        XCTAssertTrue(result.contains("file: /src/main.swift"))
    }

    func testDistillEvent_PostToolUse_ShowsSizeOnly() {
        let longResponse = String(repeating: "x", count: 5000)
        let event = SessionEvent(
            sessionId: "test-1",
            eventType: "PostToolUse",
            rawJson: #"{"event":"PostToolUse","session_id":"test-1","data":{"tool":"Read","tool_response":"\#(longResponse)"}}"#
        )

        let result = SessionSummarizer.distillEvent(event)
        XCTAssertTrue(result.contains("[Tool:Read result]"))
        // Should show size, NOT the full response
        XCTAssertTrue(result.contains("KB") || result.contains("B)"))
        XCTAssertFalse(result.contains(longResponse))
    }

    func testDistillEvent_SessionEnd() {
        let event = SessionEvent(
            sessionId: "test-1",
            eventType: "SessionEnd",
            rawJson: #"{"event":"SessionEnd","session_id":"test-1","data":{"reason":"user_exit"}}"#
        )

        let result = SessionSummarizer.distillEvent(event)
        XCTAssertEqual(result, "[SessionEnd] reason=user_exit")
    }

    func testDistillEvent_Stop() {
        let event = SessionEvent(
            sessionId: "test-1",
            eventType: "Stop",
            rawJson: #"{"event":"Stop","session_id":"test-1","data":{}}"#
        )

        let result = SessionSummarizer.distillEvent(event)
        XCTAssertEqual(result, "[Stop]")
    }

    // MARK: - Budget Fitting

    func testFitEventsToBudget_UnderBudget() {
        let events = (0..<5).map { i in
            SessionEvent(
                sessionId: "s1",
                eventType: "UserPromptSubmit",
                rawJson: #"{"event":"UserPromptSubmit","session_id":"s1","data":{"prompt":"msg \#(i)"}}"#
            )
        }

        let result = SessionSummarizer.fitEventsToBudget(events: events, charBudget: 100_000)
        XCTAssertEqual(result.count, 5)
        XCTAssertFalse(result.contains { $0.contains("omitted") })
    }

    func testFitEventsToBudget_OverBudget() {
        // Create many events that exceed budget
        let events = (0..<100).map { i in
            SessionEvent(
                sessionId: "s1",
                eventType: "UserPromptSubmit",
                rawJson: #"{"event":"UserPromptSubmit","session_id":"s1","data":{"prompt":"\#(String(repeating: "word ", count: 50)) \#(i)"}}"#
            )
        }

        let result = SessionSummarizer.fitEventsToBudget(events: events, charBudget: 1000)
        XCTAssertTrue(result.count < 100)
        XCTAssertTrue(result.contains { $0.contains("omitted") })
    }

    // MARK: - Prompt Construction

    func testBuildSummarizationPrompt_IncludesMetadata() throws {
        let db = try DatabaseManager(path: temporaryDatabasePath())
        let summarizer = SessionSummarizer(databaseManager: db)

        let session = Session(
            sessionId: "s1",
            cwd: "/Users/user/myproject",
            model: "sonnet",
            gitBranch: "feature/login"
        )
        let events = [
            SessionEvent(
                sessionId: "s1",
                eventType: "SessionStart",
                rawJson: #"{"event":"SessionStart","session_id":"s1","data":{"cwd":"/Users/user/myproject","model":"sonnet"}}"#
            ),
            SessionEvent(
                sessionId: "s1",
                eventType: "UserPromptSubmit",
                rawJson: #"{"event":"UserPromptSubmit","session_id":"s1","data":{"prompt":"fix the login bug"}}"#
            ),
        ]

        let prompt = summarizer.buildSummarizationPrompt(session: session, events: events)
        XCTAssertTrue(prompt.contains("myproject"))
        XCTAssertTrue(prompt.contains("sonnet"))
        XCTAssertTrue(prompt.contains("feature/login"))
        XCTAssertTrue(prompt.contains("fix the login bug"))
    }

    // MARK: - Helpers

    private func temporaryDatabasePath() -> String {
        let temp = FileManager.default.temporaryDirectory
        return temp.appendingPathComponent("test-summarizer-\(UUID().uuidString).db").path
    }
}
