import XCTest
@testable import Whippet

final class HookInstallerTests: XCTestCase {

    private var tempDir: URL!
    private var settingsURL: URL!
    private var dropDir: String!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("WhippetHookInstallerTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        settingsURL = tempDir.appendingPathComponent("settings.json")
        dropDir = tempDir.appendingPathComponent("session-events").path
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
        try super.tearDownWithError()
    }

    private func makeInstaller() -> HookInstaller {
        HookInstaller(settingsURL: settingsURL, dropDirectory: dropDir)
    }

    // MARK: - Installation into empty/missing settings

    func testInstallHooksCreatesSettingsFileWhenMissing() throws {
        let installer = makeInstaller()

        XCTAssertFalse(FileManager.default.fileExists(atPath: settingsURL.path))

        let result = installer.installHooks()

        XCTAssertEqual(result, .installed)
        XCTAssertTrue(FileManager.default.fileExists(atPath: settingsURL.path))
    }

    func testInstallHooksWithEmptySettingsFile() throws {
        try Data().write(to: settingsURL)
        let installer = makeInstaller()

        let result = installer.installHooks()

        XCTAssertEqual(result, .installed)

        // Verify the settings file now contains hooks
        let settings = try installer.loadSettings()
        let hooks = settings["hooks"] as? [String: Any]
        XCTAssertNotNil(hooks)
    }

    func testInstallHooksWithEmptyJsonObject() throws {
        try "{}".data(using: .utf8)!.write(to: settingsURL)
        let installer = makeInstaller()

        let result = installer.installHooks()

        XCTAssertEqual(result, .installed)

        let settings = try installer.loadSettings()
        let hooks = settings["hooks"] as? [String: Any]
        XCTAssertNotNil(hooks)
    }

    // MARK: - All event types are installed

    func testAllHookEventTypesAreInstalled() throws {
        let installer = makeInstaller()

        let result = installer.installHooks()
        XCTAssertEqual(result, .installed)

        let settings = try installer.loadSettings()
        let hooks = settings["hooks"] as? [String: Any]
        XCTAssertNotNil(hooks)

        for eventType in HookInstaller.hookedEventTypes {
            let matcherGroups = hooks?[eventType] as? [[String: Any]]
            XCTAssertNotNil(matcherGroups, "Missing hook for event type: \(eventType)")
            XCTAssertEqual(matcherGroups?.count, 1, "Expected exactly one matcher group for \(eventType)")

            // Verify the hook contains the Whippet marker
            let hookList = matcherGroups?.first?["hooks"] as? [[String: Any]]
            XCTAssertNotNil(hookList, "Missing hooks array for \(eventType)")
            let command = hookList?.first?["command"] as? String
            XCTAssertNotNil(command, "Missing command for \(eventType)")
            XCTAssertTrue(
                command?.contains(HookInstaller.whippetMarker) == true,
                "Command for \(eventType) missing Whippet marker"
            )
        }
    }

    // MARK: - Existing hooks are preserved

    func testExistingHooksArePreserved() throws {
        // Write settings with an existing PreToolUse hook
        let existingSettings: [String: Any] = [
            "hooks": [
                "PreToolUse": [
                    [
                        "matcher": "Bash",
                        "hooks": [
                            ["type": "command", "command": "echo 'existing hook'"]
                        ]
                    ]
                ]
            ]
        ]
        let data = try JSONSerialization.data(withJSONObject: existingSettings, options: .prettyPrinted)
        try data.write(to: settingsURL)

        let installer = makeInstaller()
        let result = installer.installHooks()
        XCTAssertEqual(result, .installed)

        // Verify the existing hook is still there
        let settings = try installer.loadSettings()
        let hooks = settings["hooks"] as? [String: Any]
        let preToolUseGroups = hooks?["PreToolUse"] as? [[String: Any]]
        XCTAssertNotNil(preToolUseGroups)
        XCTAssertEqual(preToolUseGroups?.count, 2, "Should have existing hook + Whippet hook")

        // First group should be the existing one
        let existingGroup = preToolUseGroups?.first
        let existingMatcher = existingGroup?["matcher"] as? String
        XCTAssertEqual(existingMatcher, "Bash")
        let existingHookList = existingGroup?["hooks"] as? [[String: Any]]
        let existingCommand = existingHookList?.first?["command"] as? String
        XCTAssertEqual(existingCommand, "echo 'existing hook'")

        // Second group should be the Whippet hook
        let whippetGroup = preToolUseGroups?.last
        let whippetHookList = whippetGroup?["hooks"] as? [[String: Any]]
        let whippetCommand = whippetHookList?.first?["command"] as? String
        XCTAssertTrue(whippetCommand?.contains(HookInstaller.whippetMarker) == true)
    }

