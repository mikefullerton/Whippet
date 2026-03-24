import AppKit
import UserNotifications

/// Errors that can occur when executing a session click action.
enum SessionActionError: Error, LocalizedError {
    case directoryNotFound(String)
    case transcriptNotFound(String)
    case commandFailed(String)
    case notificationFailed(String)
    case noActionConfigured

    var errorDescription: String? {
        switch self {
        case .directoryNotFound(let path):
            return "Directory not found: \(path)"
        case .transcriptNotFound(let path):
            return "Transcript file not found: \(path)"
        case .commandFailed(let message):
            return "Command failed: \(message)"
        case .notificationFailed(let message):
            return "Notification failed: \(message)"
        case .noActionConfigured:
            return "No click action configured"
        }
    }
}

/// Result of executing a session click action.
enum SessionActionResult {
    case success
    case failure(SessionActionError)
}

/// Handles execution of session click actions.
///
/// Reads the configured action from the database settings table and executes
/// the appropriate action when a session row is clicked. Supports variable
/// substitution in custom shell commands using `$SESSION_ID`, `$CWD`, and `$MODEL`.
final class SessionActionHandler {

    // MARK: - Settings Keys

    /// The settings key for the selected click action.
    static let clickActionKey = "click_action"

    /// The settings key for the custom shell command template.
    static let customCommandKey = "custom_command_template"

    // MARK: - Properties

    private let databaseManager: DatabaseManager

    // MARK: - Initialization

    /// Creates an action handler that reads settings from the given database manager.
    init(databaseManager: DatabaseManager) {
        self.databaseManager = databaseManager
    }

    // MARK: - Configuration

    /// Returns the currently configured click action, defaulting to `.openTerminal`.
    var currentAction: SessionClickAction {
        guard let value = try? databaseManager.getSetting(key: Self.clickActionKey),
              let action = SessionClickAction(rawValue: value) else {
            return .openTerminal
        }
        return action
    }

    /// Sets the click action in settings.
    func setAction(_ action: SessionClickAction) throws {
        try databaseManager.setSetting(key: Self.clickActionKey, value: action.rawValue)
    }

    /// Returns the custom command template, or a default placeholder.
    var customCommandTemplate: String {
        (try? databaseManager.getSetting(key: Self.customCommandKey)) ?? "echo $SESSION_ID $CWD $MODEL"
    }

    /// Sets the custom command template in settings.
    func setCustomCommandTemplate(_ template: String) throws {
        try databaseManager.setSetting(key: Self.customCommandKey, value: template)
    }

    // MARK: - Execution

    /// Executes the configured click action for the given session.
    /// - Parameter session: The session that was clicked.
    /// - Returns: The result of the action execution.
    @discardableResult
    func execute(for session: Session) -> SessionActionResult {
        return execute(action: currentAction, for: session)
    }

    /// Executes a specific action for the given session.
    /// - Parameters:
    ///   - action: The action to execute.
    ///   - session: The session that was clicked.
    /// - Returns: The result of the action execution.
    @discardableResult
    func execute(action: SessionClickAction, for session: Session) -> SessionActionResult {
        switch action {
        case .openTerminal:
            return openTerminal(at: session.cwd)
        case .openTranscript:
            return openTranscript(for: session)
        case .copySessionId:
            return copySessionId(session.sessionId)
        case .customCommand:
            return runCustomCommand(for: session)
        case .sendNotification:
            return sendNotification(for: session)
        }
    }

    // MARK: - Action Implementations

