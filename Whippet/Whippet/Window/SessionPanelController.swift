import AppKit
import SwiftUI

/// Manages the lifecycle and visibility of the floating session panel.
/// Uses NSSplitViewController with a native inspector item for the settings drawer.
final class SessionPanelController {

    // MARK: - Properties

    private(set) var panel: SessionPanel?
    private(set) var viewModel: SessionListViewModel?
    private(set) var settingsViewModel: SettingsViewModel?

    private var splitViewController: NSSplitViewController?
    private var inspectorItem: NSSplitViewItem?

    /// Key used to persist the panel frame in UserDefaults.
    static let frameAutosaveName = "WhippetSessionPanel"

    private var databaseManager: DatabaseManager?

    /// The window origin before the inspector was opened, used to restore position on close.
    private var preInspectorOrigin: NSPoint?
    /// The window origin right after the inspector open animation finishes.
    private var postInspectorOpenOrigin: NSPoint?

    // Window discovery panel
    private var discoveryPanel: NSPanel?
    private var discoveryHosting: NSHostingController<WindowDiscoveryView>?

    // MARK: - Initialization

    init() {}

    // MARK: - Configuration

    func setDatabaseManager(_ databaseManager: DatabaseManager) {
        self.databaseManager = databaseManager
        self.viewModel = SessionListViewModel(databaseManager: databaseManager)

        // Create settings view model
        let launchAtLoginManager = LaunchAtLoginManager(databaseManager: databaseManager)
        let settingsVM = SettingsViewModel(databaseManager: databaseManager, launchAtLoginManager: launchAtLoginManager)
        settingsVM.onAlwaysOnTopChanged = { [weak self] isFloating in
            self?.panel?.isFloating = isFloating
        }
        settingsVM.onTransparencyChanged = { [weak self] alpha in
            self?.panel?.transparency = alpha
        }
        settingsVM.onAppearanceModeChanged = { mode in
            switch mode {
            case "light": NSApp.appearance = NSAppearance(named: .aqua)
            case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
            default: NSApp.appearance = nil
            }
            Log.app.info("Appearance mode: \(mode, privacy: .public)")
        }
        self.settingsViewModel = settingsVM

        // Wire up window discovery request from click actions
        self.viewModel?.onWindowDiscoveryRequested = { [weak self] session in
            self?.showWindowDiscovery(for: session)
        }
    }

    // MARK: - Panel Creation

    private func createPanelIfNeeded() {
        guard panel == nil else { return }

        guard let viewModel = viewModel, let settingsViewModel = settingsViewModel else {
            Log.ui.warning("Creating panel without database manager — call setDatabaseManager first")
            return
        }
        Log.ui.debug("Creating session panel")

        let defaultFrame = NSRect(x: 0, y: 0, width: 340, height: 300)
        let sessionPanel = SessionPanel(contentRect: defaultFrame)

        // -- Session content (main item) --
        let sessionView = SessionContentView(viewModel: viewModel)
        let sessionHosting = NSHostingController(rootView: sessionView)

        let sessionItem = NSSplitViewItem(viewController: sessionHosting)
        sessionItem.minimumThickness = 280
        sessionItem.canCollapse = false

        // -- Settings inspector (right-side drawer) --
        let settingsView = SettingsDrawerView(viewModel: settingsViewModel) { [weak self] in
            self?.toggleSettings()
        }
        let settingsHosting = NSHostingController(rootView: settingsView)

        let inspector = NSSplitViewItem(inspectorWithViewController: settingsHosting)
        inspector.minimumThickness = 440
        inspector.maximumThickness = 600
        inspector.preferredThicknessFraction = 0.55
        inspector.isCollapsed = true
        self.inspectorItem = inspector

        // -- Split view controller --
        let splitVC = NSSplitViewController()
        splitVC.addSplitViewItem(sessionItem)
        splitVC.addSplitViewItem(inspector)
        splitVC.splitView.dividerStyle = .thin
        splitVC.splitView.autosaveName = "WhippetSplitView"
        self.splitViewController = splitVC

        sessionPanel.contentViewController = splitVC

        // Wire callbacks
        sessionPanel.onCloseButtonPressed = { [weak self] in
            self?.promptQuit()
        }
        sessionPanel.onSettingsButtonPressed = { [weak self] in
            self?.toggleSettings()
        }

        // Set autosave name BEFORE restoring frame
        sessionPanel.setFrameAutosaveName(Self.frameAutosaveName)

        if !sessionPanel.setFrameUsingName(Self.frameAutosaveName) {
            sessionPanel.center()
        }

        // Lock horizontal width initially (inspector starts collapsed)
        sessionPanel.lockedWidth = sessionPanel.frame.width

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
        panel.orderFront(nil)
        Log.ui.debug("Panel shown")
    }

    func hidePanel() {
        guard let panel = panel else { return }
        panel.saveFrame(usingName: Self.frameAutosaveName)
        panel.orderOut(nil)
        Log.ui.debug("Panel hidden")
    }

    // MARK: - Settings Inspector

    func toggleSettings() {
        guard let inspector = inspectorItem, let panel = panel else { return }

        // Unlock horizontal resize for the duration of the animation
        panel.lockedWidth = nil

        if inspector.isCollapsed {
            // Opening: record current origin so we can restore on close
            preInspectorOrigin = panel.frame.origin
            postInspectorOpenOrigin = nil

            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.2
                context.allowsImplicitAnimation = true
                inspector.animator().isCollapsed = false
            }, completionHandler: { [weak self] in
                // Record where the window ended up after the system adjusted for screen bounds
                self?.postInspectorOpenOrigin = self?.panel?.frame.origin
                // Leave lockedWidth = nil so user can resize while inspector is open
            })
        } else {
            // Closing: check if the user moved the window since it was opened
            let shouldRestore: Bool = {
                guard let pre = preInspectorOrigin, let post = postInspectorOpenOrigin else { return false }
                let current = panel.frame.origin
                // If the window is still where the system put it (within 1pt tolerance), restore
                return abs(current.x - post.x) < 1 && abs(current.y - post.y) < 1
            }()

            let restoreOrigin = shouldRestore ? preInspectorOrigin : nil

            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.2
                context.allowsImplicitAnimation = true
                inspector.animator().isCollapsed = true

                if let origin = restoreOrigin {
                    var newFrame = panel.frame
                    newFrame.origin = origin
                    panel.animator().setFrame(newFrame, display: true)
                }
            }, completionHandler: { [weak self] in
                self?.preInspectorOrigin = nil
                self?.postInspectorOpenOrigin = nil
                // Lock width now that inspector is collapsed
                self?.panel?.lockedWidth = self?.panel?.frame.width
            })
        }
    }

    var isSettingsVisible: Bool {
        inspectorItem?.isCollapsed == false
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
