import Foundation
import Combine

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

    // MARK: - Properties

    private let databaseManager: DatabaseManager
    private var refreshTimer: Timer?

    /// Project names we've ever seen — kept across reloads so groups don't disappear.
    private var knownProjects: Set<String> = []

    /// The action handler for session click actions.
    let actionHandler: SessionActionHandler

    /// The last error message from a click action, shown briefly in the UI.
    @Published var lastActionError: String?

    /// If the last error was a permission issue, the Settings pane the user should open.
    @Published var lastPermissionPane: PermissionPane?

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

            // Build groups for ALL known projects, sorted alphabetically
            let sortedGroups = knownProjects.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
                .map { name -> SessionGroup in
                    let sessions = sessionsByProject[name] ?? []
                    let path: String = {
                        guard let cwd = (sessions.first ?? allSessions.first(where: { $0.projectName == name }))?.cwd,
                              !cwd.isEmpty else { return "" }
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
    }

    func stopListening() {
        NotificationCenter.default.removeObserver(self)
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    @objc private func handleSessionsDidChange() {
        loadSessions()
    }

    static func notifySessionsChanged() {
        NotificationCenter.default.post(
            name: sessionsDidChangeNotification,
            object: nil
        )
    }

    // MARK: - Click Actions

    func handleSessionClick(_ session: Session) {
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
}
