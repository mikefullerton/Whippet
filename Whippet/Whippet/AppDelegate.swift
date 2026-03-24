import AppKit

@main
class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem!

    // MARK: - App Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenuBar()
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
        // Placeholder: will open the floating session window in a later step
        NSLog("Whippet: Show Sessions selected")
    }

    @objc private func openSettings() {
        // Placeholder: will open settings window in a later step
        NSLog("Whippet: Settings selected")
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}