    func testExistingNonHookSettingsArePreserved() throws {
        // Write settings with other config besides hooks
        let existingSettings: [String: Any] = [
            "permissions": ["allow": ["Bash"]],
            "model": "claude-sonnet-4-6",
        ]
        let data = try JSONSerialization.data(withJSONObject: existingSettings, options: .prettyPrinted)
        try data.write(to: settingsURL)

        let installer = makeInstaller()
        let result = installer.installHooks()
        XCTAssertEqual(result, .installed)

        let settings = try installer.loadSettings()
        // Verify non-hook settings are preserved
        XCTAssertNotNil(settings["permissions"])
        XCTAssertEqual(settings["model"] as? String, "claude-sonnet-4-6")
        // And hooks are installed
        XCTAssertNotNil(settings["hooks"])
    }

    // MARK: - Skip re-installation

    func testSkipsReinstallationWhenHooksAlreadyPresent() throws {
        let installer = makeInstaller()

        // First install
        let firstResult = installer.installHooks()
        XCTAssertEqual(firstResult, .installed)

        // Capture the file contents after first install
        let firstData = try Data(contentsOf: settingsURL)

        // Second install should detect hooks and skip
        let secondResult = installer.installHooks()
        XCTAssertEqual(secondResult, .alreadyInstalled)

        // File should be unchanged
        let secondData = try Data(contentsOf: settingsURL)
        XCTAssertEqual(firstData, secondData)
    }

    func testDetectsHooksAlreadyInstalledWithPartialInstall() throws {
        // Simulate a partial install: only one event type has a Whippet hook
        let partialSettings: [String: Any] = [
            "hooks": [
                "SessionStart": [
                    [
                        "hooks": [
                            ["type": "command", "command": "\(HookInstaller.whippetMarker)\necho 'test'"]
                        ]
                    ]
                ]
            ]
        ]
        let data = try JSONSerialization.data(withJSONObject: partialSettings, options: .prettyPrinted)
        try data.write(to: settingsURL)

        let installer = makeInstaller()
        let result = installer.installHooks()
        // Should detect that Whippet hooks exist even if not all event types are present
        XCTAssertEqual(result, .alreadyInstalled)
    }

    // MARK: - Detection

    func testHooksAlreadyInstalledReturnsFalseForEmptySettings() {
        let installer = makeInstaller()
        XCTAssertFalse(installer.hooksAlreadyInstalled(in: [:]))
    }

    func testHooksAlreadyInstalledReturnsFalseForNonWhippetHooks() {
        let installer = makeInstaller()
        let settings: [String: Any] = [
            "hooks": [
                "PreToolUse": [
                    [
                        "hooks": [
                            ["type": "command", "command": "echo 'not whippet'"]
                        ]
                    ]
                ]
            ]
        ]
        XCTAssertFalse(installer.hooksAlreadyInstalled(in: settings))
    }

    func testHooksAlreadyInstalledReturnsTrueForWhippetHooks() {
        let installer = makeInstaller()
        let settings: [String: Any] = [
            "hooks": [
                "SessionStart": [
                    [
                        "hooks": [
                            ["type": "command", "command": "\(HookInstaller.whippetMarker)\nsome command"]
                        ]
                    ]
                ]
            ]
        ]
        XCTAssertTrue(installer.hooksAlreadyInstalled(in: settings))
    }

