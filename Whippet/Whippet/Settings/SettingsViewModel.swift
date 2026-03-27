import Foundation
import Combine
import os

/// Supported AI providers for session summarization.
enum AIProvider: String, CaseIterable, Identifiable {
    case anthropic
    case openai
    case google
    case custom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .anthropic: return "Anthropic (Claude)"
        case .openai: return "OpenAI (ChatGPT)"
        case .google: return "Google (Gemini)"
        case .custom: return "Custom (OpenAI-compatible)"
        }
    }

    /// Available models for each provider, cheapest first.
    var defaultModels: [String] {
        switch self {
        case .anthropic: return ["claude-haiku-4-5-20251001", "claude-sonnet-4-5-20250514", "claude-opus-4-5-20250514"]
        case .openai: return ["gpt-4.1-nano", "gpt-4.1-mini", "gpt-4o-mini", "gpt-4o"]
        case .google: return ["gemini-2.0-flash", "gemini-2.5-flash-preview-05-20", "gemini-2.5-pro-preview-05-06"]
        case .custom: return []
        }
    }

    /// The cheapest model that's good enough for short session summaries.
    var recommendedModel: String {
        switch self {
        case .anthropic: return "claude-haiku-4-5-20251001"   // ~$0.80/M input, fast
        case .openai: return "gpt-4.1-nano"                   // ~$0.10/M input, very cheap
        case .google: return "gemini-2.0-flash"               // free tier available, fast
        case .custom: return ""
        }
    }

    /// Short cost/speed note for the recommended model.
    var recommendedNote: String {
        switch self {
        case .anthropic: return "Haiku 4.5 — fast and inexpensive (~$0.80/M input tokens)"
        case .openai: return "GPT-4.1 Nano — cheapest OpenAI model (~$0.10/M input tokens)"
        case .google: return "Gemini 2.0 Flash — fast, free tier available"
        case .custom: return ""
        }
    }

    /// Placeholder text for the API key field.
    var apiKeyPlaceholder: String {
        switch self {
        case .anthropic: return "sk-ant-..."
        case .openai: return "sk-..."
        case .google: return "AIza..."
        case .custom: return "API key"
        }
    }

    /// Default base URL for the provider's API.
    var defaultBaseURL: String {
        switch self {
        case .anthropic: return "https://api.anthropic.com"
        case .openai: return "https://api.openai.com"
        case .google: return "https://generativelanguage.googleapis.com"
        case .custom: return ""
        }
    }
}

/// View model for the Settings window. Reads and writes all configurable settings
/// to the SQLite `settings` table via DatabaseManager. Changes are persisted
/// immediately and take effect without requiring an app restart.
final class SettingsViewModel: ObservableObject {

    // MARK: - Settings Keys

    /// Key for the staleness timeout (seconds), also used by SessionLivenessMonitor.
    static let stalenessTimeoutKey = "staleness_timeout"

    /// Key for the launch-at-login setting.
    static let launchAtLoginKey = LaunchAtLoginManager.launchAtLoginKey

    /// Key for tracking whether the first-launch prompt has been shown.
    static let launchAtLoginPromptShownKey = LaunchAtLoginManager.launchAtLoginPromptShownKey

    /// Key for the always-on-top toggle.
    static let alwaysOnTopKey = "always_on_top"

    /// Key for the window transparency value (0.3...1.0).
    static let transparencyKey = "window_transparency"

    /// Key for notification toggle: SessionStart events.
    static let notifySessionStartKey = "notify_session_start"

    /// Key for notification toggle: SessionEnd events.
    static let notifySessionEndKey = "notify_session_end"

    /// Key for notification toggle: Stale events.
    static let notifyStaleKey = "notify_stale"

    /// Key for the selected click action (raw value of SessionClickAction).
    static let clickActionKey = SessionActionHandler.clickActionKey

    /// Key for the custom shell command template.
    static let customCommandKey = SessionActionHandler.customCommandKey

    /// Key for the appearance mode ("light", "dark", "auto").
    static let appearanceModeKey = "appearance_mode"

    /// Key for the text size offset from system default.
    static let textSizeKey = "text_size"

