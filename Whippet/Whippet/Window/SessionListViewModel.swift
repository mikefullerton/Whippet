import AppKit
import ApplicationServices
import Combine
import Foundation

/// Groups sessions by project name (derived from the working directory).
struct SessionGroup: Identifiable {
    let id: String  // project name
    let projectName: String
    let sessions: [Session]
    let abbreviatedPath: String

    /// Whether any session in this group is active.
    var hasActiveSessions: Bool {
        sessions.contains { $0.status == .active }
    }

    /// Whether any session in this group is stale (but not active).
    var hasStaleSessions: Bool {
        !hasActiveSessions && sessions.contains { $0.status == .stale }
    }
}

/// Bridges SQLite session data to SwiftUI views with real-time update support.
///
/// Projects are "sticky" — once a project appears, it stays in the list even when
/// all its sessions end, showing "None" instead. Groups are sorted alphabetically.
final class SessionListViewModel: ObservableObject {

    // MARK: - Published Properties

    /// All sessions grouped by project, sorted alphabetically.
    @Published private(set) var groups: [SessionGroup] = []

    /// Whether there are zero known projects (true only before any session is ever seen).
    @Published private(set) var isEmpty: Bool = true

    /// The total number of live (non-ended) sessions.
    @Published private(set) var sessionCount: Int = 0

    /// The number of active sessions.
    @Published private(set) var activeSessionCount: Int = 0

    /// Whether the app has accessibility permission.
    @Published private(set) var isAccessibilityTrusted: Bool = AXIsProcessTrusted()

    // MARK: - Properties

    private let databaseManager: DatabaseManager
    private var refreshTimer: Timer?
    private var accessibilityTimer: Timer?

    /// Project names we've ever seen — kept across reloads so groups don't disappear.
    private var knownProjects: Set<String> = []

    /// The action handler for session click actions.
    let actionHandler: SessionActionHandler

    /// The last error message from a click action, shown briefly in the UI.
    @Published var lastActionError: String?

    /// If the last error was a permission issue, the Settings pane the user should open.
    @Published var lastPermissionPane: PermissionPane?

    /// Called when the activateWindow action needs a discovery panel shown.
    var onWindowDiscoveryRequested: ((Session) -> Void)?

    /// The session summarizer for manual AI summarization.
    var sessionSummarizer: SessionSummarizer?

    /// Session IDs currently being summarized (for UI progress indication).
    @Published private(set) var summarizingSessionIds: Set<String> = []

    /// The session ID whose terminal window is currently frontmost, if any.
    @Published private(set) var frontmostSessionId: String?

    private var frontmostTimer: Timer?

    /// Notification name posted when new events are ingested.
    static let sessionsDidChangeNotification = Notification.Name("WhippetSessionsDidChange")

    // MARK: - Initialization

    init(databaseManager: DatabaseManager) {
        self.databaseManager = databaseManager
        self.actionHandler = SessionActionHandler(databaseManager: databaseManager)
        loadSessions()
        startListening()
    }

    deinit {
        stopListening()
    }

    // MARK: - Data Loading

    /// Loads active and stale sessions from the database and groups them by project.
    /// Ended sessions are excluded. Known projects are kept even if they have no sessions.
    func loadSessions() {
        do {
            let allSessions = try databaseManager.fetchAllSessions()
            let liveSessions = allSessions.filter { $0.status != .ended }

            // Group live sessions by project
            let sessionsByProject = Dictionary(grouping: liveSessions) { $0.projectName }

            // Add any new project names to the sticky set
            for name in sessionsByProject.keys {
                knownProjects.insert(name)
            }
            // Also add projects from ended sessions so they appear immediately
            for session in allSessions where !session.projectName.isEmpty && session.projectName != "Unknown" {
                knownProjects.insert(session.projectName)
            }

            // Build groups only for projects that have live sessions
            let sortedGroups = knownProjects.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
                .compactMap { name -> SessionGroup? in
                    let sessions = sessionsByProject[name] ?? []
                    guard !sessions.isEmpty else { return nil }
                    let path: String = {
                        guard let cwd = sessions.first?.cwd, !cwd.isEmpty else { return "" }
                        let home = FileManager.default.homeDirectoryForCurrentUser.path
                        return cwd.hasPrefix(home) ? "~" + cwd.dropFirst(home.count) : cwd
                    }()
                    return SessionGroup(
                        id: name,
                        projectName: name,
                        sessions: sessions.sorted { $0.lastActivityAt > $1.lastActivityAt },
                        abbreviatedPath: path
                    )
                }

            let count = liveSessions.count
            let activeCount = liveSessions.filter { $0.status == .active }.count
            let empty = knownProjects.isEmpty

            if Thread.isMainThread {
                self.groups = sortedGroups
                self.isEmpty = empty
                self.sessionCount = count
                self.activeSessionCount = activeCount
            } else {
                DispatchQueue.main.async { [weak self] in
                    self?.groups = sortedGroups
                    self?.isEmpty = empty
                    self?.sessionCount = count
                    self?.activeSessionCount = activeCount
                }
            }
        } catch {
            Log.ui.error("Failed to load sessions: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Real-time Updates

    private func startListening() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSessionsDidChange),
            name: Self.sessionsDidChangeNotification,
            object: nil
        )

        // Re-check accessibility when the app comes to the foreground
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(checkAccessibility),
            name: NSApplication.didBecomeActiveNotification,
            object: nil
        )

