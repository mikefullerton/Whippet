import XCTest
import UserNotifications
@testable import Whippet

/// Tests for NotificationManager covering authorization, per-event-type toggles,
/// notification content, and notification click handling.
final class NotificationManagerTests: XCTestCase {

    private var databaseManager: DatabaseManager!
    private var notificationManager: NotificationManager!
    private var mockCenter: MockNotificationCenter!
    private var tempDBPath: String!

    override func setUp() {
        super.setUp()

        // Create a temp database
        let tempDir = NSTemporaryDirectory()
        tempDBPath = (tempDir as NSString).appendingPathComponent(
            "whippet-notification-test-\(UUID().uuidString).db"
        )
        databaseManager = try! DatabaseManager(path: tempDBPath)

        // Create with mock notification center
        mockCenter = MockNotificationCenter()
        notificationManager = NotificationManager(
            databaseManager: databaseManager,
            notificationCenter: mockCenter
        )
    }

    override func tearDown() {
        databaseManager.close()
        try? FileManager.default.removeItem(atPath: tempDBPath)
        super.tearDown()
    }

    // MARK: - Authorization Tests

    func testRequestAuthorizationCallsCenter() {
        notificationManager.requestAuthorization()

        XCTAssertTrue(
            mockCenter.requestAuthorizationCalled,
            "Should call requestAuthorization on the notification center"
        )
        XCTAssertEqual(
            mockCenter.requestedOptions,
            [.alert, .sound],
            "Should request alert and sound options"
        )
    }

    func testAuthorizationGrantedUpdatesFlag() {
        mockCenter.authorizationGrantResult = true
        notificationManager.requestAuthorization()

        XCTAssertTrue(
            notificationManager.isAuthorized,
            "Should be authorized after granting"
        )
    }

    func testAuthorizationDeniedUpdatesFlag() {
        mockCenter.authorizationGrantResult = false
        notificationManager.requestAuthorization()

        XCTAssertFalse(
            notificationManager.isAuthorized,
            "Should not be authorized after denial"
        )
    }

    // MARK: - Settings Toggle Tests

    func testNotificationDisabledByDefaultForSessionStart() {
        setAuthorized(true)

        let enabled = notificationManager.isNotificationEnabled(
            forKey: SettingsViewModel.notifySessionStartKey
        )
        XCTAssertFalse(enabled, "SessionStart notifications should be disabled by default")
    }

    func testNotificationDisabledByDefaultForSessionEnd() {
        setAuthorized(true)

        let enabled = notificationManager.isNotificationEnabled(
            forKey: SettingsViewModel.notifySessionEndKey
        )
        XCTAssertFalse(enabled, "SessionEnd notifications should be disabled by default")
    }

    func testNotificationDisabledByDefaultForStale() {
        setAuthorized(true)

        let enabled = notificationManager.isNotificationEnabled(
            forKey: SettingsViewModel.notifyStaleKey
        )
        XCTAssertFalse(enabled, "Stale notifications should be disabled by default")
    }

    func testNotificationEnabledWhenSettingIsTrue() throws {
        setAuthorized(true)
        try databaseManager.setSetting(
            key: SettingsViewModel.notifySessionStartKey,
            value: "true"
        )

        let enabled = notificationManager.isNotificationEnabled(
            forKey: SettingsViewModel.notifySessionStartKey
        )
        XCTAssertTrue(enabled, "Should be enabled when setting is 'true'")
    }

    func testNotificationDisabledWhenSettingIsFalse() throws {
        setAuthorized(true)
        try databaseManager.setSetting(
            key: SettingsViewModel.notifySessionStartKey,
            value: "false"
        )

        let enabled = notificationManager.isNotificationEnabled(
            forKey: SettingsViewModel.notifySessionStartKey
        )
        XCTAssertFalse(enabled, "Should be disabled when setting is 'false'")
    }

    func testNotificationDisabledWhenNotAuthorized() throws {
        setAuthorized(false)
        try databaseManager.setSetting(
            key: SettingsViewModel.notifySessionStartKey,
            value: "true"
        )

        let enabled = notificationManager.isNotificationEnabled(
            forKey: SettingsViewModel.notifySessionStartKey
        )
        XCTAssertFalse(
            enabled,
            "Should be disabled when not authorized, even if setting is true"
        )
    }

    // MARK: - SessionStart Notification Tests