    /// Opens the default terminal app at the given directory.
    private func openTerminal(at path: String) -> SessionActionResult {
        guard !path.isEmpty else {
            return .failure(.directoryNotFound(""))
        }

        let expandedPath = (path as NSString).expandingTildeInPath
        guard FileManager.default.fileExists(atPath: expandedPath) else {
            return .failure(.directoryNotFound(expandedPath))
        }

        // Try iTerm2 first, fall back to Terminal.app
        if NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.googlecode.iterm2") != nil {
            // Use iTerm2 via AppleScript for directory support
            let script = """
                tell application "iTerm"
                    activate
                    create window with default profile command "cd \(shellEscape(expandedPath)) && exec $SHELL -l"
                end tell
            """
            var error: NSDictionary?
            if let appleScript = NSAppleScript(source: script) {
                appleScript.executeAndReturnError(&error)
                if let error = error {
                    NSLog("Whippet: iTerm2 script error: \(error), falling back to Terminal.app")
                    return openTerminalApp(at: expandedPath)
                }
                return .success
            }
            return openTerminalApp(at: expandedPath)
        } else {
            return openTerminalApp(at: expandedPath)
        }
    }

    /// Opens Terminal.app at the given directory.
    private func openTerminalApp(at path: String) -> SessionActionResult {
        let script = """
            tell application "Terminal"
                activate
                do script "cd \(shellEscape(path))"
            end tell
        """
        var error: NSDictionary?
        if let appleScript = NSAppleScript(source: script) {
            appleScript.executeAndReturnError(&error)
            if let error = error {
                return .failure(.commandFailed("Terminal.app script error: \(error)"))
            }
            return .success
        }
        return .failure(.commandFailed("Failed to create AppleScript for Terminal.app"))
    }

    /// Opens the session transcript file.
    private func openTranscript(for session: Session) -> SessionActionResult {
        // Claude Code stores transcripts in ~/.claude/projects/<project-hash>/sessions/<session-id>/
        // Try the common transcript locations
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        let possiblePaths = [
            "\(homeDir)/.claude/projects/\(session.sessionId)/transcript.md",
            "\(homeDir)/.claude/projects/\(session.sessionId)/transcript.json",
            "\(homeDir)/.claude/sessions/\(session.sessionId)/transcript.md",
            "\(homeDir)/.claude/sessions/\(session.sessionId)/transcript.json",
        ]

        for path in possiblePaths {
            if FileManager.default.fileExists(atPath: path) {
                NSWorkspace.shared.open(URL(fileURLWithPath: path))
                return .success
            }
        }

        return .failure(.transcriptNotFound(
            "No transcript found for session \(session.sessionId). Looked in ~/.claude/projects/ and ~/.claude/sessions/."
        ))
    }

    /// Copies the session ID to the system clipboard.
    private func copySessionId(_ sessionId: String) -> SessionActionResult {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(sessionId, forType: .string)
        return .success
    }

    /// Runs the custom shell command with variable substitution.
    private func runCustomCommand(for session: Session) -> SessionActionResult {
        let template = customCommandTemplate
        let command = substituteVariables(in: template, session: session)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", command]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()

            if process.terminationStatus != 0 {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? "Unknown error"
                return .failure(.commandFailed("Exit code \(process.terminationStatus): \(output)"))
            }
            return .success
        } catch {
            return .failure(.commandFailed(error.localizedDescription))
        }
    }

    /// Sends a macOS notification with session details.
    private func sendNotification(for session: Session) -> SessionActionResult {
        let content = UNMutableNotificationContent()
        content.title = "Whippet: \(session.projectName)"
        content.body = "Session: \(session.sessionId)\nModel: \(session.model)\nStatus: \(session.status.rawValue)"
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "whippet-click-\(session.sessionId)-\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil
        )

        let semaphore = DispatchSemaphore(value: 0)
        var deliveryError: Error?

        UNUserNotificationCenter.current().add(request) { error in
            deliveryError = error
            semaphore.signal()
        }

        semaphore.wait()

        if let error = deliveryError {
            return .failure(.notificationFailed(error.localizedDescription))
        }
        return .success
    }

    // MARK: - Helpers

    /// Substitutes `$SESSION_ID`, `$CWD`, and `$MODEL` in a command template.
    func substituteVariables(in template: String, session: Session) -> String {
        var result = template
        result = result.replacingOccurrences(of: "$SESSION_ID", with: session.sessionId)
        result = result.replacingOccurrences(of: "$CWD", with: session.cwd)
        result = result.replacingOccurrences(of: "$MODEL", with: session.model)
        return result
    }

    /// Escapes a string for safe use inside a single-quoted shell argument within AppleScript.
    private func shellEscape(_ string: String) -> String {
        // For AppleScript's "do script" we need to escape backslashes and double quotes
        return string
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
