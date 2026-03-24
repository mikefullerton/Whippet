import XCTest
@testable import Whippet

final class SessionPanelControllerTests: XCTestCase {

    private var controller: SessionPanelController!
    private var tempDatabasePath: String!
    private var databaseManager: DatabaseManager!

    override func setUp() {
        super.setUp()

        // Create a temp database so the panel controller can create its view model
        tempDatabasePath = NSTemporaryDirectory() + "whippet_test_panel_\(UUID().uuidString).db"
        databaseManager = try! DatabaseManager(path: tempDatabasePath)

        controller = SessionPanelController()
        controller.setDatabaseManager(databaseManager)

        // Clear any saved frame from previous test runs
        let key = "NSWindow Frame \(SessionPanelController.frameAutosaveName)"
        UserDefaults.standard.removeObject(forKey: key)
    }

    override func tearDown() {
        // Ensure panel is hidden and cleaned up
        controller.hidePanel()
        controller = nil

        databaseManager.close()
        try? FileManager.default.removeItem(atPath: tempDatabasePath)

        let key = "NSWindow Frame \(SessionPanelController.frameAutosaveName)"
        UserDefaults.standard.removeObject(forKey: key)

        super.tearDown()
    }

    // MARK: - Panel Creation

    func testPanelIsNilBeforeFirstToggle() {
        XCTAssertNil(controller.panel, "Panel should not be created until first toggle")
    }

    func testPanelIsCreatedOnFirstToggle() {
        controller.togglePanel()
        XCTAssertNotNil(controller.panel, "Panel should be created after first toggle")
    }

    func testPanelIsCreatedOnShowPanel() {
        controller.showPanel()
        XCTAssertNotNil(controller.panel, "Panel should be created after showPanel")
    }

    // MARK: - Visibility Toggle

    func testTogglePanelShowsWhenHidden() {
        controller.togglePanel()
        XCTAssertTrue(controller.isVisible, "Panel should be visible after first toggle")
    }

    func testTogglePanelHidesWhenVisible() {
        controller.togglePanel() // show
        XCTAssertTrue(controller.isVisible)

        controller.togglePanel() // hide
        XCTAssertFalse(controller.isVisible, "Panel should be hidden after second toggle")
    }

    func testTogglePanelShowsAgainAfterHide() {
        controller.togglePanel() // show
        controller.togglePanel() // hide
        controller.togglePanel() // show again
        XCTAssertTrue(controller.isVisible, "Panel should be visible after third toggle")
    }

    func testShowPanelMakesVisible() {
        controller.showPanel()
        XCTAssertTrue(controller.isVisible)
    }

    func testHidePanelMakesInvisible() {
        controller.showPanel()
        controller.hidePanel()
        XCTAssertFalse(controller.isVisible)
    }

    func testIsVisibleReturnsFalseBeforeCreation() {
        XCTAssertFalse(controller.isVisible, "isVisible should return false when panel hasn't been created")
    }

    // MARK: - Panel Configuration

    func testPanelHasUtilityWindowStyle() {
        controller.showPanel()
        guard let panel = controller.panel else {
            XCTFail("Panel should exist")
            return
        }
        XCTAssertTrue(panel.styleMask.contains(.utilityWindow), "Panel should have utilityWindow style")
    }

    func testPanelHasNonActivatingStyle() {
        controller.showPanel()
        guard let panel = controller.panel else {
            XCTFail("Panel should exist")
            return
        }
        XCTAssertTrue(panel.styleMask.contains(.nonactivatingPanel), "Panel should have nonactivatingPanel style")
    }

    func testPanelIsClosable() {
        controller.showPanel()
        guard let panel = controller.panel else {
            XCTFail("Panel should exist")
            return
        }
        XCTAssertTrue(panel.styleMask.contains(.closable), "Panel should be closable")
    }

    func testPanelIsResizable() {
        controller.showPanel()
        guard let panel = controller.panel else {
            XCTFail("Panel should exist")
            return
        }
        XCTAssertTrue(panel.styleMask.contains(.resizable), "Panel should be resizable")
    }

    func testPanelHasTitled() {
        controller.showPanel()
        guard let panel = controller.panel else {
            XCTFail("Panel should exist")
            return
        }
        XCTAssertTrue(panel.styleMask.contains(.titled), "Panel should have title bar")
    }

    func testPanelTitle() {
        controller.showPanel()
        XCTAssertEqual(controller.panel?.title, "Whippet Sessions")
    }

    func testPanelIsNotReleasedWhenClosed() {
        controller.showPanel()
        XCTAssertFalse(controller.panel?.isReleasedWhenClosed ?? true)
    }

    func testPanelDoesNotHideOnDeactivate() {
        controller.showPanel()
        XCTAssertFalse(controller.panel?.hidesOnDeactivate ?? true)
    }

    func testPanelCanBecomeKey() {
        controller.showPanel()
        XCTAssertTrue(controller.panel?.canBecomeKey ?? false)
    }

