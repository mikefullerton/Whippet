import AppKit
import SwiftUI

/// Manages the lifecycle and visibility of the floating session panel.
final class SessionPanelController {

    // MARK: - Properties

    private(set) var panel: SessionPanel?
    private(set) var viewModel: SessionListViewModel?

    /// Key used to persist the panel frame in UserDefaults.
    static let frameAutosaveName = "WhippetSessionPanel"

    private var databaseManager: DatabaseManager?
    private var hostingController: NSHostingController<SessionContentView>?
    private var sizeObservation: NSKeyValueObservation?

    /// Called when the user clicks the gear icon. Set by AppDelegate to open the settings window.
    var onSettingsButtonPressed: (() -> Void)?

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

        let sessionView = SessionContentView(viewModel: viewModel)
        let sessionHosting = NSHostingController(rootView: sessionView)
        // Don't let the hosting controller auto-resize the window at all
        sessionHosting.sizingOptions = []
        sessionPanel.contentViewController = sessionHosting
        hostingController = sessionHosting

        // Wire callbacks
        sessionPanel.onCloseButtonPressed = { [weak self] in
            self?.promptQuit()
        }
        sessionPanel.onSettingsButtonPressed = { [weak self] in
            self?.onSettingsButtonPressed?()
        }

        // Set autosave name BEFORE restoring frame
        sessionPanel.setFrameAutosaveName(Self.frameAutosaveName)

        if !sessionPanel.setFrameUsingName(Self.frameAutosaveName) {
            sessionPanel.center()
        }

        panel = sessionPanel

        // The hosting view fills the window via autoresizing mask (default).
        // We observe its intrinsic content size to resize the window height only.
        sizeObservation = sessionHosting.view.observe(\.intrinsicContentSize, options: [.new]) { [weak self] view, _ in
            let fittingHeight = view.intrinsicContentSize.height
            if fittingHeight > 0 {
                DispatchQueue.main.async {
                    self?.updatePanelHeight(to: fittingHeight)
                }
            }
        }
    }

    private func updatePanelHeight(to contentHeight: CGFloat) {
        guard let panel else { return }
        let newHeight = min(max(contentHeight, 80), 800)
        var frame = panel.frame
        guard abs(frame.height - newHeight) > 1 else { return }
        // Adjust origin.y so the top edge stays put
        frame.origin.y -= (newHeight - frame.height)
        frame.size.height = newHeight
        // Keep width unchanged
        panel.setFrame(frame, display: true, animate: false)
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
        panel.orderFront(nil)
        Log.ui.debug("Panel shown")
    }

    func hidePanel() {
        guard let panel = panel else { return }
        panel.saveFrame(usingName: Self.frameAutosaveName)
        panel.orderOut(nil)
        Log.ui.debug("Panel hidden")
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