        // Poll accessibility status every 2 seconds so the indicator updates
        // promptly after the user grants permission in System Settings.
        accessibilityTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.checkAccessibility()
        }

        // Poll the frontmost window to highlight the active session
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.updateFrontmostSession()
        }
        RunLoop.main.add(timer, forMode: .common)
        frontmostTimer = timer
    }

    func stopListening() {
        NotificationCenter.default.removeObserver(self)
        refreshTimer?.invalidate()
        refreshTimer = nil
        accessibilityTimer?.invalidate()
        accessibilityTimer = nil
        frontmostTimer?.invalidate()
        frontmostTimer = nil
    }

    @objc private func handleSessionsDidChange() {
        loadSessions()
    }

    @objc private func checkAccessibility() {
        let trusted = AXIsProcessTrusted()
        if trusted != isAccessibilityTrusted {
            Log.app.info("Accessibility status changed: \(trusted)")
            if Thread.isMainThread {
                isAccessibilityTrusted = trusted
            } else {
                DispatchQueue.main.async { [weak self] in
                    self?.isAccessibilityTrusted = trusted
                }
            }
        }
    }

    static func notifySessionsChanged() {
        NotificationCenter.default.post(
            name: sessionsDidChangeNotification,
            object: nil
        )
    }

    // MARK: - Click Actions

    func handleSessionClick(_ session: Session) {
        let action = actionHandler.currentAction
        let log = ActivationTestLog.shared

        // For window activation actions, try direct AX match first; show discovery panel if no match
        if action == .activateWindow || action == .activateWarp {
            let projectName = session.projectName
            log.append("Click: project=\"\(projectName)\" action=\(action.rawValue) cwd=\"\(session.cwd)\"")
            log.append("  Before: main=\"\(Self.frontmostWindowTitle())\"")

            let result = actionHandler.execute(action: .activateWindow, for: session)

            if case .success = result {
                log.append("  execute() returned success")
                lastActionError = nil
                lastPermissionPane = nil

                // Verify activation actually worked after Warp has time to process
                DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                    Thread.sleep(forTimeInterval: 0.5)
                    let mainTitle = Self.frontmostWindowTitle()
                    let verified = mainTitle.localizedCaseInsensitiveContains(projectName)
                    log.append("  After:  main=\"\(mainTitle)\" verified=\(verified)")
                    DispatchQueue.main.async {
                        if !verified {
                            self?.lastActionError = "Activation failed: main=\"\(mainTitle)\", expected \"\(projectName)\""
                            DispatchQueue.main.asyncAfter(deadline: .now() + 6) { [weak self] in
                                if self?.lastActionError?.hasPrefix("Activation") == true {
                                    self?.lastActionError = nil
                                }
                            }
                        }
                    }
                }
                return
            }

            if case .failure(let error) = result {
                log.append("  execute() returned failure: \(error.localizedDescription)")
            }

            // No direct match — show the discovery panel so the user can pick
            log.append("  Falling back to discovery panel")
            onWindowDiscoveryRequested?(session)
            return
        }

        let result = actionHandler.execute(for: session)
        switch result {
        case .success:
            lastActionError = nil
            lastPermissionPane = nil
        case .failure(let error):
            lastActionError = error.localizedDescription
            lastPermissionPane = error.permissionPane
            Log.actions.warning("Click action failed for session \(session.sessionId, privacy: .public): \(error.localizedDescription, privacy: .public)")

            let delay: TimeInterval = error.permissionPane != nil ? 10 : 4
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.lastActionError = nil
                self?.lastPermissionPane = nil
            }
        }
    }

    func openPermissionSettings() {
        lastPermissionPane?.open()
    }

    // MARK: - Activation Test

    /// Tests window activation for each unique project by simulating a click
    /// and verifying the Warp main window switched. Runs on a background thread
    /// and reports results via lastActionError.
    func testActivation() {
        let log = ActivationTestLog.shared
        log.clear()
        log.append("=== Activation Test Started ===")
        log.append("Log file: \(ActivationTestLog.logPath)")

        // Gather unique project names from live sessions
        let projects: [(name: String, session: Session)] = groups.compactMap { group in
            guard let session = group.sessions.first else { return nil }
            return (group.projectName, session)
        }

        guard !projects.isEmpty else {
            log.append("ABORT: No sessions to test")
            lastActionError = "Test: No sessions to test"
            return
        }

        log.append("Projects to test: \(projects.map(\.name).joined(separator: ", "))")
        lastActionError = "Test: Running \(projects.count) activation test(s)..."

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            var passCount = 0
            var failCount = 0

            for (name, session) in projects {
                let before = Self.frontmostWindowTitle()
                log.append("--- Testing \"\(name)\" ---")
                log.append("  Before: main=\"\(before)\"")

                let result = self.actionHandler.execute(action: .activateWindow, for: session)
                if case .success = result {
                    log.append("  execute() returned: success")
                } else {
                    log.append("  execute() returned: failure")
                }

                Thread.sleep(forTimeInterval: 0.5)

                let after = Self.frontmostWindowTitle()
                log.append("  After:  main=\"\(after)\"")

                let passed: Bool
                if case .success = result {
                    passed = after.localizedCaseInsensitiveContains(name)
                } else {
                    passed = false
                }

                if passed {
                    log.append("  PASS")
                    passCount += 1
                } else {
                    log.append("  FAIL: expected title containing \"\(name)\", got \"\(after)\"")
                    failCount += 1
                }

                Thread.sleep(forTimeInterval: 0.5)
            }

            log.append("=== Results: \(passCount) passed, \(failCount) failed ===")

            DispatchQueue.main.async {
                NSApp.activate(ignoringOtherApps: true)
                self.lastActionError = "Test: \(passCount) passed, \(failCount) failed — see \(ActivationTestLog.logPath)"

                DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak self] in
                    if self?.lastActionError?.hasPrefix("Test:") == true {
                        self?.lastActionError = nil
                    }
                }
            }
        }
    }


    // MARK: - Frontmost Window Tracking

    /// Checks the system's frontmost window title and matches it to a session.
    private func updateFrontmostSession() {
        guard AXIsProcessTrusted() else { return }

        let title = Self.frontmostWindowTitle()
        guard !title.isEmpty else {
            if frontmostSessionId != nil { frontmostSessionId = nil }
            return
        }

        // Match against all live sessions by project name (case-insensitive substring)
        let allSessions = groups.flatMap(\.sessions)
        let matched = allSessions.first { session in
            let project = session.projectName
            guard !project.isEmpty, project != "Unknown" else { return false }
            return title.localizedCaseInsensitiveContains(project)
        }

        let newId = matched?.sessionId
        if newId != frontmostSessionId {
            frontmostSessionId = newId
        }
    }

    /// Returns the title of the frontmost application's main window.
    private static func frontmostWindowTitle() -> String {
        guard let frontApp = NSWorkspace.shared.frontmostApplication else { return "" }

        // Skip our own app
        if frontApp.bundleIdentifier == Bundle.main.bundleIdentifier { return "" }

        let axApp = AXUIElementCreateApplication(frontApp.processIdentifier)
        var windowRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, &windowRef)
        guard result == .success, let window = windowRef else { return "" }

        var titleRef: CFTypeRef?
        AXUIElementCopyAttributeValue(window as! AXUIElement, kAXTitleAttribute as CFString, &titleRef)
        return (titleRef as? String) ?? ""
    }

    // MARK: - AI Summarization

    /// Triggers AI summarization for a session. Guards against double-trigger.
    func summarizeSession(_ session: Session) {
        SummarizerDebugLog.shared.append("Manual summarize requested for \(session.sessionId)")
        guard let summarizer = sessionSummarizer else {
            SummarizerDebugLog.shared.append("sessionSummarizer is nil on SessionListViewModel!")
            return
        }
        guard !summarizingSessionIds.contains(session.sessionId) else {
            SummarizerDebugLog.shared.append("Already summarizing \(session.sessionId), skipping")
            return
        }

        summarizingSessionIds.insert(session.sessionId)

        Task.detached(priority: .userInitiated) { [weak self] in
            await summarizer.summarizeAndStore(sessionId: session.sessionId)
            await MainActor.run {
                self?.summarizingSessionIds.remove(session.sessionId)
                self?.loadSessions()
            }
        }
    }
}
