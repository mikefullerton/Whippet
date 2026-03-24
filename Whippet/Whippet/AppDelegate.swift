import AppKit

@main
class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem!
    private var databaseManager: DatabaseManager?
    private var ingestionManager: EventIngestionManager?
    private var hookInstaller: HookInstaller?
    private var livenessMonitor: SessionLivenessMonitor?
    private(set) var panelController = SessionPanelController()
    private(set) var settingsController = SettingsWindowController()

    // MARK: - App Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenuBar()
        setupDatabase()
        setupPanelController()
        setupSettingsController()
        installHooksIfNeeded()
        setupIngestion()
        setupLivenessMonitor()
    }

    func applicationWillTerminate(_ notification: Notification) {
        livenessMonitor?.stop()
        ingestionManager?.stop()
    }

    // MARK: - Database

    private func setupDatabase() {
        do {
            databaseManager = try DatabaseManager()
            NSLog("Whippet: Database initialized")
        } catch {
            NSLog("Whippet: Failed to initialize database: \(error.localizedDescription)")
        }
    }

    // MARK: - Panel Controller

    private func setupPanelController() {
        guard let db = databaseManager else {
            NSLog("Whippet: Cannot setup panel controller without database")
            return
        }
        panelController.setDatabaseManager(db)
    }

    // MARK: - Settings Controller

    private func setupSettingsController() {
        guard let db = databaseManager else {
            NSLog("Whippet: Cannot setup settings controller without database")
            return
        }
        settingsController.configure(databaseManager: db, panelController: panelController)
    }

    // MARK: - Hooks

    private func installHooksIfNeeded() {
        hookInstaller = HookInstaller()
        let result = hookInstaller?.installHooks() ?? .failed("HookInstaller not created")
        switch result {
        case .installed:
            NSLog("Whippet: Hooks installed successfully")
        case .alreadyInstalled:
            NSLog("Whippet: Hooks already installed, skipping")
        case .failed(let error):
            NSLog("Whippet: Hook installation failed: \(error)")
        }
    }

    // MARK: - Ingestion

    private func setupIngestion() {
        guard let db = databaseManager else {
            NSLog("Whippet: Cannot start ingestion without database")
            return
        }

        ingestionManager = EventIngestionManager(databaseManager: db)
        do {
            try ingestionManager?.start()
        } catch {
            NSLog("Whippet: Failed to start event ingestion: \(error.localizedDescription)")
        }
    }

    // MARK: - Liveness Monitor

    private func setupLivenessMonitor() {
        guard let db = databaseManager else {
            NSLog("Whippet: Cannot start liveness monitor without database")
            return
        }

        livenessMonitor = SessionLivenessMonitor(databaseManager: db)
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
            NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ",")
        )
        menu.addItem(NSMenuItem.separator())
        menu.addItem(
            NSMenuItem(title: "Quit Whippet", action: #selector(quitApp), keyEquivalent: "q")
        )

        statusItem.menu = menu
    }

    // MARK: - Menu Actions

    @objc private func showSessions() {
        panelController.togglePanel()
    }

    @objc private func openSettings() {
        settingsController.showSettings()
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}
