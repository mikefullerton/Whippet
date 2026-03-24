import AppKit

/// A floating NSPanel for displaying Claude Code session information.
///
/// This panel is configured as a utility window with non-activating behavior,
/// meaning it won't steal focus from other applications. It supports configurable
/// window level (floating vs normal) and transparency.
final class SessionPanel: NSPanel {

    // MARK: - Initialization

    /// Creates a new SessionPanel with default utility window configuration.
    /// - Parameter contentRect: The initial frame for the panel.
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [
                .titled,
                .closable,
                .resizable,
                .utilityWindow,
                .nonactivatingPanel
            ],
            backing: .buffered,
            defer: false
        )

        configureDefaults()
    }

    // MARK: - Configuration

    private func configureDefaults() {
        title = "Whippet Sessions"
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        level = .floating
        isMovableByWindowBackground = true
        minSize = NSSize(width: 320, height: 200)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        // Default transparency
        alphaValue = 1.0
        isOpaque = false
        backgroundColor = .windowBackgroundColor
    }

    // MARK: - Window Level

    /// Whether the panel floats above all other windows.
    var isFloating: Bool {
        get { level == .floating }
        set { level = newValue ? .floating : .normal }
    }

    // MARK: - Transparency

    /// The panel's transparency value (0.0 fully transparent to 1.0 fully opaque).
    /// Clamped to a usable range of 0.3...1.0 so the window never becomes invisible.
    var transparency: CGFloat {
        get { alphaValue }
        set { alphaValue = min(max(newValue, 0.3), 1.0) }
    }

    // MARK: - Key/Main Behavior

    /// Allow the panel to become key so it can receive keyboard events when focused.
    override var canBecomeKey: Bool { true }

    /// Prevent the panel from becoming main window to avoid
    /// disrupting the main app's window ordering.
    override var canBecomeMain: Bool { false }
}
