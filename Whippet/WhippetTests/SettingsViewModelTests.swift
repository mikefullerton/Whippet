import XCTest
@testable import Whippet

final class SettingsViewModelTests: XCTestCase {

    private var databaseManager: DatabaseManager!
    private var tempDBPath: String!

    override func setUpWithError() throws {
        try super.setUpWithError()
        let tempDir = NSTemporaryDirectory()
        tempDBPath = (tempDir as NSString).appendingPathComponent("whippet_settings_test_\(UUID().uuidString).db")
        databaseManager = try DatabaseManager(path: tempDBPath)
    }

    override func tearDownWithError() throws {
        databaseManager.close()
        try? FileManager.default.removeItem(atPath: tempDBPath)
        try super.tearDownWithError()
    }

    // MARK: - Default Values

    func testDefaultValuesWhenDatabaseEmpty() throws {
        let vm = SettingsViewModel(databaseManager: databaseManager)

        XCTAssertEqual(vm.stalenessTimeout, SettingsViewModel.defaultStalenessTimeout)
        XCTAssertEqual(vm.alwaysOnTop, SettingsViewModel.defaultAlwaysOnTop)
        XCTAssertEqual(vm.transparency, SettingsViewModel.defaultTransparency)
        XCTAssertEqual(vm.notifySessionStart, SettingsViewModel.defaultNotifySessionStart)
        XCTAssertEqual(vm.notifySessionEnd, SettingsViewModel.defaultNotifySessionEnd)
        XCTAssertEqual(vm.notifyStale, SettingsViewModel.defaultNotifyStale)
        XCTAssertEqual(vm.clickAction, SettingsViewModel.defaultClickAction)
        XCTAssertEqual(vm.customCommand, SettingsViewModel.defaultCustomCommand)
    }

    // MARK: - Staleness Timeout

    func testStalenessTimeoutPersists() throws {
        let vm = SettingsViewModel(databaseManager: databaseManager)
        vm.stalenessTimeout = 120

        let value = try databaseManager.getSetting(key: SettingsViewModel.stalenessTimeoutKey)
        XCTAssertEqual(value, "120")
    }

    func testStalenessTimeoutLoadsFromDatabase() throws {
        try databaseManager.setSetting(key: SettingsViewModel.stalenessTimeoutKey, value: "300")
        let vm = SettingsViewModel(databaseManager: databaseManager)

        XCTAssertEqual(vm.stalenessTimeout, 300)
    }

    func testStalenessTimeoutDisplay() throws {
        let vm = SettingsViewModel(databaseManager: databaseManager)

        vm.stalenessTimeout = 30
        XCTAssertEqual(vm.stalenessTimeoutDisplay, "30 seconds")

        vm.stalenessTimeout = 60
        XCTAssertEqual(vm.stalenessTimeoutDisplay, "1 minute")

        vm.stalenessTimeout = 120
        XCTAssertEqual(vm.stalenessTimeoutDisplay, "2 minutes")

        vm.stalenessTimeout = 90
        XCTAssertEqual(vm.stalenessTimeoutDisplay, "1m 30s")

        vm.stalenessTimeout = 1
        // Since slider minimum is 30 but we can set programmatically
        XCTAssertEqual(vm.stalenessTimeoutDisplay, "1 second")
    }

    // MARK: - Always On Top

    func testAlwaysOnTopPersists() throws {
        let vm = SettingsViewModel(databaseManager: databaseManager)
        vm.alwaysOnTop = false

        let value = try databaseManager.getSetting(key: SettingsViewModel.alwaysOnTopKey)
        XCTAssertEqual(value, "false")
    }

    func testAlwaysOnTopLoadsFromDatabase() throws {
        try databaseManager.setSetting(key: SettingsViewModel.alwaysOnTopKey, value: "false")
        let vm = SettingsViewModel(databaseManager: databaseManager)

        XCTAssertEqual(vm.alwaysOnTop, false)
    }

