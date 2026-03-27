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

    /// Callback invoked for each session whose originating process has died,
    /// providing session ID and project name. Used for end-of-session notifications.
    var onSessionProcessDied: ((_ sessionId: String, _ projectName: String) -> Void)?

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

        Log.liveness.info("Started (check interval: \(Self.checkInterval)s, timeout: \(self.currentTimeout())s)")
    }

    /// Stops the repeating liveness check timer.
    func stop() {
        timer?.cancel()
        timer = nil
        isRunning = false
        Log.liveness.info("Stopped")
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
            Log.liveness.warning("Failed to read staleness timeout setting: \(error.localizedDescription, privacy: .public)")
        }
        return Self.defaultTimeoutSeconds
    }

    /// Checks all active sessions and marks those that exceed the timeout as stale.
    /// Also checks if the originating process for each session is still alive.
    /// Posts a sessions-changed notification if any sessions were updated.
    func performLivenessCheck() {
        // Phase 1: PID-based dead session detection (fast, single syscall per session)
        let pidDeathCount = performPidLivenessCheck()

        // Phase 2: Timeout-based staleness detection (fallback for sessions without PID)
        let timeout = currentTimeout()

        do {
            // Capture sessions that are about to go stale (for per-session callbacks)
            let aboutToGoStale = try databaseManager.fetchActiveSessionsPastTimeout(timeout)

            let count = try databaseManager.markStaleSessions(olderThan: timeout)
            if count > 0 {
                Log.liveness.info("Marked \(count) session(s) as stale (timeout: \(timeout)s)")
                onSessionsMarkedStale?(count)

                // Notify per-session callback for notifications
                for session in aboutToGoStale {
                    onSessionMarkedStale?(session.sessionId, session.projectName)
                }
            }

            if count > 0 || pidDeathCount > 0 {
                DispatchQueue.main.async {
                    SessionListViewModel.notifySessionsChanged()
                }
            }
        } catch {
            Log.liveness.error("Liveness check failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Checks if the originating process for each tracked session is still alive.
    /// Returns the number of sessions marked as ended.
    @discardableResult
    private func performPidLivenessCheck() -> Int {
        do {
            let sessions = try databaseManager.fetchLiveSessionsWithPid()
            var endedCount = 0

            for session in sessions {
                if !isProcessAlive(pid: session.pid) {
                    try databaseManager.updateSessionStatus(
                        sessionId: session.sessionId,
                        status: .ended
                    )
                    onSessionProcessDied?(session.sessionId, session.projectName)
                    endedCount += 1
                    Log.liveness.info("Process \(session.pid) dead — ended session '\(session.projectName, privacy: .public)'")
                }
            }

            if endedCount > 0 {
                Log.liveness.info("Ended \(endedCount) session(s) via PID liveness check")
            }

            return endedCount
        } catch {
            Log.liveness.error("PID liveness check failed: \(error.localizedDescription, privacy: .public)")
            return 0
        }
    }

    /// Checks if a process with the given PID is currently running.
    /// Uses the POSIX kill(2) system call with signal 0 (no signal sent).
    private func isProcessAlive(pid: Int32) -> Bool {
        guard pid > 0 else { return false }
        return kill(pid, 0) == 0
    }
}