    /// Key for the AI provider ("anthropic", "openai", "google", "custom").
    static let aiProviderKey = "ai_provider"

    /// Key for the AI model identifier (e.g. "claude-haiku-4-5-20251001", "gpt-4o-mini").
    static let aiModelKey = "ai_model"

    /// Key for the AI API key.
    static let aiAPIKeyKey = "ai_api_key"

    /// Key for a custom API base URL (for custom/self-hosted providers).
    static let aiBaseURLKey = "ai_base_url"

    /// Key for the AI summaries enabled toggle.
    static let aiSummariesEnabledKey = "ai_summaries_enabled"

    // MARK: - Default Values

    static let defaultStalenessTimeout: Double = 60
    static let defaultAlwaysOnTop: Bool = true
    static let defaultTransparency: Double = 1.0
    static let defaultNotifySessionStart: Bool = false
    static let defaultNotifySessionEnd: Bool = false
    static let defaultNotifyStale: Bool = false
    static let defaultClickAction: SessionClickAction = .openTerminal
    static let defaultCustomCommand: String = "echo $SESSION_ID $CWD $MODEL"
    static let defaultLaunchAtLogin: Bool = false
    static let defaultAppearanceMode: String = "auto"
    static let defaultTextSize: Double = 0.0
    static let defaultAIProvider: String = AIProvider.anthropic.rawValue
    static let defaultAIModel: String = "claude-haiku-4-5-20251001"
    static let defaultAIAPIKey: String = ""
    static let defaultAIBaseURL: String = ""
    static let defaultAISummariesEnabled: Bool = false

    // MARK: - Published Properties

    /// Staleness timeout in seconds (30...600).
    @Published var stalenessTimeout: Double {
        didSet { saveSetting(key: Self.stalenessTimeoutKey, value: String(Int(stalenessTimeout))) }
    }

    /// Whether the session panel floats above all other windows.
    @Published var alwaysOnTop: Bool {
        didSet {
            saveSetting(key: Self.alwaysOnTopKey, value: alwaysOnTop ? "true" : "false")
            onAlwaysOnTopChanged?(alwaysOnTop)
        }
    }

    /// Window transparency (0.3...1.0).
    @Published var transparency: Double {
        didSet {
            let clamped = min(max(transparency, 0.3), 1.0)
            if clamped != transparency { transparency = clamped; return }
            saveSetting(key: Self.transparencyKey, value: String(format: "%.2f", transparency))
            onTransparencyChanged?(CGFloat(transparency))
        }
    }

    /// Whether to send a notification on SessionStart events.
    @Published var notifySessionStart: Bool {
        didSet { saveSetting(key: Self.notifySessionStartKey, value: notifySessionStart ? "true" : "false") }
    }

    /// Whether to send a notification on SessionEnd events.
    @Published var notifySessionEnd: Bool {
        didSet { saveSetting(key: Self.notifySessionEndKey, value: notifySessionEnd ? "true" : "false") }
    }

    /// Whether to send a notification when a session becomes stale.
    @Published var notifyStale: Bool {
        didSet { saveSetting(key: Self.notifyStaleKey, value: notifyStale ? "true" : "false") }
    }

    /// The selected click action.
    @Published var clickAction: SessionClickAction {
        didSet { saveSetting(key: Self.clickActionKey, value: clickAction.rawValue) }
    }

    /// The custom shell command template.
    @Published var customCommand: String {
        didSet { saveSetting(key: Self.customCommandKey, value: customCommand) }
    }

    /// Whether the app is registered to launch at login. Reads the actual system
    /// state from SMAppService and toggles it via LaunchAtLoginManager.
    @Published var launchAtLogin: Bool {
        didSet {
            guard let manager = launchAtLoginManager else { return }
            // Only call setEnabled when the toggle actually differs from system state
            guard launchAtLogin != manager.isEnabled else { return }
            do {
                try manager.setEnabled(launchAtLogin)
            } catch {
                NSLog("Whippet: Failed to \(launchAtLogin ? "enable" : "disable") launch at login: \(error.localizedDescription)")
                // Revert to actual state on failure (suppress re-trigger of didSet)
                let actual = manager.isEnabled
                if actual != launchAtLogin {
                    launchAtLogin = actual
                }
            }
        }
    }

