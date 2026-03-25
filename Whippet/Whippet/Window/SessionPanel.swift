import AppKit

/// A floating palette-style NSPanel for displaying Claude Code sessions.
///
/// Has a visible title bar with close button (prompts to quit) and a gear icon
/// for settings. Stays above all windows when floating is enabled.
final class SessionPanel: NSPanel {

    /// Called when the user clicks the close button. The controller should present
    /// a quit confirmation instead of actually closing.
    var onCloseButtonPressed: (() -> Void)?

    /// Called when the user clicks the gear icon in the title bar.
    var onSettingsButtonPressed: (() -> Void)?

    // MARK: - Initialization

    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [
                .titled,
                .closable,
                .resizable,
                .utilityWindow,
                .nonactivatingPanel,
            ],
            backing: .buffered,
            defer: false
        )

        configureDefaults()
        addTitleBarAccessory()
    }

    // MARK: - Configuration

    private func configureDefaults() {
        title = "Whippet"
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        level = .floating
        isMovableByWindowBackground = true
        minSize = NSSize(width: 280, height: 120)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        alphaValue = 0.96
        isOpaque = false
        backgroundColor = .windowBackgroundColor
    }

    private func addTitleBarAccessory() {
        let gearButton = NSButton(frame: NSRect(x: 0, y: 0, width: 28, height: 28))
        gearButton.bezelStyle = .accessoryBarAction
        gearButton.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: "Settings")
        gearButton.imagePosition = .imageOnly
        gearButton.isBordered = false
        gearButton.target = self
        gearButton.action = #selector(gearButtonClicked)

        let accessoryView = NSTitlebarAccessoryViewController()
        accessoryView.layoutAttribute = .trailing
        accessoryView.view = gearButton
        addTitlebarAccessoryViewController(accessoryView)
    }

    @objc private func gearButtonClicked() {
        onSettingsButtonPressed?()
    }

    // MARK: - Close → Quit Confirmation

    override func close() {
        onCloseButtonPressed?()
    }

    // MARK: - Window Level

    var isFloating: Bool {
        get { level == .floating }
        set { level = newValue ? .floating : .normal }
    }

    // MARK: - Transparency

    var transparency: CGFloat {
        get { alphaValue }
        set { alphaValue = min(max(newValue, 0.3), 1.0) }
    }

    // MARK: - Key/Main Behavior

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
