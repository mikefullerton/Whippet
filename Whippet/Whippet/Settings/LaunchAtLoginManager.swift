import Foundation
import ServiceManagement

/// Protocol abstracting SMAppService for testability.
/// In production, `SMAppService.mainApp` provides the real implementation.
protocol LaunchAtLoginServiceProtocol {
    /// The current registration status of the app service.
    var status: SMAppService.Status { get }

    /// Registers the app to launch at login.
    func register() throws

    /// Unregisters the app from launching at login.
    func unregister() throws
}

/// Conform the real SMAppService to our protocol.
extension SMAppService: LaunchAtLoginServiceProtocol {}

/// Manages the "Launch at Login" feature using SMAppService (macOS 13+).
///
/// Provides a clean interface for the settings UI to toggle launch-at-login
/// and accurately reflect the current system registration state. Uses a protocol
/// abstraction over SMAppService for unit testing.
final class LaunchAtLoginManager {

    // MARK: - Settings Keys

    /// Key for the launch-at-login setting in the database.
    /// Also used to track whether the first-launch prompt has been shown.
    static let launchAtLoginKey = "launch_at_login"

    /// Key for tracking whether the first-launch prompt has been shown.
    static let launchAtLoginPromptShownKey = "launch_at_login_prompt_shown"

    // MARK: - Properties

    private let service: LaunchAtLoginServiceProtocol
    private let databaseManager: DatabaseManager

    // MARK: - Initialization

    /// Creates a LaunchAtLoginManager.
    /// - Parameters:
    ///   - databaseManager: The database manager for persisting settings.
    ///   - service: The app service to use. Defaults to `SMAppService.mainApp`.
    init(databaseManager: DatabaseManager, service: LaunchAtLoginServiceProtocol? = nil) {
        self.databaseManager = databaseManager
        self.service = service ?? SMAppService.mainApp
    }

    // MARK: - State

    /// Whether the app is currently registered to launch at login,
    /// based on the actual system state via SMAppService.
    var isEnabled: Bool {
        service.status == .enabled
    }

    /// Whether the first-launch prompt has already been shown.
    var hasShownPrompt: Bool {
        do {
            if let value = try databaseManager.getSetting(key: Self.launchAtLoginPromptShownKey) {
                return value == "true"
            }
        } catch {
            NSLog("Whippet: Failed to read launch-at-login prompt state: \(error.localizedDescription)")
        }
        return false
    }

    // MARK: - Toggle

    /// Enables or disables launch at login.
    /// - Parameter enabled: Whether to register or unregister the app.
    /// - Throws: An error if the registration or unregistration fails.
    func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try service.register()
        } else {
            try service.unregister()
        }

        // Persist the setting
        do {
            try databaseManager.setSetting(key: Self.launchAtLoginKey, value: enabled ? "true" : "false")
        } catch {
            NSLog("Whippet: Failed to persist launch-at-login setting: \(error.localizedDescription)")
        }
    }

    /// Marks the first-launch prompt as shown.
    func markPromptShown() {
        do {
            try databaseManager.setSetting(key: Self.launchAtLoginPromptShownKey, value: "true")
        } catch {
            NSLog("Whippet: Failed to persist launch-at-login prompt state: \(error.localizedDescription)")
        }
    }
}