    /// Whether to show the first-launch prompt explaining launch-at-login.
    @Published var shouldShowLaunchAtLoginPrompt: Bool = false

    /// Appearance mode: "light", "dark", or "auto".
    @Published var appearanceMode: String = "auto" {
        didSet {
            saveSetting(key: Self.appearanceModeKey, value: appearanceMode)
            onAppearanceModeChanged?(appearanceMode)
        }
    }

    /// Text size offset from system default (range -4...4). 0.0 means system default.
    @Published var textSize: Double = 0.0 {
        didSet {
            saveSetting(key: Self.textSizeKey, value: String(textSize))
            onTextSizeChanged?(textSize)
        }
    }

    /// The AI provider for session summaries.
    @Published var aiProvider: AIProvider = .anthropic {
        didSet {
            saveSetting(key: Self.aiProviderKey, value: aiProvider.rawValue)
            apiKeyTestState = .idle
            // Set a sensible default model when switching providers
            if aiModel.isEmpty || !aiProvider.defaultModels.contains(aiModel) {
                aiModel = aiProvider.defaultModels.first ?? ""
            }
        }
    }

    /// The AI model to use for summaries (e.g. "claude-haiku-4-5-20251001", "gpt-4o-mini").
    @Published var aiModel: String = "claude-haiku-4-5-20251001" {
        didSet { saveSetting(key: Self.aiModelKey, value: aiModel) }
    }

    /// The text currently in the API key field. Only contains a value when the user
    /// is actively entering a new key. NOT pre-populated from Keychain on load.
    @Published var aiAPIKey: String = "" {
        didSet {
            if aiAPIKey.isEmpty {
                // User cleared the field — don't delete the stored key
            } else {
                KeychainHelper.set(aiAPIKey, forKey: Self.aiAPIKeyKey)
                hasStoredAPIKey = true
                // Auto-enable AI features when the user enters a key
                if !aiSummariesEnabled {
                    aiSummariesEnabled = true
                }
            }
            apiKeyTestState = .idle
        }
    }

    /// Whether a key is stored in Keychain. Used to show masked placeholder.
    @Published var hasStoredAPIKey: Bool = false

    /// Deletes the stored API key from Keychain.
    func clearAPIKey() {
        KeychainHelper.delete(forKey: Self.aiAPIKeyKey)
        hasStoredAPIKey = false
        aiAPIKey = ""
        apiKeyTestState = .idle
    }

    /// Custom API base URL (only used when provider is .custom).
    @Published var aiBaseURL: String = "" {
        didSet { saveSetting(key: Self.aiBaseURLKey, value: aiBaseURL) }
    }

    /// Whether AI session summaries are enabled.
    @Published var aiSummariesEnabled: Bool = false {
        didSet { saveSetting(key: Self.aiSummariesEnabledKey, value: aiSummariesEnabled ? "true" : "false") }
    }

    /// The current state of the API key validation test.
    @Published var apiKeyTestState: APIKeyTestState = .idle

    // MARK: - Callbacks

    /// Called when the always-on-top setting changes so the panel controller can update.
    var onAlwaysOnTopChanged: ((Bool) -> Void)?

    /// Called when the transparency setting changes so the panel controller can update.
    var onTransparencyChanged: ((CGFloat) -> Void)?

    /// Called when the appearance mode changes so the app delegate can update NSApp.appearance.
    var onAppearanceModeChanged: ((String) -> Void)?

    /// Called when the text size changes.
    var onTextSizeChanged: ((Double) -> Void)?

    // MARK: - Properties

    private let databaseManager: DatabaseManager

    /// The launch-at-login manager. Nil until configured via `configureLaunchAtLogin`.
    private(set) var launchAtLoginManager: LaunchAtLoginManager?

    /// Suppresses didSet saves during init to avoid overwriting persisted values.
    private var isLoading = true

    // MARK: - Initialization

