import Foundation

/// Monitors active sessions and marks them as stale when no events arrive
/// within the configured timeout period. Runs a repeating timer on a background
/// queue to avoid blocking the main thread.
///
/// The default staleness timeout is 60 seconds. This can be overridden by setting
/// the `staleness_timeout` key in the SQLite `settings` table (value in seconds).
final class SessionLivenessMonitor {

    // MARK: - Constants

    /// Settings key for the staleness timeout (in seconds).
    static let stalenessTimeoutKey = "staleness_timeout"

    /// Default staleness timeout: 60 seconds.
    static let defaultTimeoutSeconds: TimeInterval = 60

    /// How often the liveness check runs (in seconds).
    static let checkInterval: TimeInterval = 10

    // MARK: - Properties

    private let databaseManager: DatabaseManager
    private var timer: DispatchSourceTimer?
    private let queue = DispatchQueue(
        label: "com.mikefullerton.whippet.liveness",
        qos: .utility
    )

    /// Whether the monitor is currently running.
    private(set) var isRunning = false

    /// Callback invoked when sessions are marked stale. Called on the liveness queue.
    var onSessionsMarkedStale: ((Int) -> Void)?

    /// Callback invoked for each session that was just marked stale, providing session ID
    /// and project name. Used by NotificationManager to fire per-session stale notifications.
    var onSessionMarkedStale: ((_ sessionId: String, _ projectName: String) -> Void)?

    // MARK: - Initialization

    /// Creates a liveness monitor that uses the given database manager.
    /// - Parameter databaseManager: The database manager for querying and updating sessions.
    init(databaseManager: DatabaseManager) {
        self.databaseManager = databaseManager
    }

    deinit {
        stop()
    }

    // MARK: - Start / Stop

    /// Starts the repeating liveness check timer.
    func start() {
        guard !isRunning else { return }

        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(
            deadline: .now() + Self.checkInterval,
            repeating: Self.checkInterval
        )
        timer.setEventHandler { [weak self] in
            self?.performLivenessCheck()
        }

        self.timer = timer
        timer.resume()
        isRunning = true

        NSLog("Whippet: SessionLivenessMonitor started (check interval: \(Self.checkInterval)s)")
    }

    /// Stops the repeating liveness check timer.
    func stop() {
        timer?.cancel()
        timer = nil
        isRunning = false
    }

    // MARK: - Liveness Check

    /// Reads the staleness timeout from settings, falling back to the default.
    func currentTimeout() -> TimeInterval {
        do {
            if let value = try databaseManager.getSetting(key: Self.stalenessTimeoutKey),
               let seconds = TimeInterval(value), seconds > 0 {
                return seconds
            }
        } catch {
            NSLog("Whippet: Failed to read staleness timeout setting: \(error.localizedDescription)")
        }
        return Self.defaultTimeoutSeconds
    }

    /// Checks all active sessions and marks those that exceed the timeout as stale.
    /// Posts a sessions-changed notification if any sessions were updated.
    func performLivenessCheck() {
        let timeout = currentTimeout()

        do {
            // Capture sessions that are about to go stale (for per-session callbacks)
            let aboutToGoStale = try databaseManager.fetchActiveSessionsPastTimeout(timeout)

            let count = try databaseManager.markStaleSessions(olderThan: timeout)
            if count > 0 {
                NSLog("Whippet: Marked \(count) session(s) as stale (timeout: \(timeout)s)")
                onSessionsMarkedStale?(count)

                // Notify per-session callback for notifications
                for session in aboutToGoStale {
                    onSessionMarkedStale?(session.sessionId, session.projectName)
                }

                DispatchQueue.main.async {
                    SessionListViewModel.notifySessionsChanged()
                }
            }
        } catch {
            NSLog("Whippet: Liveness check failed: \(error.localizedDescription)")
        }
    }
}
