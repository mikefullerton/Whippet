import AppKit
import SwiftUI

/// Manages the Settings window lifecycle. Creates the window lazily on first open,
/// hosts the SwiftUI SettingsView via NSHostingController, and wires up the
/// SettingsViewModel callbacks to apply changes to the session panel in real time.
final class SettingsWindowController {

    // MARK: - Properties

    /// The settings window instance (created lazily).
    private var window: NSWindow?

    /// The view model driving the settings UI.
    private(set) var viewModel: SettingsViewModel?

    /// The database manager, held so the view model can be created.
    private var databaseManager: DatabaseManager?

    /// The panel controller, used to apply window setting changes immediately.
    private weak var panelController: SessionPanelController?

    // MARK: - Initialization

    init() {}

    // MARK: - Configuration

    /// Sets the database manager and panel controller. Must be called before showing the window.
    func configure(databaseManager: DatabaseManager, panelController: SessionPanelController) {
        self.databaseManager = databaseManager
        self.panelController = panelController
    }

    // MARK: - Show / Hide

    /// Shows the settings window. Creates it on first call.
    func showSettings() {
        if let window = window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        guard let databaseManager = databaseManager else {
            NSLog("Whippet: Cannot show settings without database manager")
            return
        }

        let launchAtLoginManager = LaunchAtLoginManager(databaseManager: databaseManager)
        let vm = SettingsViewModel(databaseManager: databaseManager, launchAtLoginManager: launchAtLoginManager)

        // Wire up callbacks so changes take effect immediately on the session panel
        vm.onAlwaysOnTopChanged = { [weak self] isFloating in
            self?.panelController?.isFloating = isFloating
        }
        vm.onTransparencyChanged = { [weak self] alpha in
            self?.panelController?.transparency = alpha
        }

        self.viewModel = vm

        let settingsView = SettingsView(viewModel: vm)
        let hostingController = NSHostingController(rootView: settingsView)

        let settingsWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 480),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        settingsWindow.title = "Whippet Settings"
        settingsWindow.contentViewController = hostingController
        settingsWindow.center()
        settingsWindow.isReleasedWhenClosed = false
        settingsWindow.setFrameAutosaveName("WhippetSettingsWindow")
        settingsWindow.minSize = NSSize(width: 550, height: 420)

        self.window = settingsWindow
        settingsWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Whether the settings window is currently visible.
    var isVisible: Bool {
        window?.isVisible ?? false
    }
}
