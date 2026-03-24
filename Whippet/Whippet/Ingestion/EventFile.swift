import Foundation

/// Represents a parsed JSON event file from the drop directory.
/// File naming convention: `{timestamp}-{uuid}.json`
/// JSON format: `{"event": "...", "session_id": "...", "timestamp": "...", "data": {...}}`
struct EventFile {
    /// The event type (e.g., "SessionStart", "SessionEnd", "PreToolUse", "PostToolUse", etc.)
    let event: String

    /// The unique session identifier from Claude Code.
    let sessionId: String

    /// ISO 8601 timestamp of when the event occurred.
    let timestamp: String

    /// Event-specific data payload.
    let data: [String: Any]

    /// The raw JSON string of the entire file contents.
    let rawJson: String
}

/// Known event types that can appear in drop directory files.
enum EventType: String, CaseIterable {
    case sessionStart = "SessionStart"
    case sessionEnd = "SessionEnd"
    case userPromptSubmit = "UserPromptSubmit"
    case preToolUse = "PreToolUse"
    case postToolUse = "PostToolUse"
    case stop = "Stop"
    case subagentStart = "SubagentStart"
    case subagentStop = "SubagentStop"
    case notification = "Notification"
}
