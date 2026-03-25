import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem!
    private var databaseManager: DatabaseManager?
    private var ingestionManager: EventIngestionManager?
    private var hookInstaller: HookInstaller?
    private var livenessMonitor: SessionLivenessMonitor?
    private var notificationManager: NotificationManager?
    private(set) var panelController = SessionPanelController()

    // MARK: - App Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        Log.app.info("Whippet launching")
        setupMenuBar()
        setupDatabase()
        setupPanelController()
        installHooksIfNeeded()
        setupNotifications()
        setupIngestion()
        setupLivenessMonitor()
        panelController.showPanel()
        Log.app.info("Whippet launch complete — all subsystems initialized")
    }

    func applicationWillTerminate(_ notification: Notification) {
        Log.app.info("Whippet terminating")
        livenessMonitor?.stop()
        ingestionManager?.stop()
        Log.app.info("Whippet shutdown complete")
    }

    // MARK: - Database

    private func setupDatabase() {
        do {
            databaseManager = try DatabaseManager()
            Log.app.info("Database initialized")
        } catch {
            Log.app.error("Failed to initialize database: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Panel Controller

    private func setupPanelController() {
        guard let db = databaseManager else {
            Log.app.warning("Cannot setup panel controller — no database")
            return
        }
        panelController.setDatabaseManager(db)

        // Apply saved appearance mode
        if let mode = try? db.getSetting(key: SettingsViewModel.appearanceModeKey) {
            applyAppearanceMode(mode)
        }

        Log.app.debug("Panel controller configured")
    }

    // MARK: - Hooks

    private func installHooksIfNeeded() {
        hookInstaller = HookInstaller()
        guard let installer = hookInstaller else { return }

        // Always reinstall to pick up hook command updates
        _ = installer.uninstallHooks()
        let result = installer.installHooks()
        switch result {
        case .installed:
            Log.app.info("Hooks installed successfully")
        case .alreadyInstalled:
            Log.app.info("Hooks already installed")
        case .failed(let error):
            Log.app.error("Hook installation failed: \(error, privacy: .public)")
        }
    }

    // MARK: - Notifications

    private func setupNotifications() {
        guard let db = databaseManager else {
            Log.app.warning("Cannot setup notifications — no database")
            return
        }

        notificationManager = NotificationManager(databaseManager: db)
        notificationManager?.requestAuthorization()

        // When a notification is clicked, bring the floating window to the front
        notificationManager?.onNotificationClicked = { [weak self] in
            self?.panelController.showPanel()
        }
        Log.app.debug("Notification manager configured")
    }

    // MARK: - Ingestion

    private func setupIngestion() {
        guard let db = databaseManager else {
            Log.app.warning("Cannot start ingestion — no database")
            return
        }

        ingestionManager = EventIngestionManager(databaseManager: db)

        // Wire per-event callback for notifications
        ingestionManager?.onEventIngested = { [weak self] eventType, sessionId, projectName in
            guard let nm = self?.notificationManager else { return }
            switch eventType {
            case "SessionStart":
                nm.notifySessionStart(sessionId: sessionId, projectName: projectName)
            case "SessionEnd":
                nm.notifySessionEnd(sessionId: sessionId, projectName: projectName)
            default:
                break
            }
        }

        do {
            try ingestionManager?.start()
        } catch {
            Log.app.error("Failed to start event ingestion: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Liveness Monitor

    private func setupLivenessMonitor() {
        guard let db = databaseManager else {
            Log.app.warning("Cannot start liveness monitor — no database")
            return
        }

        livenessMonitor = SessionLivenessMonitor(databaseManager: db)

        // Wire per-session stale callback for notifications
        livenessMonitor?.onSessionMarkedStale = { [weak self] sessionId, projectName in
            self?.notificationManager?.notifySessionStale(sessionId: sessionId, projectName: projectName)
        }

        livenessMonitor?.start()
    }

    // MARK: - Menu Bar

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "dog.fill", accessibilityDescription: "Whippet")
            button.image?.size = NSSize(width: 18, height: 18)
            button.image?.isTemplate = true
        }

        let menu = NSMenu()
        menu.addItem(
            NSMenuItem(title: "Show Sessions", action: #selector(showSessions), keyEquivalent: "s")
        )
        menu.addItem(NSMenuItem.separator())
        menu.addItem(
            NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: "")
        )
        menu.addItem(NSMenuItem.separator())
        menu.addItem(
            NSMenuItem(title: "Quit Whippet", action: #selector(quitApp), keyEquivalent: "q")
        )

        statusItem.menu = menu
        Log.app.debug("Menu bar configured")
    }

    // MARK: - Menu Actions

    @objc private func showSessions() {
        Log.ui.debug("Menu action: Show Sessions")
        panelController.togglePanel()
    }

    @objc private func openSettings() {
        Log.ui.debug("Menu action: Settings")
        panelController.showPanel()
        panelController.toggleSettings()
    }

    @objc private func quitApp() {
        Log.app.info("Menu action: Quit")
        NSApplication.shared.terminate(nil)
    }

    // MARK: - Appearance

    private func applyAppearanceMode(_ mode: String) {
        switch mode {
        case "light":
            NSApp.appearance = NSAppearance(named: .aqua)
        case "dark":
            NSApp.appearance = NSAppearance(named: .darkAqua)
        default:
            NSApp.appearance = nil
        }
        Log.app.info("Appearance mode: \(mode, privacy: .public)")
    }
}
