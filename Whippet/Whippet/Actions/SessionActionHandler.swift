import AppKit
import UserNotifications

/// The System Settings pane to open when guiding the user to fix a permission.
enum PermissionPane: String {
    case accessibility = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
    case automation = "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation"
    case notifications = "x-apple.systempreferences:com.apple.preference.security?Privacy_Notifications"

    var displayName: String {
        switch self {
        case .accessibility: return "Accessibility"
        case .automation: return "Automation"
        case .notifications: return "Notifications"
        }
    }

    func open() {
        if let url = URL(string: rawValue) {
            NSWorkspace.shared.open(url)
        }
    }
}

/// Errors that can occur when executing a session click action.
enum SessionActionError: Error, LocalizedError {
    case directoryNotFound(String)
    case transcriptNotFound(String)
    case commandFailed(String)
    case notificationFailed(String)
    case noActionConfigured
    case permissionDenied(String, pane: PermissionPane)

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
        case .permissionDenied(let message, _):
            return message
        }
    }

    /// If this is a permission error, returns the pane the user should open.
    var permissionPane: PermissionPane? {
        if case .permissionDenied(_, let pane) = self { return pane }
        return nil
    }
}

/// Result of executing a session click action.
enum SessionActionResult {
    case success
    case failure(SessionActionError)
}

/// Handles execution of session click actions.
final class SessionActionHandler {

    // MARK: - Settings Keys

    static let clickActionKey = "click_action"
    static let customCommandKey = "custom_command_template"

    // MARK: - Properties

    private let databaseManager: DatabaseManager

    // MARK: - Initialization

    init(databaseManager: DatabaseManager) {
        self.databaseManager = databaseManager
    }

    // MARK: - Configuration

    var currentAction: SessionClickAction {
        guard let value = try? databaseManager.getSetting(key: Self.clickActionKey),
              let action = SessionClickAction(rawValue: value) else {
            return .openTerminal
        }
        return action
    }

    func setAction(_ action: SessionClickAction) throws {
        try databaseManager.setSetting(key: Self.clickActionKey, value: action.rawValue)
    }

    var customCommandTemplate: String {
        (try? databaseManager.getSetting(key: Self.customCommandKey)) ?? "echo $SESSION_ID $CWD $MODEL"
    }

    func setCustomCommandTemplate(_ template: String) throws {
        try databaseManager.setSetting(key: Self.customCommandKey, value: template)
    }

    // MARK: - Execution

    @discardableResult
    func execute(for session: Session) -> SessionActionResult {
        let action = currentAction
        Log.actions.info("Session clicked: \(session.sessionId, privacy: .public) project=\(session.projectName, privacy: .public) cwd=\(session.cwd, privacy: .public) action=\(action.rawValue, privacy: .public)")
        return execute(action: action, for: session)
    }

    @discardableResult
    func execute(action: SessionClickAction, for session: Session) -> SessionActionResult {
        Log.actions.info("Executing action '\(action.rawValue, privacy: .public)' for session \(session.sessionId, privacy: .public)")
        let result: SessionActionResult
        switch action {
        case .openTerminal:
            result = openTerminal(at: session.cwd)
        case .activateWarp:
            result = activateWarpSession(for: session)
        case .activateWindow:
            result = activateMatchingWindow(for: session)
        case .openTranscript:
            result = openTranscript(for: session)
        case .copySessionId:
            result = copySessionId(session.sessionId)
        case .customCommand:
            result = runCustomCommand(for: session)
        case .sendNotification:
            result = sendNotification(for: session)
        }

        switch result {
        case .success:
            Log.actions.info("Action '\(action.rawValue, privacy: .public)' succeeded")
        case .failure(let error):
            Log.actions.error("Action '\(action.rawValue, privacy: .public)' failed: \(error.localizedDescription, privacy: .public)")
        }
        return result
    }

    // MARK: - Open Terminal

