import Foundation
import os

/// Generates AI-powered summaries for Claude Code sessions by reading stored events
/// and sending a summarization prompt to the configured AI provider.
final class SessionSummarizer {

    // MARK: - Properties

    private let databaseManager: DatabaseManager

    /// Approximate character budget for the events portion of the prompt.
    static let defaultEventCharBudget = 20_000

    /// Maximum tokens for the summary output (short name, ~3-8 words).
    static let summaryMaxTokens = 32

    /// Timeout for the summarization API call.
    static let requestTimeout: TimeInterval = 60

    private static let systemPrompt = """
        Given a timeline of events from a Claude Code session, produce a short name \
        (3-8 words) that describes what the session is doing. Think of it like a tab title \
        or branch name — concrete and scannable. \
        Examples: "PID-based session liveness", "Keychain API key migration", \
        "Fix horizontal resize bug", "Add mini chat control". \
        Output only the short name, nothing else.
        """

    // MARK: - Initialization

    init(databaseManager: DatabaseManager) {
        self.databaseManager = databaseManager
    }

    // MARK: - Public API

    /// Summarizes a session by reading all its events from the database,
    /// building a prompt, and calling the configured AI provider.
    /// Returns nil if summarization is disabled, unconfigured, or fails.
    func summarize(sessionId: String) async -> String? {
        let dbg = SummarizerDebugLog.shared
        dbg.append("--- summarize(\(sessionId)) called ---")

        // Read settings from database at call time
        let enabledStr = try? databaseManager.getSetting(key: SettingsViewModel.aiSummariesEnabledKey)
        dbg.append("ai_summaries_enabled setting = \(enabledStr ?? "<nil>")")
        guard enabledStr == "true" else {
            dbg.append("BAIL: AI summaries not enabled")
            Log.ai.debug("Skipping summarization — AI summaries disabled")
            return nil
        }

        let apiKey = KeychainHelper.get(forKey: SettingsViewModel.aiAPIKeyKey) ?? ""
        dbg.append("API key present = \(!apiKey.isEmpty) (length: \(apiKey.count))")
        guard !apiKey.isEmpty else {
            dbg.append("BAIL: No API key in Keychain")
            Log.ai.debug("Skipping summarization — no API key configured")
            return nil
        }

        let providerStr = (try? databaseManager.getSetting(key: SettingsViewModel.aiProviderKey)) ?? "anthropic"
        let provider = AIProvider(rawValue: providerStr) ?? .anthropic
        let model = (try? databaseManager.getSetting(key: SettingsViewModel.aiModelKey)) ?? provider.recommendedModel
        let baseURL = (try? databaseManager.getSetting(key: SettingsViewModel.aiBaseURLKey)) ?? ""
        dbg.append("Provider: \(provider.rawValue), Model: \(model), BaseURL: \(baseURL.isEmpty ? "(none)" : baseURL)")

        // Fetch session and events
        guard let session = try? databaseManager.fetchSession(bySessionId: sessionId) else {
            dbg.append("BAIL: Session not found in database")
            Log.ai.warning("Cannot summarize — session not found: \(sessionId, privacy: .public)")
            return nil
        }
        dbg.append("Session found: project=\(session.projectName), status=\(session.status.rawValue)")

        let events: [SessionEvent]
        do {
            events = try databaseManager.fetchEvents(forSessionId: sessionId)
        } catch {
            dbg.append("BAIL: Failed to fetch events — \(error.localizedDescription)")
            Log.ai.error("Failed to fetch events for \(sessionId, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return nil
        }
        dbg.append("Fetched \(events.count) events")

        guard !events.isEmpty else {
            dbg.append("BAIL: No events for this session")
            Log.ai.debug("Skipping summarization — no events for session \(sessionId, privacy: .public)")
            return nil
        }

        // Build prompt
        let userMessage = buildSummarizationPrompt(session: session, events: events)
        dbg.append("--- PROMPT (\(userMessage.count) chars) ---")
        dbg.append(userMessage)
        dbg.append("--- END PROMPT ---")

        // Call AI provider
        let config = AIRequestConfig(
            provider: provider,
            model: model,
            apiKey: apiKey,
            customBaseURL: baseURL,
            maxTokens: Self.summaryMaxTokens,
            timeoutInterval: Self.requestTimeout
        )

        do {
            let request = try AIRequestBuilder.buildRequest(
                config: config,
                messages: [["role": "user", "content": userMessage]],
                systemPrompt: Self.systemPrompt
            )
            dbg.append("Sending request to \(request.url?.host ?? "?") ...")

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let http = response as? HTTPURLResponse else {
                dbg.append("BAIL: Invalid response (not HTTP)")
                Log.ai.error("Summarization failed — invalid response for \(sessionId, privacy: .public)")
                return nil
            }

            dbg.append("HTTP \(http.statusCode)")

            guard http.statusCode == 200 || http.statusCode == 201 else {
                let body = String(data: data, encoding: .utf8) ?? ""
                let message = AIRequestBuilder.parseErrorMessage(from: body, statusCode: http.statusCode)
                dbg.append("BAIL: API error — \(message)")
                dbg.append("Response body: \(body.prefix(500))")
                Log.ai.error("Summarization failed — HTTP \(http.statusCode) for \(sessionId, privacy: .public): \(message, privacy: .public)")
                return nil
            }

            let reply = AIRequestBuilder.parseAssistantReply(from: data, provider: provider)
            dbg.append("--- REPLY ---")
            dbg.append(reply)
            dbg.append("--- END REPLY ---")

            guard !reply.isEmpty, !reply.starts(with: "(") else {
                dbg.append("BAIL: Empty or error reply")
                Log.ai.warning("Summarization returned empty/error reply for \(sessionId, privacy: .public)")
                return nil
            }

            dbg.append("SUCCESS: Summary generated")
            Log.ai.info("Generated summary for \(sessionId, privacy: .public): \(reply.prefix(80), privacy: .public)")
            return reply
        } catch {
            dbg.append("BAIL: Request exception — \(error.localizedDescription)")
            Log.ai.error("Summarization request failed for \(sessionId, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// Summarizes a session and stores the result in the database.
    /// Failures are logged but not thrown.
    func summarizeAndStore(sessionId: String) async {
        SummarizerDebugLog.shared.append("summarizeAndStore(\(sessionId)) entered")
        guard let summary = await summarize(sessionId: sessionId) else { return }

        do {
            try databaseManager.updateSessionSummary(sessionId: sessionId, summary: summary)
            Log.ai.info("Stored AI summary for session \(sessionId, privacy: .public)")

            await MainActor.run {
                SessionListViewModel.notifySessionsChanged()
            }
        } catch {
            Log.ai.error("Failed to store summary for \(sessionId, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Prompt Construction

    /// Builds the user message for summarization from session metadata and events.
    func buildSummarizationPrompt(session: Session, events: [SessionEvent]) -> String {
        var lines: [String] = []

        lines.append("Session: \(session.projectName)")
        if !session.cwd.isEmpty {
            lines.append("Working directory: \(session.cwd)")
        }
        if !session.model.isEmpty {
            lines.append("Model: \(session.model)")
        }
        if !session.gitBranch.isEmpty {
            lines.append("Branch: \(session.gitBranch)")
        }
        lines.append("")
        lines.append("Event timeline:")

        let distilled = Self.fitEventsToBudget(events: events, charBudget: Self.defaultEventCharBudget)
        lines.append(contentsOf: distilled)

        return lines.joined(separator: "\n")
    }

    // MARK: - Event Distillation

    /// Reduces a single event's raw JSON to a compact, high-signal line.
    static func distillEvent(_ event: SessionEvent) -> String {
        let json = parseRawJson(event.rawJson)
        let data = json["data"] as? [String: Any] ?? [:]

        switch event.eventType {
        case "SessionStart":
            let cwd = data["cwd"] as? String ?? ""
            let model = data["model"] as? String ?? ""
            return "[SessionStart] cwd=\(cwd) model=\(model)"

        case "SessionEnd":
            let reason = data["reason"] as? String ?? ""
            return "[SessionEnd] reason=\(reason)"

        case "UserPromptSubmit":
            let prompt = data["prompt"] as? String ?? ""
            let truncated = String(prompt.prefix(500))
            return "[UserPrompt] \"\(truncated)\""

        case "PreToolUse":
            let tool = data["tool"] as? String ?? "unknown"
            let input = compactToolInput(data["tool_input"])
            return "[Tool:\(tool)] \(input)"

        case "PostToolUse":
            let tool = data["tool"] as? String ?? "unknown"
            let responseSize = estimateSize(data["tool_response"])
            return "[Tool:\(tool) result] (\(responseSize))"

        case "SubagentStart":
            let agentType = data["agent_type"] as? String ?? ""
            return "[SubagentStart] type=\(agentType)"

        case "SubagentStop":
            let agentType = data["agent_type"] as? String ?? ""
            return "[SubagentStop] type=\(agentType)"

        case "Notification":
            let message = data["message"] as? String ?? ""
            return "[Notification] \(String(message.prefix(200)))"

        case "Stop":
            return "[Stop]"

        default:
            return "[\(event.eventType)]"
        }
    }

    /// Fits distilled events into the character budget.
    /// Keeps first and last events, omits from the middle if over budget.
    static func fitEventsToBudget(events: [SessionEvent], charBudget: Int) -> [String] {
        let distilled = events.map { distillEvent($0) }

        let totalChars = distilled.reduce(0) { $0 + $1.count }
        if totalChars <= charBudget {
            return distilled
        }

        // Over budget: keep first half and last half of the budget
        let keepCount = max(4, distilled.count / 3)
        let headCount = min(keepCount, distilled.count)
        let tailCount = min(keepCount, max(0, distilled.count - headCount))

        var result: [String] = []
        result.append(contentsOf: distilled.prefix(headCount))

        let omitted = distilled.count - headCount - tailCount
        if omitted > 0 {
            result.append("[... \(omitted) events omitted ...]")
        }

        if tailCount > 0 {
            result.append(contentsOf: distilled.suffix(tailCount))
        }

        return result
    }

    // MARK: - Helpers

    private static func parseRawJson(_ rawJson: String) -> [String: Any] {
        guard let data = rawJson.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        return json
    }

    /// Extracts key fields from tool_input for compact representation.
    private static func compactToolInput(_ input: Any?) -> String {
        guard let dict = input as? [String: Any] else {
            guard let str = input as? String else { return "" }
            return String(str.prefix(200))
        }

        // Common tool input patterns
        if let filePath = dict["file_path"] as? String ?? dict["path"] as? String {
            return "file: \(filePath)"
        }
        if let command = dict["command"] as? String {
            return "cmd: \(String(command.prefix(200)))"
        }
        if let pattern = dict["pattern"] as? String {
            return "pattern: \(String(pattern.prefix(100)))"
        }

        // Fallback: list keys
        let keys = dict.keys.sorted().prefix(5).joined(separator: ", ")
        return "{\(keys)}"
    }

    /// Estimates the display size of a value.
    private static func estimateSize(_ value: Any?) -> String {
        guard let value else { return "empty" }
        let description: String
        if let str = value as? String {
            description = str
        } else if let data = try? JSONSerialization.data(withJSONObject: value) {
            description = String(data: data, encoding: .utf8) ?? ""
        } else {
            description = String(describing: value)
        }

        let bytes = description.utf8.count
        if bytes < 1024 {
            return "\(bytes)B"
        } else {
            let kb = Double(bytes) / 1024.0
            return String(format: "%.1fKB", kb)
        }
    }
}