    /// Creates a SettingsViewModel that reads initial values from the database.
    /// - Parameters:
    ///   - databaseManager: The database manager for persisting settings.
    ///   - launchAtLoginManager: Optional manager for launch-at-login functionality.
    init(databaseManager: DatabaseManager, launchAtLoginManager: LaunchAtLoginManager? = nil) {
        self.databaseManager = databaseManager
        self.launchAtLoginManager = launchAtLoginManager

        // Load initial values from database (use defaults if not set)
        self.stalenessTimeout = Self.defaultStalenessTimeout
        self.alwaysOnTop = Self.defaultAlwaysOnTop
        self.transparency = Self.defaultTransparency
        self.notifySessionStart = Self.defaultNotifySessionStart
        self.notifySessionEnd = Self.defaultNotifySessionEnd
        self.notifyStale = Self.defaultNotifyStale
        self.clickAction = Self.defaultClickAction
        self.customCommand = Self.defaultCustomCommand
        self.launchAtLogin = Self.defaultLaunchAtLogin
        self.appearanceMode = Self.defaultAppearanceMode
        self.textSize = Self.defaultTextSize
        self.aiProvider = AIProvider(rawValue: Self.defaultAIProvider) ?? .anthropic
        self.aiModel = Self.defaultAIModel
        self.aiAPIKey = Self.defaultAIAPIKey
        self.aiBaseURL = Self.defaultAIBaseURL
        self.aiSummariesEnabled = Self.defaultAISummariesEnabled

        loadFromDatabase()
        isLoading = false
    }

    /// Configures the launch-at-login manager after initialization.
    /// Call this to enable the launch-at-login toggle in settings.
    func configureLaunchAtLogin(_ manager: LaunchAtLoginManager) {
        self.launchAtLoginManager = manager
        // Sync the toggle with the actual system state
        self.launchAtLogin = manager.isEnabled
        // Check if we should show the first-launch prompt
        self.shouldShowLaunchAtLoginPrompt = !manager.hasShownPrompt
    }

    // MARK: - Load

    /// Loads all settings from the database, falling back to defaults for missing keys.
    func loadFromDatabase() {
        do {
            let settings = try databaseManager.fetchAllSettings()

            if let value = settings[Self.stalenessTimeoutKey], let seconds = Double(value), seconds > 0 {
                stalenessTimeout = seconds
            }

            if let value = settings[Self.alwaysOnTopKey] {
                alwaysOnTop = value == "true"
            }

            if let value = settings[Self.transparencyKey], let alpha = Double(value) {
                transparency = min(max(alpha, 0.3), 1.0)
            }

            if let value = settings[Self.notifySessionStartKey] {
                notifySessionStart = value == "true"
            }

            if let value = settings[Self.notifySessionEndKey] {
                notifySessionEnd = value == "true"
            }

            if let value = settings[Self.notifyStaleKey] {
                notifyStale = value == "true"
            }

            if let value = settings[Self.clickActionKey], let action = SessionClickAction(rawValue: value) {
                clickAction = action
            }

            if let value = settings[Self.customCommandKey], !value.isEmpty {
                customCommand = value
            }

            if let value = settings[Self.appearanceModeKey], ["light", "dark", "auto"].contains(value) {
                appearanceMode = value
            }

            if let value = settings[Self.textSizeKey], let size = Double(value) {
                textSize = min(max(size, -4), 4)
            }

            if let value = settings[Self.aiProviderKey], let provider = AIProvider(rawValue: value) {
                aiProvider = provider
            }

            if let value = settings[Self.aiModelKey], !value.isEmpty {
                aiModel = value
            }

            // API key: check Keychain existence (migrate from SQLite if needed).
            // Never load the actual key into memory just for display.
            if KeychainHelper.exists(forKey: Self.aiAPIKeyKey) {
                hasStoredAPIKey = true
            } else if let sqliteKey = settings[Self.aiAPIKeyKey], !sqliteKey.isEmpty {
                // Migrate from insecure SQLite storage to Keychain
                KeychainHelper.set(sqliteKey, forKey: Self.aiAPIKeyKey)
                try? databaseManager.deleteSetting(key: Self.aiAPIKeyKey)
                hasStoredAPIKey = true
                Log.settings.info("Migrated API key from SQLite to Keychain")
            }

            if let value = settings[Self.aiBaseURLKey] {
                aiBaseURL = value
            }

            if let value = settings[Self.aiSummariesEnabledKey] {
                aiSummariesEnabled = value == "true"
            }

            // Launch at login reads the actual system state, not the database
            if let manager = launchAtLoginManager {
                launchAtLogin = manager.isEnabled
                shouldShowLaunchAtLoginPrompt = !manager.hasShownPrompt
            }
        } catch {
            NSLog("Whippet: Failed to load settings: \(error.localizedDescription)")
        }
    }

