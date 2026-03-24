import Foundation
import UserNotifications

/// Protocol abstracting UNUserNotificationCenter for testability.
protocol NotificationCenterProtocol: AnyObject {
    var delegate: (any UNUserNotificationCenterDelegate)? { get set }
    func requestAuthorization(options: UNAuthorizationOptions, completionHandler: @escaping @Sendable (Bool, (any Error)?) -> Void)
    func getNotificationSettings(completionHandler: @escaping @Sendable (UNNotificationSettings) -> Void)
    func setNotificationCategories(_ categories: Set<UNNotificationCategory>)
    func add(_ request: UNNotificationRequest, withCompletionHandler completionHandler: (@Sendable ((any Error)?) -> Void)?)
}

/// Conform the real UNUserNotificationCenter to our protocol.
extension UNUserNotificationCenter: NotificationCenterProtocol {}

/// Manages macOS notifications for Whippet session events.
///
/// Responsibilities:
/// - Requests notification authorization on first launch
/// - Posts notifications for SessionStart, SessionEnd, and Stale events
/// - Respects per-event-type toggles from the settings database
/// - Handles notification click actions (brings floating window to front)
final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {

    // MARK: - Category Identifiers

    /// Notification category identifier for session events.
    static let sessionCategoryIdentifier = "WHIPPET_SESSION_EVENT"

    // MARK: - User Info Keys

    /// Key for the session ID in the notification's userInfo dictionary.
    static let sessionIdKey = "sessionId"

    /// Key for the event type in the notification's userInfo dictionary.
    static let eventTypeKey = "eventType"

    // MARK: - Properties

    private let databaseManager: DatabaseManager
    private let notificationCenter: NotificationCenterProtocol

    /// Whether the user has granted notification permission.
    private(set) var isAuthorized = false

    /// Callback invoked when the user taps a notification.
    /// The caller (AppDelegate) should bring the floating window to the front.
    var onNotificationClicked: (() -> Void)?

    // MARK: - Initialization

    /// Creates a NotificationManager.
    /// - Parameters:
    ///   - databaseManager: The database manager for reading notification settings.
    ///   - notificationCenter: The notification center to use. Defaults to `.current()`.
    init(databaseManager: DatabaseManager, notificationCenter: NotificationCenterProtocol? = nil) {
        self.databaseManager = databaseManager
        self.notificationCenter = notificationCenter ?? UNUserNotificationCenter.current()
        super.init()
        self.notificationCenter.delegate = self
        registerCategories()
    }

    // MARK: - Authorization

    /// Requests notification authorization with alert and sound options.
    /// Should be called once during app launch.
    func requestAuthorization() {
        notificationCenter.requestAuthorization(options: [.alert, .sound]) { [weak self] granted, error in
            self?.isAuthorized = granted
            if let error = error {
                NSLog("Whippet: Notification authorization error: \(error.localizedDescription)")
            } else {
                NSLog("Whippet: Notification authorization \(granted ? "granted" : "denied")")
            }
        }
    }

    /// Checks the current authorization status and updates `isAuthorized`.
    func checkAuthorization(completion: ((Bool) -> Void)? = nil) {
        notificationCenter.getNotificationSettings { [weak self] settings in
            let authorized = settings.authorizationStatus == .authorized
            self?.isAuthorized = authorized
            completion?(authorized)
        }
    }

    // MARK: - Category Registration

    /// Registers notification categories so the system knows how to display them.
    private func registerCategories() {
        let category = UNNotificationCategory(
            identifier: Self.sessionCategoryIdentifier,
            actions: [],
            intentIdentifiers: []
        )
        notificationCenter.setNotificationCategories([category])
    }

    // MARK: - Posting Notifications

    /// Posts a notification for a SessionStart event if enabled in settings.
    /// - Parameters:
    ///   - sessionId: The session identifier.
    ///   - projectName: The derived project name from the working directory.
    func notifySessionStart(sessionId: String, projectName: String) {
        guard isNotificationEnabled(forKey: SettingsViewModel.notifySessionStartKey) else { return }

        let content = UNMutableNotificationContent()
        content.title = "Session Started"
        content.body = "\(projectName) - \(abbreviateSessionId(sessionId))"
        content.categoryIdentifier = Self.sessionCategoryIdentifier
        content.sound = .default
        content.userInfo = [
            Self.sessionIdKey: sessionId,
            Self.eventTypeKey: "SessionStart"
        ]

        postNotification(identifier: "session-start-\(sessionId)", content: content)
    }

    /// Posts a notification for a SessionEnd event if enabled in settings.
    /// - Parameters:
    ///   - sessionId: The session identifier.
    ///   - projectName: The derived project name from the working directory.
    func notifySessionEnd(sessionId: String, projectName: String) {
        guard isNotificationEnabled(forKey: SettingsViewModel.notifySessionEndKey) else { return }

        let content = UNMutableNotificationContent()
        content.title = "Session Ended"
        content.body = "\(projectName) - \(abbreviateSessionId(sessionId))"
        content.categoryIdentifier = Self.sessionCategoryIdentifier
        content.sound = .default
        content.userInfo = [
            Self.sessionIdKey: sessionId,
            Self.eventTypeKey: "SessionEnd"
        ]

        postNotification(identifier: "session-end-\(sessionId)", content: content)
    }

    /// Posts a notification when a session becomes stale if enabled in settings.
    /// - Parameters:
    ///   - sessionId: The session identifier.
    ///   - projectName: The derived project name from the working directory.
    func notifySessionStale(sessionId: String, projectName: String) {
        guard isNotificationEnabled(forKey: SettingsViewModel.notifyStaleKey) else { return }

        let content = UNMutableNotificationContent()
        content.title = "Session Stale"
        content.body = "\(projectName) - \(abbreviateSessionId(sessionId))"
        content.categoryIdentifier = Self.sessionCategoryIdentifier
        content.sound = .default
        content.userInfo = [
            Self.sessionIdKey: sessionId,
            Self.eventTypeKey: "Stale"
        ]

        postNotification(identifier: "session-stale-\(sessionId)", content: content)
    }

    // MARK: - UNUserNotificationCenterDelegate

    /// Called when a notification is delivered while the app is in the foreground.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Show banner and play sound even when the app is in the foreground
        completionHandler([.banner, .sound])
    }

    /// Called when the user interacts with a notification (e.g., clicks it).
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        // Bring the floating window to the front
        DispatchQueue.main.async { [weak self] in
            self?.onNotificationClicked?()
        }
        completionHandler()
    }

    // MARK: - Helpers

    /// Checks whether notifications are enabled for the given settings key.
    /// - Parameter key: The settings key (e.g., `notify_session_start`).
    /// - Returns: `true` if the setting is "true", `false` otherwise (default: false).
    func isNotificationEnabled(forKey key: String) -> Bool {
        guard isAuthorized else { return false }

        do {
            if let value = try databaseManager.getSetting(key: key) {
                return value == "true"
            }
        } catch {
            NSLog("Whippet: Failed to read notification setting '\(key)': \(error.localizedDescription)")
        }
        return false
    }

    /// Posts a notification request with the given identifier and content.
    private func postNotification(identifier: String, content: UNNotificationContent) {
        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: nil // Deliver immediately
        )

        notificationCenter.add(request, withCompletionHandler: { error in
            if let error = error {
                NSLog("Whippet: Failed to post notification: \(error.localizedDescription)")
            }
        })
    }

    /// Abbreviates a session ID for display (first 8 characters).
    func abbreviateSessionId(_ sessionId: String) -> String {
        if sessionId.count > 8 {
            return String(sessionId.prefix(8)) + "..."
        }
        return sessionId
    }
}
