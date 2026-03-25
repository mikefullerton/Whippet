import AppKit
import SwiftUI

/// Manages the lifecycle and visibility of the floating session panel.
final class SessionPanelController {

    // MARK: - Properties

    private(set) var panel: SessionPanel?
    private(set) var viewModel: SessionListViewModel?
    private var hostingController: NSHostingController<SessionContentView>?

    /// Key used to persist the panel frame in UserDefaults.
    static let frameAutosaveName = "WhippetSessionPanel"

    private var databaseManager: DatabaseManager?

    /// Called when the user clicks the gear icon. AppDelegate wires this to open settings.
    var onSettingsRequested: (() -> Void)?

    // Window discovery panel
    private var discoveryPanel: NSPanel?
    private var discoveryHosting: NSHostingController<WindowDiscoveryView>?

    // MARK: - Initialization

    init() {}

    // MARK: - Configuration

    func setDatabaseManager(_ databaseManager: DatabaseManager) {
        self.databaseManager = databaseManager
        self.viewModel = SessionListViewModel(databaseManager: databaseManager)

        // Wire up window discovery request from click actions
        self.viewModel?.onWindowDiscoveryRequested = { [weak self] session in
            self?.showWindowDiscovery(for: session)
        }
    }

    // MARK: - Panel Creation

    private func createPanelIfNeeded() {
        guard panel == nil else { return }

        guard let viewModel = viewModel else {
            Log.ui.warning("Creating panel without database manager — call setDatabaseManager first")
            return
        }
        Log.ui.debug("Creating session panel")

        let defaultFrame = NSRect(x: 0, y: 0, width: 340, height: 300)
        let sessionPanel = SessionPanel(contentRect: defaultFrame)

        let contentView = SessionContentView(viewModel: viewModel)
        let hosting = NSHostingController(rootView: contentView)
        // Let the hosting view size itself to the SwiftUI content
        hosting.sizingOptions = [.preferredContentSize]
        sessionPanel.contentView = hosting.view
        hostingController = hosting

        // Wire callbacks
        sessionPanel.onCloseButtonPressed = { [weak self] in
            self?.promptQuit()
        }
        sessionPanel.onSettingsButtonPressed = { [weak self] in
            self?.onSettingsRequested?()
        }

        // Set autosave name BEFORE restoring frame
        sessionPanel.setFrameAutosaveName(Self.frameAutosaveName)

        if !sessionPanel.setFrameUsingName(Self.frameAutosaveName) {
            sessionPanel.center()
        }

        // Observe content size changes to resize the window to fit
        hostingController?.view.setContentHuggingPriority(.defaultHigh, for: .vertical)

        panel = sessionPanel
    }

    // MARK: - Visibility

    var isVisible: Bool {
        panel?.isVisible ?? false
    }

    func togglePanel() {
        if isVisible {
            hidePanel()
        } else {
            showPanel()
        }
    }

    func showPanel() {
        createPanelIfNeeded()
        guard let panel = panel else { return }

        viewModel?.loadSessions()
        sizeWindowToContent()
        panel.orderFront(nil)
        Log.ui.debug("Panel shown")
    }

    func hidePanel() {
        guard let panel = panel else { return }
        panel.saveFrame(usingName: Self.frameAutosaveName)
        panel.orderOut(nil)
        Log.ui.debug("Panel hidden")
    }

    // MARK: - Size to Content

    /// Resizes the window height to fit the SwiftUI content, keeping the current width and position.
    func sizeWindowToContent() {
        guard let panel = panel, let hosting = hostingController else { return }

        let fittingSize = hosting.view.fittingSize
        let currentFrame = panel.frame

        // Keep the current width (user may have resized), adjust height to content
        let newHeight = max(fittingSize.height + panel.titlebarHeight, panel.minSize.height)
        let newFrame = NSRect(
            x: currentFrame.origin.x,
            y: currentFrame.origin.y + currentFrame.height - newHeight,
            width: currentFrame.width,
            height: newHeight
        )
        panel.setFrame(newFrame, display: true, animate: false)
    }

    // MARK: - Quit Confirmation

    private func promptQuit() {
        let alert = NSAlert()
        alert.messageText = "Quit Whippet?"
        alert.informativeText = "Whippet will stop monitoring Claude Code sessions."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Quit")
        alert.addButton(withTitle: "Cancel")

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            Log.app.info("User confirmed quit from close button")
            NSApplication.shared.terminate(nil)
        }
    }

    // MARK: - Window Discovery

    func showWindowDiscovery(for session: Session) {
        // Dismiss any existing discovery panel
        dismissWindowDiscovery()

        let vm = WindowDiscoveryViewModel(session: session)
        vm.onWindowActivated = { [weak self] in
            self?.dismissWindowDiscovery()
        }

        let view = WindowDiscoveryView(viewModel: vm)
        let hosting = NSHostingController(rootView: view)
        hosting.sizingOptions = [.preferredContentSize]

        let discoveryPanel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 420),
            styleMask: [.titled, .closable, .resizable, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        discoveryPanel.title = "Window Discovery"
        discoveryPanel.contentView = hosting.view
        discoveryPanel.level = .floating
        discoveryPanel.isReleasedWhenClosed = false
        discoveryPanel.hidesOnDeactivate = false
        discoveryPanel.minSize = NSSize(width: 300, height: 200)
        discoveryPanel.center()
        discoveryPanel.orderFront(nil)

        self.discoveryPanel = discoveryPanel
        self.discoveryHosting = hosting
        Log.ui.debug("Window discovery panel shown for '\(session.projectName, privacy: .public)'")
    }

    func dismissWindowDiscovery() {
        discoveryPanel?.orderOut(nil)
        discoveryPanel = nil
        discoveryHosting = nil
    }

    // MARK: - Configuration

    var isFloating: Bool {
        get { panel?.isFloating ?? true }
        set {
            createPanelIfNeeded()
            panel?.isFloating = newValue
        }
    }

    var transparency: CGFloat {
        get { panel?.transparency ?? 1.0 }
        set {
            createPanelIfNeeded()
            panel?.transparency = newValue
        }
    }
}

// MARK: - NSPanel Extension

private extension NSPanel {
    /// The height of the title bar area.
    var titlebarHeight: CGFloat {
        contentRect(forFrameRect: frame).height < frame.height
            ? frame.height - contentRect(forFrameRect: frame).height
            : 22 // fallback
    }
}
