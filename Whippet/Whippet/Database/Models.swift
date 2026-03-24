import Foundation

// MARK: - Session

/// Represents a Claude Code session being monitored.
struct Session: Equatable {
    var id: Int?
    var sessionId: String
    var cwd: String
    var model: String
    var startedAt: String
    var lastActivityAt: String
    var lastTool: String
    var status: SessionStatus

    init(
        id: Int? = nil,
        sessionId: String,
        cwd: String = "",
        model: String = "",
        startedAt: String = "",
        lastActivityAt: String = "",
        lastTool: String = "",
        status: SessionStatus = .active
    ) {
        self.id = id
        self.sessionId = sessionId
        self.cwd = cwd
        self.model = model
        self.startedAt = startedAt.isEmpty ? ISO8601DateFormatter().string(from: Date()) : startedAt
        self.lastActivityAt = lastActivityAt.isEmpty ? ISO8601DateFormatter().string(from: Date()) : lastActivityAt
        self.lastTool = lastTool
        self.status = status
    }

    /// Derives the project name from the working directory path.
    var projectName: String {
        guard !cwd.isEmpty else { return "Unknown" }
        return (cwd as NSString).lastPathComponent
    }
}

// MARK: - Session Status

/// The lifecycle status of a session.
enum SessionStatus: String, CaseIterable {
    case active
    case stale
    case ended
}

// MARK: - Session Event

/// Represents a single event in a Claude Code session.
struct SessionEvent: Equatable {
    var id: Int?
    var sessionId: String
    var eventType: String
    var timestamp: String
    var rawJson: String

    init(
        id: Int? = nil,
        sessionId: String,
        eventType: String,
        timestamp: String = "",
        rawJson: String = "{}"
    ) {
        self.id = id
        self.sessionId = sessionId
        self.eventType = eventType
        self.timestamp = timestamp.isEmpty ? ISO8601DateFormatter().string(from: Date()) : timestamp
        self.rawJson = rawJson
    }
}

// MARK: - Database Error

/// Errors that can occur during database operations.
enum DatabaseError: Error, LocalizedError {
    case openFailed(String)
    case prepareFailed(String)
    case executionFailed(String)
    case migrationFailed(String)

    var errorDescription: String? {
        switch self {
        case .openFailed(let message):
            return "Failed to open database: \(message)"
        case .prepareFailed(let message):
            return "Failed to prepare statement: \(message)"
        case .executionFailed(let message):
            return "Failed to execute statement: \(message)"
        case .migrationFailed(let message):
            return "Database migration failed: \(message)"
        }
    }
}