    func testPanelCannotBecomeMain() {
        controller.showPanel()
        XCTAssertFalse(controller.panel?.canBecomeMain ?? true)
    }

    func testPanelHasMinimumSize() {
        controller.showPanel()
        guard let panel = controller.panel else {
            XCTFail("Panel should exist")
            return
        }
        XCTAssertGreaterThanOrEqual(panel.minSize.width, 320)
        XCTAssertGreaterThanOrEqual(panel.minSize.height, 200)
    }

    // MARK: - Floating Window Level

    func testDefaultWindowLevelIsFloating() {
        controller.showPanel()
        XCTAssertEqual(controller.panel?.level, .floating, "Panel should default to floating level")
    }

    func testIsFloatingDefaultsToTrue() {
        XCTAssertTrue(controller.isFloating, "isFloating should default to true")
    }

    func testSetIsFloatingToFalse() {
        controller.isFloating = false
        controller.showPanel()
        XCTAssertFalse(controller.isFloating)
        XCTAssertEqual(controller.panel?.level, .normal)
    }

    func testSetIsFloatingToTrue() {
        controller.isFloating = false
        controller.isFloating = true
        controller.showPanel()
        XCTAssertTrue(controller.isFloating)
        XCTAssertEqual(controller.panel?.level, .floating)
    }

    // MARK: - Transparency

    func testDefaultTransparencyIsOpaque() {
        XCTAssertEqual(controller.transparency, 1.0, "Default transparency should be 1.0")
    }

    func testSetTransparency() {
        controller.transparency = 0.7
        controller.showPanel()
        guard let panel = controller.panel else {
            XCTFail("Panel should exist")
            return
        }
        XCTAssertEqual(Double(panel.alphaValue), 0.7, accuracy: 0.01)
    }

    func testTransparencyClampedToMinimum() {
        controller.transparency = 0.1
        controller.showPanel()
        guard let panel = controller.panel else {
            XCTFail("Panel should exist")
            return
        }
        XCTAssertEqual(Double(panel.alphaValue), 0.3, accuracy: 0.01,
                       "Transparency should be clamped to minimum 0.3")
    }

    func testTransparencyClampedToMaximum() {
        controller.transparency = 1.5
        controller.showPanel()
        guard let panel = controller.panel else {
            XCTFail("Panel should exist")
            return
        }
        XCTAssertEqual(Double(panel.alphaValue), 1.0, accuracy: 0.01,
                       "Transparency should be clamped to maximum 1.0")
    }

    // MARK: - Position Persistence Between Toggles

    func testPositionRestoredAfterToggle() {
        controller.showPanel()
        guard let panel = controller.panel else {
            XCTFail("Panel should exist")
            return
        }

        // Move the panel to a specific position
        let testOrigin = NSPoint(x: 200, y: 300)
        panel.setFrameOrigin(testOrigin)

        // Hide and show
        controller.hidePanel()
        controller.showPanel()

        // Verify position is restored
        XCTAssertEqual(panel.frame.origin.x, testOrigin.x, accuracy: 1.0,
                       "X position should be restored after toggle")
        XCTAssertEqual(panel.frame.origin.y, testOrigin.y, accuracy: 1.0,
                       "Y position should be restored after toggle")
    }

    // MARK: - Content View

    func testPanelHasContentView() {
        controller.showPanel()
        XCTAssertNotNil(controller.panel?.contentView, "Panel should have a content view")
    }

    // MARK: - Frame Autosave

    func testFrameAutosaveNameIsSet() {
        controller.showPanel()
        XCTAssertEqual(controller.panel?.frameAutosaveName, SessionPanelController.frameAutosaveName)
    }

    // MARK: - Collection Behavior

    func testPanelCanJoinAllSpaces() {
        controller.showPanel()
        guard let panel = controller.panel else {
            XCTFail("Panel should exist")
            return
        }
        XCTAssertTrue(panel.collectionBehavior.contains(.canJoinAllSpaces),
                       "Panel should be able to join all spaces")
    }

    func testPanelIsFullScreenAuxiliary() {
        controller.showPanel()
        guard let panel = controller.panel else {
            XCTFail("Panel should exist")
            return
        }
        XCTAssertTrue(panel.collectionBehavior.contains(.fullScreenAuxiliary),
                       "Panel should be full screen auxiliary")
    }

    // MARK: - View Model

    func testViewModelIsCreatedWhenDatabaseManagerIsSet() {
        XCTAssertNotNil(controller.viewModel, "View model should be created after setDatabaseManager")
    }

    func testShowPanelRefreshesSessionData() throws {
        // Insert a session into the database
        try databaseManager.upsertSession(Session(
            sessionId: "test-session",
            cwd: "/Users/test/projects/TestProject",
            model: "claude-3.5-sonnet",
            status: .active
        ))

        // Show the panel - this should trigger loadSessions on the view model
        controller.showPanel()

        XCTAssertNotNil(controller.viewModel)
        XCTAssertFalse(controller.viewModel?.isEmpty ?? true, "View model should have loaded session data")
    }
}