    // MARK: - Uninstallation

    func testUninstallRemovesWhippetHooks() throws {
        let installer = makeInstaller()

        // Install first
        let installResult = installer.installHooks()
        XCTAssertEqual(installResult, .installed)

        // Uninstall
        let removed = installer.uninstallHooks()
        XCTAssertTrue(removed)

        // Verify hooks are gone
        let settings = try installer.loadSettings()
        XCTAssertFalse(installer.hooksAlreadyInstalled(in: settings))
    }

    func testUninstallPreservesNonWhippetHooks() throws {
        // Write settings with both a user hook and then install Whippet hooks
        let existingSettings: [String: Any] = [
            "hooks": [
                "PreToolUse": [
                    [
                        "matcher": "Bash",
                        "hooks": [
                            ["type": "command", "command": "echo 'user hook'"]
                        ]
                    ]
                ]
            ]
        ]
        let data = try JSONSerialization.data(withJSONObject: existingSettings, options: .prettyPrinted)
        try data.write(to: settingsURL)

        let installer = makeInstaller()
        let installResult = installer.installHooks()
        XCTAssertEqual(installResult, .installed)

        // Now uninstall
        let removed = installer.uninstallHooks()
        XCTAssertTrue(removed)

        // Verify user hook is still there
        let settings = try installer.loadSettings()
        let hooks = settings["hooks"] as? [String: Any]
        let preToolGroups = hooks?["PreToolUse"] as? [[String: Any]]
        XCTAssertEqual(preToolGroups?.count, 1)
        let remainingHooks = preToolGroups?.first?["hooks"] as? [[String: Any]]
        let command = remainingHooks?.first?["command"] as? String
        XCTAssertEqual(command, "echo 'user hook'")
    }

    func testUninstallReturnsFalseWhenNoHooksPresent() throws {
        try "{}".data(using: .utf8)!.write(to: settingsURL)
        let installer = makeInstaller()
        let removed = installer.uninstallHooks()
        XCTAssertFalse(removed)
    }

    // MARK: - Hook command generation

    func testHookCommandContainsMarker() {
        let installer = makeInstaller()
        for eventType in HookInstaller.hookedEventTypes {
            let command = installer.makeHookCommand(eventType: eventType)
            XCTAssertTrue(
                command.contains(HookInstaller.whippetMarker),
                "Command for \(eventType) should contain the Whippet marker"
            )
        }
    }

    func testHookCommandContainsDropDirectory() {
        let installer = makeInstaller()
        for eventType in HookInstaller.hookedEventTypes {
            let command = installer.makeHookCommand(eventType: eventType)
            XCTAssertTrue(
                command.contains(dropDir),
                "Command for \(eventType) should reference the drop directory"
            )
        }
    }

    func testHookCommandUsesJq() {
        let installer = makeInstaller()
        for eventType in HookInstaller.hookedEventTypes {
            let command = installer.makeHookCommand(eventType: eventType)
            XCTAssertTrue(
                command.contains("jq"),
                "Command for \(eventType) should use jq for JSON processing"
            )
        }
    }

    func testHookCommandIncludesEventType() {
        let installer = makeInstaller()
        for eventType in HookInstaller.hookedEventTypes {
            let command = installer.makeHookCommand(eventType: eventType)
            XCTAssertTrue(
                command.contains(eventType),
                "Command for \(eventType) should include the event type in the jq filter"
            )
        }
    }

    func testHookCommandAlwaysExitsZero() {
        let installer = makeInstaller()
        for eventType in HookInstaller.hookedEventTypes {
            let command = installer.makeHookCommand(eventType: eventType)
            XCTAssertTrue(
                command.contains("exit 0"),
                "Command for \(eventType) should always exit 0 to not block Claude Code"
            )
        }
    }

    func testHookCommandCreatesDropDirectory() {
        let installer = makeInstaller()
        for eventType in HookInstaller.hookedEventTypes {
            let command = installer.makeHookCommand(eventType: eventType)
            XCTAssertTrue(
                command.contains("mkdir -p"),
                "Command for \(eventType) should create the drop directory if needed"
            )
        }
    }

