import Foundation
import Combine

/// Groups sessions by project name (derived from the working directory).
struct SessionGroup: Identifiable {
    let id: String  // project name
    let projectName: String
    let sessions: [Session]

    /// Whether any session in this group is active.
    var hasActiveSessions: Bool {
        sessions.contains { $0.status == .active }
    }
}

/// Bridges SQLite session data to SwiftUI views with real-time update support.
///
/// Uses `ObservableObject` with `@Published` properties so SwiftUI views
/// automatically re-render when sessions change. Listens for ingestion
/// notifications to refresh data from the database.
final class SessionListViewModel: ObservableObject {

    // MARK: - Published Properties

    /// All sessions grouped by project, sorted by most recent activity.
    @Published private(set) var groups: [SessionGroup] = []

    /// Whether the session list is empty.
    @Published private(set) var isEmpty: Bool = true

    /// The total number of sessions.
    @Published private(set) var sessionCount: Int = 0

    /// The number of active sessions.
    @Published private(set) var activeSessionCount: Int = 0

    // MARK: - Properties

    private let databaseManager: DatabaseManager
    private var refreshTimer: Timer?

    /// The action handler for session click actions.
    let actionHandler: SessionActionHandler

    /// The last error message from a click action, shown briefly in the UI.
    @Published var lastActionError: String?

    /// Notification name posted when new events are ingested.
    static let sessionsDidChangeNotification = Notification.Name("WhippetSessionsDidChange")

    // MARK: - Initialization

    /// Creates a view model that reads sessions from the given database manager.
    /// - Parameter databaseManager: The database manager to query for sessions.
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

    /// Loads all sessions from the database and groups them by project.
    func loadSessions() {
        do {
            let allSessions = try databaseManager.fetchAllSessions()
            let grouped = groupSessionsByProject(allSessions)

            // Sort groups: groups with active sessions first, then by most recent activity
            let sortedGroups = grouped.sorted { lhs, rhs in
                if lhs.hasActiveSessions != rhs.hasActiveSessions {
                    return lhs.hasActiveSessions
                }
                let lhsLatest = lhs.sessions.first?.lastActivityAt ?? ""
                let rhsLatest = rhs.sessions.first?.lastActivityAt ?? ""
                return lhsLatest > rhsLatest
            }

            // Update on main thread for SwiftUI
            if Thread.isMainThread {
                self.groups = sortedGroups
                self.isEmpty = allSessions.isEmpty
                self.sessionCount = allSessions.count
                self.activeSessionCount = allSessions.filter { $0.status == .active }.count
            } else {
                DispatchQueue.main.async { [weak self] in
                    self?.groups = sortedGroups
                    self?.isEmpty = allSessions.isEmpty
                    self?.sessionCount = allSessions.count
                    self?.activeSessionCount = allSessions.filter { $0.status == .active }.count
                }
            }
        } catch {
            NSLog("Whippet: Failed to load sessions: \(error.localizedDescription)")
        }
    }

    /// Groups sessions by their project name (derived from working directory).
    private func groupSessionsByProject(_ sessions: [Session]) -> [SessionGroup] {
        let grouped = Dictionary(grouping: sessions) { $0.projectName }
        return grouped.map { projectName, sessions in
            SessionGroup(
                id: projectName,
                projectName: projectName,
                sessions: sessions.sorted { $0.lastActivityAt > $1.lastActivityAt }
            )
        }
    }

    // MARK: - Real-time Updates

    /// Starts listening for session change notifications from the ingestion layer.
    private func startListening() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSessionsDidChange),
            name: Self.sessionsDidChangeNotification,
            object: nil
        )
    }

    /// Stops listening for notifications.
    func stopListening() {
        NotificationCenter.default.removeObserver(self)
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    @objc private func handleSessionsDidChange() {
        loadSessions()
    }

    /// Posts a notification that sessions have changed.
    /// Call this from the ingestion layer after processing new events.
    static func notifySessionsChanged() {
        NotificationCenter.default.post(
            name: sessionsDidChangeNotification,
            object: nil
        )
    }

    // MARK: - Click Actions

    /// Handles a click on a session row by executing the configured action.
    /// - Parameter session: The session that was clicked.
    func handleSessionClick(_ session: Session) {
        let result = actionHandler.execute(for: session)
        switch result {
        case .success:
            lastActionError = nil
        case .failure(let error):
            lastActionError = error.localizedDescription
            NSLog("Whippet: Click action failed: \(error.localizedDescription)")

            // Clear the error after a delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
                self?.lastActionError = nil
            }
        }
    }
}