    // MARK: - Save

    /// Persists a single setting to the database.
    private func saveSetting(key: String, value: String) {
        guard !isLoading else { return }
        do {
            try databaseManager.setSetting(key: key, value: value)
        } catch {
            NSLog("Whippet: Failed to save setting '\(key)': \(error.localizedDescription)")
        }
    }

    // MARK: - Launch at Login Prompt

    /// Dismisses the first-launch prompt and marks it as shown.
    func dismissLaunchAtLoginPrompt() {
        shouldShowLaunchAtLoginPrompt = false
        launchAtLoginManager?.markPromptShown()
    }

    // MARK: - Formatted Display

    /// Returns the staleness timeout formatted for display (e.g., "1 minute", "5 minutes").
    var stalenessTimeoutDisplay: String {
        let seconds = Int(stalenessTimeout)
        if seconds < 60 {
            return "\(seconds) second\(seconds == 1 ? "" : "s")"
        }
        let minutes = seconds / 60
        let remainingSeconds = seconds % 60
        if remainingSeconds == 0 {
            return "\(minutes) minute\(minutes == 1 ? "" : "s")"
        }
        return "\(minutes)m \(remainingSeconds)s"
    }

    // MARK: - API Key Validation

    /// Sends a minimal API request to verify the configured API key is valid.
    func testAPIKey() {
        // Use the field value if the user just typed a key, otherwise read from Keychain
        let fieldKey = aiAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = !fieldKey.isEmpty ? fieldKey : (KeychainHelper.get(forKey: Self.aiAPIKeyKey) ?? "")
        guard !key.isEmpty else {
            apiKeyTestState = .failed("No API key entered")
            return
        }

        apiKeyTestState = .testing

        let provider = aiProvider
        let model = aiModel
        let baseURL = aiBaseURL

        Task.detached(priority: .userInitiated) {
            do {
                let config = AIRequestConfig(
                    provider: provider, model: model, apiKey: key,
                    customBaseURL: baseURL, maxTokens: 1, timeoutInterval: 15
                )
                let request = try AIRequestBuilder.buildRequest(
                    config: config,
                    messages: [["role": "user", "content": "Hi"]]
                )

                let (data, response) = try await URLSession.shared.data(for: request)

                guard let http = response as? HTTPURLResponse else {
                    throw AIRequestError.invalidResponse
                }

                if http.statusCode == 200 || http.statusCode == 201 {
                    await MainActor.run { self.apiKeyTestState = .success }
                    Log.settings.info("API key test succeeded for \(provider.rawValue, privacy: .public)")
                } else {
                    let body = String(data: data, encoding: .utf8) ?? ""
                    let message = AIRequestBuilder.parseErrorMessage(from: body, statusCode: http.statusCode)
                    await MainActor.run { self.apiKeyTestState = .failed(message) }
                    Log.settings.warning("API key test failed: HTTP \(http.statusCode) — \(message, privacy: .public)")
                }
            } catch let error as AIRequestError {
                await MainActor.run { self.apiKeyTestState = .failed(error.localizedDescription) }
            } catch {
                await MainActor.run { self.apiKeyTestState = .failed(error.localizedDescription) }
                Log.settings.error("API key test error: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}

// MARK: - API Key Test State

/// The state of an API key validation test.
enum APIKeyTestState: Equatable {
    case idle
    case testing
    case success
    case failed(String)
}