    // MARK: - Event-specific jq filter fields

    func testSessionStartCommandExtractsModel() {
        let installer = makeInstaller()
        let command = installer.makeHookCommand(eventType: "SessionStart")
        XCTAssertTrue(command.contains("model"))
    }

    func testSessionEndCommandExtractsReason() {
        let installer = makeInstaller()
        let command = installer.makeHookCommand(eventType: "SessionEnd")
        XCTAssertTrue(command.contains("reason"))
    }

    func testPreToolUseCommandExtractsToolName() {
        let installer = makeInstaller()
        let command = installer.makeHookCommand(eventType: "PreToolUse")
        XCTAssertTrue(command.contains("tool_name"))
    }

    func testPostToolUseCommandExtractsToolResponse() {
        let installer = makeInstaller()
        let command = installer.makeHookCommand(eventType: "PostToolUse")
        XCTAssertTrue(command.contains("tool_response"))
    }

    func testNotificationCommandExtractsMessage() {
        let installer = makeInstaller()
        let command = installer.makeHookCommand(eventType: "Notification")
        XCTAssertTrue(command.contains("message"))
        XCTAssertTrue(command.contains("notification_type"))
    }

    func testSubagentStartCommandExtractsAgentFields() {
        let installer = makeInstaller()
        let command = installer.makeHookCommand(eventType: "SubagentStart")
        XCTAssertTrue(command.contains("agent_id"))
        XCTAssertTrue(command.contains("agent_type"))
    }

    // MARK: - Settings I/O

    func testLoadSettingsReturnsEmptyDictForMissingFile() throws {
        let installer = makeInstaller()
        let settings = try installer.loadSettings()
        XCTAssertTrue(settings.isEmpty)
    }

    func testLoadSettingsCreatesParentDirectory() throws {
        let nestedURL = tempDir
            .appendingPathComponent("nested")
            .appendingPathComponent("dir")
            .appendingPathComponent("settings.json")
        let installer = HookInstaller(settingsURL: nestedURL, dropDirectory: dropDir)

        // Should not throw even though parent dirs don't exist
        let settings = try installer.loadSettings()
        XCTAssertTrue(settings.isEmpty)

        // Verify directory was created
        let parentDir = nestedURL.deletingLastPathComponent()
        var isDir: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: parentDir.path, isDirectory: &isDir))
        XCTAssertTrue(isDir.boolValue)
    }

    func testSaveAndLoadRoundTrip() throws {
        let installer = makeInstaller()
        let original: [String: Any] = [
            "model": "claude-sonnet-4-6",
            "hooks": [
                "SessionStart": [
                    ["hooks": [["type": "command", "command": "echo test"]]]
                ]
            ]
        ]

        try installer.saveSettings(original)
        let loaded = try installer.loadSettings()

        XCTAssertEqual(loaded["model"] as? String, "claude-sonnet-4-6")
        let hooks = loaded["hooks"] as? [String: Any]
        XCTAssertNotNil(hooks?["SessionStart"])
    }

    func testInvalidSettingsFileThrows() throws {
        try "not valid json".data(using: .utf8)!.write(to: settingsURL)
        let installer = makeInstaller()
        XCTAssertThrowsError(try installer.loadSettings())
    }

    // MARK: - Hook type field

    func testAllHooksHaveCommandType() throws {
        let installer = makeInstaller()
        let result = installer.installHooks()
        XCTAssertEqual(result, .installed)

        let settings = try installer.loadSettings()
        let hooks = settings["hooks"] as? [String: Any] ?? [:]

        for eventType in HookInstaller.hookedEventTypes {
            let matcherGroups = hooks[eventType] as? [[String: Any]] ?? []
            for group in matcherGroups {
                let hookList = group["hooks"] as? [[String: Any]] ?? []
                for hook in hookList {
                    XCTAssertEqual(
                        hook["type"] as? String, "command",
                        "Hook for \(eventType) should have type 'command'"
                    )
                }
            }
        }
    }
}
