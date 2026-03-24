import XCTest
import ServiceManagement
@testable import Whippet

/// Mock implementation of LaunchAtLoginServiceProtocol for unit testing.
final class MockLaunchAtLoginService: LaunchAtLoginServiceProtocol {
    var status: SMAppService.Status = .notRegistered
    var registerCallCount = 0
    var unregisterCallCount = 0
    var shouldThrowOnRegister = false
    var shouldThrowOnUnregister = false

    func register() throws {
        registerCallCount += 1
        if shouldThrowOnRegister {
            throw NSError(domain: "TestError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Mock register error"])
        }
        status = .enabled
    }

    func unregister() throws {
        unregisterCallCount += 1
        if shouldThrowOnUnregister {
            throw NSError(domain: "TestError", code: 2, userInfo: [NSLocalizedDescriptionKey: "Mock unregister error"])
        }
        status = .notRegistered
    }
}

final class LaunchAtLoginManagerTests: XCTestCase {

    private var databaseManager: DatabaseManager!
    private var tempDBPath: String!
    private var mockService: MockLaunchAtLoginService!

    override func setUpWithError() throws {
        try super.setUpWithError()
        let tempDir = NSTemporaryDirectory()
        tempDBPath = (tempDir as NSString).appendingPathComponent("whippet_launch_test_\(UUID().uuidString).db")
        databaseManager = try DatabaseManager(path: tempDBPath)
        mockService = MockLaunchAtLoginService()
    }

    override func tearDownWithError() throws {
        databaseManager.close()
        try? FileManager.default.removeItem(atPath: tempDBPath)
        try super.tearDownWithError()
    }

    // MARK: - isEnabled

    func testIsEnabledReflectsServiceStatus() throws {
        let manager = LaunchAtLoginManager(databaseManager: databaseManager, service: mockService)

        mockService.status = .notRegistered
        XCTAssertFalse(manager.isEnabled)

        mockService.status = .enabled
        XCTAssertTrue(manager.isEnabled)

        mockService.status = .requiresApproval
        XCTAssertFalse(manager.isEnabled)
    }

    // MARK: - setEnabled

    func testSetEnabledTrueCallsRegister() throws {
        let manager = LaunchAtLoginManager(databaseManager: databaseManager, service: mockService)

        try manager.setEnabled(true)

        XCTAssertEqual(mockService.registerCallCount, 1)
        XCTAssertEqual(mockService.unregisterCallCount, 0)
        XCTAssertTrue(manager.isEnabled)
    }

    func testSetEnabledFalseCallsUnregister() throws {
        let manager = LaunchAtLoginManager(databaseManager: databaseManager, service: mockService)
        mockService.status = .enabled

        try manager.setEnabled(false)

        XCTAssertEqual(mockService.unregisterCallCount, 1)
        XCTAssertEqual(mockService.registerCallCount, 0)
        XCTAssertFalse(manager.isEnabled)
    }

    func testSetEnabledPersistsToDatabase() throws {
        let manager = LaunchAtLoginManager(databaseManager: databaseManager, service: mockService)

        try manager.setEnabled(true)
        let value = try databaseManager.getSetting(key: LaunchAtLoginManager.launchAtLoginKey)
        XCTAssertEqual(value, "true")

        try manager.setEnabled(false)
        let value2 = try databaseManager.getSetting(key: LaunchAtLoginManager.launchAtLoginKey)
        XCTAssertEqual(value2, "false")
    }

    func testSetEnabledThrowsOnRegisterFailure() throws {
        let manager = LaunchAtLoginManager(databaseManager: databaseManager, service: mockService)
        mockService.shouldThrowOnRegister = true

        XCTAssertThrowsError(try manager.setEnabled(true))
        XCTAssertFalse(manager.isEnabled)
    }

    func testSetEnabledThrowsOnUnregisterFailure() throws {
        let manager = LaunchAtLoginManager(databaseManager: databaseManager, service: mockService)
        mockService.status = .enabled
        mockService.shouldThrowOnUnregister = true

        XCTAssertThrowsError(try manager.setEnabled(false))
        // Status should remain enabled since unregister failed
        XCTAssertTrue(manager.isEnabled)
    }

    // MARK: - Prompt State

    func testHasShownPromptDefaultsToFalse() throws {
        let manager = LaunchAtLoginManager(databaseManager: databaseManager, service: mockService)

        XCTAssertFalse(manager.hasShownPrompt)
    }