    func testAlwaysOnTopCallbackFires() throws {
        let vm = SettingsViewModel(databaseManager: databaseManager)
        var callbackValue: Bool?
        vm.onAlwaysOnTopChanged = { value in
            callbackValue = value
        }

        vm.alwaysOnTop = false
        XCTAssertEqual(callbackValue, false)

        vm.alwaysOnTop = true
        XCTAssertEqual(callbackValue, true)
    }

    // MARK: - Transparency

    func testTransparencyPersists() throws {
        let vm = SettingsViewModel(databaseManager: databaseManager)
        vm.transparency = 0.75

        let value = try databaseManager.getSetting(key: SettingsViewModel.transparencyKey)
        XCTAssertEqual(value, "0.75")
    }

    func testTransparencyLoadsFromDatabase() throws {
        try databaseManager.setSetting(key: SettingsViewModel.transparencyKey, value: "0.80")
        let vm = SettingsViewModel(databaseManager: databaseManager)

        XCTAssertEqual(vm.transparency, 0.80, accuracy: 0.01)
    }

    func testTransparencyClampedToMinimum() throws {
        let vm = SettingsViewModel(databaseManager: databaseManager)
        vm.transparency = 0.1

        XCTAssertEqual(vm.transparency, 0.3, accuracy: 0.01)
    }

    func testTransparencyClampedToMaximum() throws {
        let vm = SettingsViewModel(databaseManager: databaseManager)
        vm.transparency = 1.5

        XCTAssertEqual(vm.transparency, 1.0, accuracy: 0.01)
    }

    func testTransparencyCallbackFires() throws {
        let vm = SettingsViewModel(databaseManager: databaseManager)
        var callbackValue: CGFloat?
        vm.onTransparencyChanged = { value in
            callbackValue = value
        }

        vm.transparency = 0.75
        XCTAssertNotNil(callbackValue)
        XCTAssertEqual(Double(callbackValue!), 0.75, accuracy: 0.01)
    }

    // MARK: - Notification Toggles

    func testNotifySessionStartPersists() throws {
        let vm = SettingsViewModel(databaseManager: databaseManager)
        vm.notifySessionStart = true

        let value = try databaseManager.getSetting(key: SettingsViewModel.notifySessionStartKey)
        XCTAssertEqual(value, "true")
    }

    func testNotifySessionEndPersists() throws {
        let vm = SettingsViewModel(databaseManager: databaseManager)
        vm.notifySessionEnd = true

        let value = try databaseManager.getSetting(key: SettingsViewModel.notifySessionEndKey)
        XCTAssertEqual(value, "true")
    }

    func testNotifyStalePersists() throws {
        let vm = SettingsViewModel(databaseManager: databaseManager)
        vm.notifyStale = true

        let value = try databaseManager.getSetting(key: SettingsViewModel.notifyStaleKey)
        XCTAssertEqual(value, "true")
    }

    func testNotificationTogglesLoadFromDatabase() throws {
        try databaseManager.setSetting(key: SettingsViewModel.notifySessionStartKey, value: "true")
        try databaseManager.setSetting(key: SettingsViewModel.notifySessionEndKey, value: "true")
        try databaseManager.setSetting(key: SettingsViewModel.notifyStaleKey, value: "true")

        let vm = SettingsViewModel(databaseManager: databaseManager)

        XCTAssertTrue(vm.notifySessionStart)
        XCTAssertTrue(vm.notifySessionEnd)
        XCTAssertTrue(vm.notifyStale)
    }

    // MARK: - Click Action

    func testClickActionPersists() throws {
        let vm = SettingsViewModel(databaseManager: databaseManager)
        vm.clickAction = .copySessionId

        let value = try databaseManager.getSetting(key: SettingsViewModel.clickActionKey)
        XCTAssertEqual(value, SessionClickAction.copySessionId.rawValue)
    }

    func testClickActionLoadsFromDatabase() throws {
        try databaseManager.setSetting(key: SettingsViewModel.clickActionKey, value: SessionClickAction.openTranscript.rawValue)
        let vm = SettingsViewModel(databaseManager: databaseManager)

        XCTAssertEqual(vm.clickAction, .openTranscript)
    }