    func testNotifySessionStartPostsNotification() throws {
        setAuthorized(true)
        try databaseManager.setSetting(
            key: SettingsViewModel.notifySessionStartKey,
            value: "true"
        )

        notificationManager.notifySessionStart(
            sessionId: "abc-123-def",
            projectName: "MyProject"
        )

        XCTAssertEqual(mockCenter.addedRequests.count, 1, "Should post one notification")

        let request = mockCenter.addedRequests.first!
        XCTAssertEqual(request.content.title, "Session Started")
        XCTAssertTrue(
            request.content.body.contains("MyProject"),
            "Body should contain project name"
        )
        XCTAssertTrue(
            request.content.body.contains("abc-123-"),
            "Body should contain abbreviated session ID"
        )
        XCTAssertEqual(
            request.content.categoryIdentifier,
            NotificationManager.sessionCategoryIdentifier
        )
        XCTAssertEqual(
            request.content.userInfo[NotificationManager.sessionIdKey] as? String,
            "abc-123-def"
        )
        XCTAssertEqual(
            request.content.userInfo[NotificationManager.eventTypeKey] as? String,
            "SessionStart"
        )
    }

    func testNotifySessionStartSkippedWhenDisabled() throws {
        setAuthorized(true)
        try databaseManager.setSetting(
            key: SettingsViewModel.notifySessionStartKey,
            value: "false"
        )

        notificationManager.notifySessionStart(
            sessionId: "abc-123",
            projectName: "MyProject"
        )

        XCTAssertTrue(mockCenter.addedRequests.isEmpty, "Should not post when disabled")
    }

    // MARK: - SessionEnd Notification Tests

    func testNotifySessionEndPostsNotification() throws {
        setAuthorized(true)
        try databaseManager.setSetting(
            key: SettingsViewModel.notifySessionEndKey,
            value: "true"
        )

        notificationManager.notifySessionEnd(
            sessionId: "xyz-789",
            projectName: "OtherProject"
        )

        XCTAssertEqual(mockCenter.addedRequests.count, 1)

        let request = mockCenter.addedRequests.first!
        XCTAssertEqual(request.content.title, "Session Ended")
        XCTAssertTrue(request.content.body.contains("OtherProject"))
        XCTAssertEqual(
            request.content.userInfo[NotificationManager.eventTypeKey] as? String,
            "SessionEnd"
        )
    }

    func testNotifySessionEndSkippedWhenDisabled() {
        setAuthorized(true)
        // Default is false, so don't set anything

        notificationManager.notifySessionEnd(
            sessionId: "xyz-789",
            projectName: "OtherProject"
        )

        XCTAssertTrue(mockCenter.addedRequests.isEmpty)
    }

    // MARK: - Stale Notification Tests

    func testNotifySessionStalePostsNotification() throws {
        setAuthorized(true)
        try databaseManager.setSetting(
            key: SettingsViewModel.notifyStaleKey,
            value: "true"
        )

        notificationManager.notifySessionStale(
            sessionId: "stale-id-123",
            projectName: "StaleProject"
        )

        XCTAssertEqual(mockCenter.addedRequests.count, 1)

        let request = mockCenter.addedRequests.first!
        XCTAssertEqual(request.content.title, "Session Stale")
        XCTAssertTrue(request.content.body.contains("StaleProject"))
        XCTAssertEqual(
            request.content.userInfo[NotificationManager.eventTypeKey] as? String,
            "Stale"
        )
    }

    func testNotifySessionStaleSkippedWhenDisabled() {
        setAuthorized(true)

        notificationManager.notifySessionStale(
            sessionId: "stale-id",
            projectName: "Project"
        )

        XCTAssertTrue(mockCenter.addedRequests.isEmpty)
    }

    // MARK: - Notification Click Tests

    func testNotificationClickCallbackProperty() {
        var callbackInvoked = false
        notificationManager.onNotificationClicked = {
            callbackInvoked = true
        }

        XCTAssertNotNil(notificationManager.onNotificationClicked)
        notificationManager.onNotificationClicked?()
        XCTAssertTrue(
            callbackInvoked,
            "Callback should be invoked when notification is clicked"
        )
    }

    // MARK: - Category Registration Tests

    func testCategoriesRegistered() {
        XCTAssertTrue(
            mockCenter.setCategoriesCalled,
            "Should register notification categories on init"
        )
        XCTAssertEqual(mockCenter.registeredCategories.count, 1)
        XCTAssertEqual(
            mockCenter.registeredCategories.first?.identifier,
            NotificationManager.sessionCategoryIdentifier
        )
    }

    // MARK: - Session ID Abbreviation Tests

    func testShortSessionIdNotAbbreviated() {
        let result = notificationManager.abbreviateSessionId("short")
        XCTAssertEqual(result, "short", "Short ID should not be abbreviated")
    }

    func testExactly8CharSessionIdNotAbbreviated() {
        let result = notificationManager.abbreviateSessionId("abcdefgh")
        XCTAssertEqual(result, "abcdefgh", "Exactly 8-char ID should not be abbreviated")
    }

    func testLongSessionIdAbbreviated() {
        let result = notificationManager.abbreviateSessionId("abcdefghijklmnop")
        XCTAssertEqual(
            result, "abcdefgh...",
            "Long ID should be abbreviated to 8 chars + ..."
        )
    }