    private func openTerminal(at path: String) -> SessionActionResult {
        Log.actions.debug("openTerminal: path='\(path, privacy: .public)'")
        guard !path.isEmpty else {
            Log.actions.warning("openTerminal: empty path")
            return .failure(.directoryNotFound(""))
        }

        let expandedPath = (path as NSString).expandingTildeInPath
        Log.actions.debug("openTerminal: expandedPath='\(expandedPath, privacy: .public)'")
        guard FileManager.default.fileExists(atPath: expandedPath) else {
            Log.actions.warning("openTerminal: directory does not exist")
            return .failure(.directoryNotFound(expandedPath))
        }

        if NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.googlecode.iterm2") != nil {
            Log.actions.debug("openTerminal: using iTerm2")
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
                    Log.actions.warning("openTerminal: iTerm2 error: \(String(describing: error), privacy: .public)")
                    if let permError = appleScriptPermissionError(error, appName: "iTerm2") {
                        return .failure(permError)
                    }
                    return openTerminalApp(at: expandedPath)
                }
                return .success
            }
            return openTerminalApp(at: expandedPath)
        } else {
            Log.actions.debug("openTerminal: using Terminal.app")
            return openTerminalApp(at: expandedPath)
        }
    }

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
                if let permError = appleScriptPermissionError(error, appName: "Terminal") {
                    return .failure(permError)
                }
                return .failure(.commandFailed("Terminal.app script error: \(error)"))
            }
            return .success
        }
        return .failure(.commandFailed("Failed to create AppleScript for Terminal.app"))
    }

    // MARK: - Activate Warp Session

    private func activateWarpSession(for session: Session) -> SessionActionResult {
        Log.actions.info("activateWarp: cwd='\(session.cwd, privacy: .public)' project='\(session.projectName, privacy: .public)'")

        guard !session.cwd.isEmpty else {
            Log.actions.warning("activateWarp: empty cwd")
            return .failure(.directoryNotFound(""))
        }

        // Check Warp is running
        let warpApps = NSRunningApplication.runningApplications(withBundleIdentifier: "dev.warp.Warp-Stable")
        Log.actions.info("activateWarp: found \(warpApps.count) running Warp instance(s)")
        guard let warpApp = warpApps.first else {
            Log.actions.warning("activateWarp: Warp is not running")
            return .failure(.commandFailed("Warp is not running"))
        }

        let warpPID = warpApp.processIdentifier
        Log.actions.debug("activateWarp: Warp PID=\(warpPID)")

        let expandedCwd = (session.cwd as NSString).expandingTildeInPath
        let projectName = session.projectName
        Log.actions.debug("activateWarp: looking for window matching project='\(projectName, privacy: .public)' or cwd='\(expandedCwd, privacy: .public)'")

        // Strategy 1: Use CGWindowList to find Warp windows and match by title
        guard let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            Log.actions.error("activateWarp: CGWindowListCopyWindowInfo returned nil")
            return .failure(.commandFailed("Unable to read window list"))
        }

        var warpWindows: [(name: String, number: Int, layer: Int)] = []
        for entry in windowList {
            guard let ownerPID = entry[kCGWindowOwnerPID as String] as? pid_t,
                  ownerPID == warpPID else { continue }

            let name = entry[kCGWindowName as String] as? String ?? "<no title>"
            let number = entry[kCGWindowNumber as String] as? Int ?? -1
            let layer = entry[kCGWindowLayer as String] as? Int ?? -1
            warpWindows.append((name: name, number: number, layer: layer))
            Log.actions.debug("activateWarp: Warp window #\(number) layer=\(layer) title='\(name, privacy: .public)'")
        }

        Log.actions.info("activateWarp: found \(warpWindows.count) Warp window(s) on screen")

        if warpWindows.isEmpty {
            // Warp is running but no on-screen windows — just activate it
            Log.actions.info("activateWarp: no on-screen windows, just activating Warp")
            warpApp.activate()
            return .success
        }

        // Try to find a matching window by title
        // Warp window titles typically show: "projectName — command" or the cwd path
        let matchCandidates = [projectName, expandedCwd, (expandedCwd as NSString).lastPathComponent]
        Log.actions.debug("activateWarp: match candidates: \(matchCandidates, privacy: .public)")

        var bestMatch: (name: String, number: Int)? = nil
        for candidate in matchCandidates {
            guard !candidate.isEmpty else { continue }
            for w in warpWindows where w.layer == 0 { // layer 0 = normal windows
                if w.name.localizedCaseInsensitiveContains(candidate) {
                    Log.actions.info("activateWarp: matched window #\(w.number) title='\(w.name, privacy: .public)' via candidate='\(candidate, privacy: .public)'")
                    bestMatch = (name: w.name, number: w.number)
                    break
                }
            }
            if bestMatch != nil { break }
        }

        // Strategy 2: Use Accessibility API to find and raise the matching window
        Log.actions.debug("activateWarp: querying Accessibility API for Warp windows")
        let axApp = AXUIElementCreateApplication(warpPID)
        var axWindowsRef: CFTypeRef?
        let axResult = AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &axWindowsRef)

        if axResult != .success {
            Log.actions.warning("activateWarp: AXUIElementCopyAttributeValue failed with \(axResult.rawValue)")
            if axResult == .apiDisabled || axResult == .notImplemented {
                Log.actions.error("activateWarp: Accessibility permission not granted")
                return .failure(.permissionDenied(
                    "Whippet needs Accessibility access to raise Warp windows. Grant access in System Settings.",
                    pane: .accessibility
                ))
            }
        }

        let axWindows = (axWindowsRef as? [AXUIElement]) ?? []
        Log.actions.debug("activateWarp: Accessibility found \(axWindows.count) window(s)")

        for (i, window) in axWindows.enumerated() {
            var titleRef: CFTypeRef?
            AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleRef)
            let axTitle = titleRef as? String ?? "<no title>"
            Log.actions.debug("activateWarp: AX window[\(i)] title='\(axTitle, privacy: .public)'")
        }

        // Activate Warp first
        Log.actions.debug("activateWarp: activating Warp app")
        warpApp.activate()

        if let match = bestMatch {
            // Raise the specific window via Accessibility
            Log.actions.info("activateWarp: raising matched window '\(match.name, privacy: .public)'")
            for window in axWindows {
                var titleRef: CFTypeRef?
                AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleRef)
                if let title = titleRef as? String, title == match.name {
                    let raiseResult = AXUIElementPerformAction(window, kAXRaiseAction as CFString)
                    Log.actions.debug("activateWarp: AXRaise result=\(raiseResult.rawValue)")
                    return .success
                }
            }
            // Couldn't raise via AX but we matched — Warp is activated at least
            Log.actions.info("activateWarp: could not raise via AX, but Warp is now frontmost")
            return .success
        }

        // No title match — fall back to raising the first normal-layer window
        if let firstNormal = warpWindows.first(where: { $0.layer == 0 }) {
            Log.actions.info("activateWarp: no title match, raising first window '\(firstNormal.name, privacy: .public)'")
            for window in axWindows {
                var titleRef: CFTypeRef?
                AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleRef)
                if let title = titleRef as? String, title == firstNormal.name {
                    AXUIElementPerformAction(window, kAXRaiseAction as CFString)
                    return .success
                }
            }
        }

        Log.actions.info("activateWarp: no match found, Warp activated without specific window")
        return .success
    }

    // MARK: - Activate Matching Window (any app)

    private func activateMatchingWindow(for session: Session) -> SessionActionResult {
        let projectName = session.projectName
        Log.actions.info("activateWindow: looking for window matching '\(projectName, privacy: .public)'")

        guard projectName != "Unknown" else {
            Log.actions.warning("activateWindow: no project name (empty cwd)")
            return .failure(.commandFailed("No project name to match — session has no working directory"))
        }

        guard let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            Log.actions.error("activateWindow: CGWindowListCopyWindowInfo returned nil")
            return .failure(.commandFailed("Unable to read window list"))
        }

        Log.actions.debug("activateWindow: scanning \(windowList.count) windows")

        for entry in windowList {
            guard let ownerPID = entry[kCGWindowOwnerPID as String] as? pid_t,
                  let windowName = entry[kCGWindowName as String] as? String,
                  !windowName.isEmpty else {
                continue
            }

            let ownerName = entry[kCGWindowOwnerName as String] as? String ?? "?"
            let layer = entry[kCGWindowLayer as String] as? Int ?? -1

            if windowName.localizedCaseInsensitiveContains(projectName) && layer == 0 {
                Log.actions.info("activateWindow: matched '\(windowName, privacy: .public)' in \(ownerName, privacy: .public) (PID \(ownerPID))")

                if let app = NSRunningApplication(processIdentifier: ownerPID) {
                    app.activate()
                    raiseWindow(pid: ownerPID, windowName: windowName)
                    return .success
                }
            }
        }

        Log.actions.info("activateWindow: no window found matching '\(projectName, privacy: .public)'")
        return .failure(.commandFailed("No window found matching \"\(projectName)\""))
    }

    private func raiseWindow(pid: pid_t, windowName: String) {
        let appElement = AXUIElementCreateApplication(pid)
        var windowsRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef)
        guard result == .success, let windows = windowsRef as? [AXUIElement] else {
            Log.actions.debug("raiseWindow: AX query failed (\(result.rawValue)) for PID \(pid)")
            return
        }

        for window in windows {
            var titleRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleRef) == .success,
               let title = titleRef as? String,
               title == windowName {
                let raiseResult = AXUIElementPerformAction(window, kAXRaiseAction as CFString)
                Log.actions.debug("raiseWindow: raised '\(windowName, privacy: .public)' result=\(raiseResult.rawValue)")
                return
            }
        }
        Log.actions.debug("raiseWindow: no AX window matched '\(windowName, privacy: .public)'")
    }

    // MARK: - Open Transcript

    private func openTranscript(for session: Session) -> SessionActionResult {
        Log.actions.debug("openTranscript: sessionId=\(session.sessionId, privacy: .public)")
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        let possiblePaths = [
            "\(homeDir)/.claude/projects/\(session.sessionId)/transcript.md",
            "\(homeDir)/.claude/projects/\(session.sessionId)/transcript.json",
            "\(homeDir)/.claude/sessions/\(session.sessionId)/transcript.md",
            "\(homeDir)/.claude/sessions/\(session.sessionId)/transcript.json",
        ]

        for path in possiblePaths {
            if FileManager.default.fileExists(atPath: path) {
                Log.actions.info("openTranscript: found at \(path, privacy: .public)")
                NSWorkspace.shared.open(URL(fileURLWithPath: path))
                return .success
            }
        }

        Log.actions.info("openTranscript: not found in any location")
        return .failure(.transcriptNotFound(
            "No transcript found for session \(session.sessionId). Looked in ~/.claude/projects/ and ~/.claude/sessions/."
        ))
    }

    // MARK: - Copy Session ID

    private func copySessionId(_ sessionId: String) -> SessionActionResult {
        Log.actions.debug("copySessionId: \(sessionId, privacy: .public)")
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(sessionId, forType: .string)
        return .success
    }

    // MARK: - Custom Command

    private func runCustomCommand(for session: Session) -> SessionActionResult {
        let template = customCommandTemplate
        let command = substituteVariables(in: template, session: session)
        Log.actions.info("runCustomCommand: template='\(template, privacy: .public)' expanded='\(command, privacy: .public)'")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", command]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            DispatchQueue.global(qos: .userInitiated).async {
                process.waitUntilExit()
                if process.terminationStatus != 0 {
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    let output = String(data: data, encoding: .utf8) ?? "Unknown error"
                    Log.actions.error("Custom command failed (exit \(process.terminationStatus)): \(output, privacy: .public)")
                } else {
                    Log.actions.debug("Custom command completed successfully")
                }
            }
            return .success
        } catch {
            Log.actions.error("Custom command launch failed: \(error.localizedDescription, privacy: .public)")
            return .failure(.commandFailed(error.localizedDescription))
        }
    }

    // MARK: - Send Notification

    private func sendNotification(for session: Session) -> SessionActionResult {
        Log.actions.debug("sendNotification: \(session.projectName, privacy: .public)")
        let content = UNMutableNotificationContent()
        content.title = "Whippet: \(session.projectName)"
        content.body = "Session: \(session.sessionId)\nModel: \(session.model)\nStatus: \(session.status.rawValue)"
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "whippet-click-\(session.sessionId)-\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                Log.actions.error("Notification delivery failed: \(error.localizedDescription, privacy: .public)")
            }
        }

        return .success
    }

    // MARK: - Helpers

    func substituteVariables(in template: String, session: Session) -> String {
        var result = template
        result = result.replacingOccurrences(of: "$SESSION_ID", with: posixShellEscape(session.sessionId))
        result = result.replacingOccurrences(of: "$CWD", with: posixShellEscape(session.cwd))
        result = result.replacingOccurrences(of: "$MODEL", with: posixShellEscape(session.model))
        return result
    }

    private func posixShellEscape(_ string: String) -> String {
        return "'" + string.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private func shellEscape(_ string: String) -> String {
        var escaped = string
        escaped = escaped.replacingOccurrences(of: "\\", with: "\\\\")
        escaped = escaped.replacingOccurrences(of: "\"", with: "\\\"")
        escaped = escaped.filter { !$0.isNewline && $0 != "\r" && $0 != "\0" }
        return escaped
    }

    /// Checks an AppleScript error dictionary for authorization/permission failures.
    /// Returns a `.permissionDenied` error if detected, nil otherwise.
    private func appleScriptPermissionError(_ error: NSDictionary, appName: String) -> SessionActionError? {
        let errorNumber = error[NSAppleScript.errorNumber] as? Int
        let errorMessage = error[NSAppleScript.errorMessage] as? String ?? ""

        // -1743 = "Not authorized to send Apple events"
        // -1744 = "A privilege violation occurred"
        if errorNumber == -1743 || errorNumber == -1744
            || errorMessage.localizedCaseInsensitiveContains("not authorized")
            || errorMessage.localizedCaseInsensitiveContains("privilege violation") {
            Log.actions.error("AppleScript permission denied for \(appName, privacy: .public): \(errorMessage, privacy: .public)")
            return .permissionDenied(
                "Whippet needs permission to control \(appName). Grant access in System Settings > Privacy & Security > Automation.",
                pane: .automation
            )
        }
        return nil
    }
}
