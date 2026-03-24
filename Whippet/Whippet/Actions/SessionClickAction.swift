import Foundation

/// Represents the supported click actions that can be triggered when a user clicks a session row.
enum SessionClickAction: String, CaseIterable {
    /// Opens the default terminal app at the session's working directory.
    case openTerminal = "open_terminal"

    /// Opens the session transcript file in the default application.
    case openTranscript = "open_transcript"

    /// Copies the session ID to the system clipboard.
    case copySessionId = "copy_session_id"

    /// Runs a custom shell command with variable substitution.
    case customCommand = "custom_command"

    /// Sends a macOS notification with session details.
    case sendNotification = "send_notification"

    /// Human-readable display name for UI.
    var displayName: String {
        switch self {
        case .openTerminal: return "Open Terminal"
        case .openTranscript: return "Open Transcript"
        case .copySessionId: return "Copy Session ID"
        case .customCommand: return "Run Custom Command"
        case .sendNotification: return "Send Notification"
        }
    }

    /// System image name for UI icons.
    var systemImage: String {
        switch self {
        case .openTerminal: return "terminal"
        case .openTranscript: return "doc.text"
        case .copySessionId: return "doc.on.clipboard"
        case .customCommand: return "command"
        case .sendNotification: return "bell"
        }
    }
}
