import AppKit
import SwiftUI

/// Manages the lifecycle and visibility of the floating session panel.
///
/// Responsibilities:
/// - Creates and configures the SessionPanel with SwiftUI content via NSHostingController
/// - Toggles panel visibility from the menu bar
/// - Remembers panel position between show/hide cycles
/// - Exposes window level and transparency configuration
final class SessionPanelController {

    // MARK: - Properties

    /// The underlying NSPanel instance.
    private(set) var panel: SessionPanel?

    /// The last saved frame origin, used to restore position between toggles.
    private var savedOrigin: NSPoint?

    /// Key used to persist the panel frame in UserDefaults.
    static let frameAutosaveName = "WhippetSessionPanel"

    // MARK: - Initialization

    init() {}

    // MARK: - Panel Creation

    /// Creates the panel if it hasn't been created yet.
    /// The panel is created lazily on first toggle to avoid creating
    /// windows during app launch when they may not be needed.
    private func createPanelIfNeeded() {
        guard panel == nil else { return }

        let defaultFrame = NSRect(x: 0, y: 0, width: 400, height: 500)
        let sessionPanel = SessionPanel(contentRect: defaultFrame)

        // Host the SwiftUI content
        let hostingController = NSHostingController(rootView: SessionContentView())
        sessionPanel.contentView = hostingController.view

        // Restore saved frame or center the panel
        if let savedFrame = savedFrameFromDefaults() {
            sessionPanel.setFrame(savedFrame, display: false)
        } else {
            sessionPanel.center()
        }

        // Set up frame autosave so position persists across app launches
        sessionPanel.setFrameAutosaveName(SessionPanelController.frameAutosaveName)

        panel = sessionPanel
    }

    // MARK: - Visibility

    /// Whether the panel is currently visible.
    var isVisible: Bool {
        panel?.isVisible ?? false
    }

    /// Toggles the panel visibility. Shows the panel if hidden, hides it if visible.
    func togglePanel() {
        createPanelIfNeeded()

        guard let panel = panel else { return }

        if panel.isVisible {
            hidePanel()
        } else {
            showPanel()
        }
    }

    /// Shows the panel, restoring its previous position if available.
    func showPanel() {
        createPanelIfNeeded()

        guard let panel = panel else { return }

        // Restore saved origin if we have one from a previous hide
        if let origin = savedOrigin {
            panel.setFrameOrigin(origin)
        }

        panel.orderFront(nil)
    }

    /// Hides the panel, saving its current position.
    func hidePanel() {
        guard let panel = panel else { return }

        // Save position before hiding
        savedOrigin = panel.frame.origin

        panel.orderOut(nil)
    }

    // MARK: - Configuration

    /// Whether the panel floats above all other windows.
    var isFloating: Bool {
        get { panel?.isFloating ?? true }
        set {
            createPanelIfNeeded()
            panel?.isFloating = newValue
        }
    }

    /// The panel's transparency (0.3...1.0).
    var transparency: CGFloat {
        get { panel?.transparency ?? 1.0 }
        set {
            createPanelIfNeeded()
            panel?.transparency = newValue
        }
    }

    // MARK: - Frame Persistence

    /// Attempts to read a previously saved frame from UserDefaults.
    private func savedFrameFromDefaults() -> NSRect? {
        let key = "NSWindow Frame \(SessionPanelController.frameAutosaveName)"
        guard let frameString = UserDefaults.standard.string(forKey: key) else {
            return nil
        }
        return NSRectFromString(frameString) != .zero ? NSRectFromString(frameString) : nil
    }
}