    func testMarkPromptShownPersists() throws {
        let manager = LaunchAtLoginManager(databaseManager: databaseManager, service: mockService)

        manager.markPromptShown()

        XCTAssertTrue(manager.hasShownPrompt)

        // Verify it persisted to the database
        let value = try databaseManager.getSetting(key: LaunchAtLoginManager.launchAtLoginPromptShownKey)
        XCTAssertEqual(value, "true")
    }

    func testHasShownPromptReadsFromDatabase() throws {
        try databaseManager.setSetting(key: LaunchAtLoginManager.launchAtLoginPromptShownKey, value: "true")

        let manager = LaunchAtLoginManager(databaseManager: databaseManager, service: mockService)

        XCTAssertTrue(manager.hasShownPrompt)
    }

    // MARK: - SettingsViewModel Integration

    func testSettingsViewModelLaunchAtLoginToggle() throws {
        let manager = LaunchAtLoginManager(databaseManager: databaseManager, service: mockService)
        let vm = SettingsViewModel(databaseManager: databaseManager, launchAtLoginManager: manager)

        XCTAssertFalse(vm.launchAtLogin)

        vm.launchAtLogin = true
        XCTAssertTrue(manager.isEnabled)
        XCTAssertEqual(mockService.registerCallCount, 1)

        vm.launchAtLogin = false
        XCTAssertFalse(manager.isEnabled)
        XCTAssertEqual(mockService.unregisterCallCount, 1)
    }

    func testSettingsViewModelReflectsActualState() throws {
        mockService.status = .enabled
        let manager = LaunchAtLoginManager(databaseManager: databaseManager, service: mockService)
        let vm = SettingsViewModel(databaseManager: databaseManager, launchAtLoginManager: manager)

        XCTAssertTrue(vm.launchAtLogin)
    }

    func testSettingsViewModelShowsPromptOnFirstLaunch() throws {
        let manager = LaunchAtLoginManager(databaseManager: databaseManager, service: mockService)
        let vm = SettingsViewModel(databaseManager: databaseManager, launchAtLoginManager: manager)

        XCTAssertTrue(vm.shouldShowLaunchAtLoginPrompt)
    }

    func testSettingsViewModelHidesPromptAfterDismissal() throws {
        let manager = LaunchAtLoginManager(databaseManager: databaseManager, service: mockService)
        let vm = SettingsViewModel(databaseManager: databaseManager, launchAtLoginManager: manager)

        vm.dismissLaunchAtLoginPrompt()

        XCTAssertFalse(vm.shouldShowLaunchAtLoginPrompt)
        XCTAssertTrue(manager.hasShownPrompt)
    }

    func testSettingsViewModelHidesPromptIfAlreadyShown() throws {
        let manager = LaunchAtLoginManager(databaseManager: databaseManager, service: mockService)
        manager.markPromptShown()

        let vm = SettingsViewModel(databaseManager: databaseManager, launchAtLoginManager: manager)

        XCTAssertFalse(vm.shouldShowLaunchAtLoginPrompt)
    }

    func testSettingsViewModelRevertsOnRegisterFailure() throws {
        mockService.shouldThrowOnRegister = true
        let manager = LaunchAtLoginManager(databaseManager: databaseManager, service: mockService)
        let vm = SettingsViewModel(databaseManager: databaseManager, launchAtLoginManager: manager)

        vm.launchAtLogin = true

        // Should revert to false because register threw
        XCTAssertFalse(vm.launchAtLogin)
    }

    func testConfigureLaunchAtLoginSyncsState() throws {
        mockService.status = .enabled
        let manager = LaunchAtLoginManager(databaseManager: databaseManager, service: mockService)
        let vm = SettingsViewModel(databaseManager: databaseManager)

        XCTAssertFalse(vm.launchAtLogin)

        vm.configureLaunchAtLogin(manager)

        XCTAssertTrue(vm.launchAtLogin)
    }

    func testSettingsKeysMatch() throws {
        XCTAssertEqual(SettingsViewModel.launchAtLoginKey, LaunchAtLoginManager.launchAtLoginKey)
        XCTAssertEqual(SettingsViewModel.launchAtLoginPromptShownKey, LaunchAtLoginManager.launchAtLoginPromptShownKey)
    }
}