    func testAllClickActionsCanBeSelected() throws {
        let vm = SettingsViewModel(databaseManager: databaseManager)

        for action in SessionClickAction.allCases {
            vm.clickAction = action
            let value = try databaseManager.getSetting(key: SettingsViewModel.clickActionKey)
            XCTAssertEqual(value, action.rawValue, "Failed to persist action: \(action)")
        }
    }

    // MARK: - Custom Command

    func testCustomCommandPersists() throws {
        let vm = SettingsViewModel(databaseManager: databaseManager)
        vm.customCommand = "open -a 'Visual Studio Code' $CWD"

        let value = try databaseManager.getSetting(key: SettingsViewModel.customCommandKey)
        XCTAssertEqual(value, "open -a 'Visual Studio Code' $CWD")
    }

    func testCustomCommandLoadsFromDatabase() throws {
        try databaseManager.setSetting(key: SettingsViewModel.customCommandKey, value: "code $CWD")
        let vm = SettingsViewModel(databaseManager: databaseManager)

        XCTAssertEqual(vm.customCommand, "code $CWD")
    }

    // MARK: - Settings Shared With Other Components

    func testStalenessTimeoutSharedWithLivenessMonitor() throws {
        // Verify that SettingsViewModel uses the same key as SessionLivenessMonitor
        XCTAssertEqual(SettingsViewModel.stalenessTimeoutKey, SessionLivenessMonitor.stalenessTimeoutKey)

        // Set via view model, read via liveness monitor's mechanism
        let vm = SettingsViewModel(databaseManager: databaseManager)
        vm.stalenessTimeout = 180

        let monitor = SessionLivenessMonitor(databaseManager: databaseManager)
        XCTAssertEqual(monitor.currentTimeout(), 180)
    }

    func testClickActionSharedWithActionHandler() throws {
        // Verify that SettingsViewModel uses the same key as SessionActionHandler
        XCTAssertEqual(SettingsViewModel.clickActionKey, SessionActionHandler.clickActionKey)

        // Set via view model, read via action handler
        let vm = SettingsViewModel(databaseManager: databaseManager)
        vm.clickAction = .copySessionId

        let handler = SessionActionHandler(databaseManager: databaseManager)
        XCTAssertEqual(handler.currentAction, .copySessionId)
    }

    func testCustomCommandSharedWithActionHandler() throws {
        XCTAssertEqual(SettingsViewModel.customCommandKey, SessionActionHandler.customCommandKey)

        let vm = SettingsViewModel(databaseManager: databaseManager)
        vm.customCommand = "my-script $SESSION_ID"

        let handler = SessionActionHandler(databaseManager: databaseManager)
        XCTAssertEqual(handler.customCommandTemplate, "my-script $SESSION_ID")
    }

    // MARK: - Load From Database Overwrites Defaults

    func testLoadFromDatabaseOverwritesAllDefaults() throws {
        try databaseManager.setSetting(key: SettingsViewModel.stalenessTimeoutKey, value: "200")
        try databaseManager.setSetting(key: SettingsViewModel.alwaysOnTopKey, value: "false")
        try databaseManager.setSetting(key: SettingsViewModel.transparencyKey, value: "0.50")
        try databaseManager.setSetting(key: SettingsViewModel.notifySessionStartKey, value: "true")
        try databaseManager.setSetting(key: SettingsViewModel.notifySessionEndKey, value: "true")
        try databaseManager.setSetting(key: SettingsViewModel.notifyStaleKey, value: "true")
        try databaseManager.setSetting(key: SettingsViewModel.clickActionKey, value: "copy_session_id")
        try databaseManager.setSetting(key: SettingsViewModel.customCommandKey, value: "my-cmd")

        let vm = SettingsViewModel(databaseManager: databaseManager)

        XCTAssertEqual(vm.stalenessTimeout, 200)
        XCTAssertEqual(vm.alwaysOnTop, false)
        XCTAssertEqual(vm.transparency, 0.50, accuracy: 0.01)
        XCTAssertTrue(vm.notifySessionStart)
        XCTAssertTrue(vm.notifySessionEnd)
        XCTAssertTrue(vm.notifyStale)
        XCTAssertEqual(vm.clickAction, .copySessionId)
        XCTAssertEqual(vm.customCommand, "my-cmd")
    }
}