    // MARK: - Multiple Event Types Test

    func testOnlyEnabledEventTypesPostNotifications() throws {
        setAuthorized(true)
        try databaseManager.setSetting(
            key: SettingsViewModel.notifySessionStartKey,
            value: "true"
        )
        try databaseManager.setSetting(
            key: SettingsViewModel.notifySessionEndKey,
            value: "false"
        )
        try databaseManager.setSetting(
            key: SettingsViewModel.notifyStaleKey,
            value: "true"
        )

        notificationManager.notifySessionStart(sessionId: "s1", projectName: "P")
        notificationManager.notifySessionEnd(sessionId: "s2", projectName: "P")
        notificationManager.notifySessionStale(sessionId: "s3", projectName: "P")

        XCTAssertEqual(
            mockCenter.addedRequests.count, 2,
            "Should post 2 notifications (start + stale, not end)"
        )

        let titles = mockCenter.addedRequests.map { $0.content.title }
        XCTAssertTrue(titles.contains("Session Started"))
        XCTAssertTrue(titles.contains("Session Stale"))
        XCTAssertFalse(titles.contains("Session Ended"))
    }

    // MARK: - Notification Sound Tests

    func testNotificationsHaveSound() throws {
        setAuthorized(true)
        try databaseManager.setSetting(
            key: SettingsViewModel.notifySessionStartKey,
            value: "true"
        )

        notificationManager.notifySessionStart(sessionId: "s1", projectName: "P")

        XCTAssertNotNil(
            mockCenter.addedRequests.first?.content.sound,
            "Notifications should have sound"
        )
    }

    // MARK: - Notification Identifier Tests

    func testNotificationIdentifiersAreUnique() throws {
        setAuthorized(true)
        try databaseManager.setSetting(
            key: SettingsViewModel.notifySessionStartKey,
            value: "true"
        )
        try databaseManager.setSetting(
            key: SettingsViewModel.notifySessionEndKey,
            value: "true"
        )

        notificationManager.notifySessionStart(sessionId: "session-1", projectName: "P")
        notificationManager.notifySessionEnd(sessionId: "session-1", projectName: "P")

        XCTAssertEqual(mockCenter.addedRequests.count, 2)

        let identifiers = mockCenter.addedRequests.map { $0.identifier }
        XCTAssertEqual(
            Set(identifiers).count, 2,
            "Start and end notifications for the same session should have different identifiers"
        )
        XCTAssertTrue(identifiers[0].contains("session-start-"))
        XCTAssertTrue(identifiers[1].contains("session-end-"))
    }

    // MARK: - Delegate Assignment Tests

    func testDelegateSetOnInit() {
        XCTAssertTrue(
            mockCenter.delegateSet,
            "Should set delegate on the notification center during init"
        )
    }

    // MARK: - Helper

    /// Sets the isAuthorized flag directly for testing (bypasses async auth flow).
    private func setAuthorized(_ authorized: Bool) {
        mockCenter.authorizationGrantResult = authorized
        notificationManager.requestAuthorization()
    }
}

// MARK: - Mock Notification Center

/// A mock implementation of NotificationCenterProtocol that captures all calls
/// for verification in tests. Executes callbacks synchronously for deterministic testing.
final class MockNotificationCenter: NotificationCenterProtocol {

    // MARK: - Delegate

    weak var delegate: (any UNUserNotificationCenterDelegate)?
    var delegateSet: Bool { delegate != nil }

    // MARK: - Authorization

    var requestAuthorizationCalled = false
    var requestedOptions: UNAuthorizationOptions = []
    var authorizationGrantResult = false
    var authorizationError: Error?

    func requestAuthorization(
        options: UNAuthorizationOptions,
        completionHandler: @escaping @Sendable (Bool, (any Error)?) -> Void
    ) {
        requestAuthorizationCalled = true
        requestedOptions = options
        // Call synchronously for deterministic tests
        completionHandler(authorizationGrantResult, authorizationError)
    }

    // MARK: - Notification Settings

    func getNotificationSettings(completionHandler: @escaping @Sendable (UNNotificationSettings) -> Void) {
        // Cannot easily create UNNotificationSettings for testing;
        // tests use isAuthorized directly instead.
    }

    // MARK: - Categories

    var setCategoriesCalled = false
    var registeredCategories: Set<UNNotificationCategory> = []

    func setNotificationCategories(_ categories: Set<UNNotificationCategory>) {
        setCategoriesCalled = true
        registeredCategories = categories
    }

    // MARK: - Notification Requests

    var addedRequests: [UNNotificationRequest] = []
    var addError: Error?

    func add(
        _ request: UNNotificationRequest,
        withCompletionHandler completionHandler: (@Sendable ((any Error)?) -> Void)?
    ) {
        addedRequests.append(request)
        completionHandler?(addError)
    }
}
