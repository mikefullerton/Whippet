import Foundation

/// Configuration for an AI API request.
struct AIRequestConfig {
    let provider: AIProvider
    let model: String
    let apiKey: String
    let customBaseURL: String
    let maxTokens: Int
    let timeoutInterval: TimeInterval
}

/// Builds provider-specific HTTP requests and parses responses for AI APIs.
/// Shared by MiniChatViewModel (interactive chat), SessionSummarizer (summarization),
/// and SettingsViewModel (API key smoke tests).
enum AIRequestBuilder {

    /// Builds a URLRequest for the configured provider with the given messages.
    /// Messages use the format `[["role": "user"|"assistant", "content": "..."]]`.
    static func buildRequest(
        config: AIRequestConfig,
        messages: [[String: String]],
        systemPrompt: String? = nil
    ) throws -> URLRequest {
        switch config.provider {
        case .anthropic:
            return try buildAnthropicRequest(config: config, messages: messages, systemPrompt: systemPrompt)
        case .openai:
            return try buildOpenAIRequest(config: config, messages: messages, systemPrompt: systemPrompt,
                                          baseURL: "https://api.openai.com")
        case .google:
            return buildGoogleRequest(config: config, messages: messages, systemPrompt: systemPrompt)
        case .custom:
            guard !config.customBaseURL.isEmpty else {
                throw AIRequestError.missingBaseURL
            }
            return try buildOpenAIRequest(config: config, messages: messages, systemPrompt: systemPrompt,
                                          baseURL: config.customBaseURL)
        }
    }

    /// Extracts the assistant's text reply from a provider-specific JSON response.
    static func parseAssistantReply(from data: Data, provider: AIProvider) -> String {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return "(Unable to parse response)"
        }

        switch provider {
        case .anthropic:
            if let content = json["content"] as? [[String: Any]],
               let first = content.first,
               let text = first["text"] as? String {
                return text
            }

        case .openai, .custom:
            if let choices = json["choices"] as? [[String: Any]],
               let first = choices.first,
               let message = first["message"] as? [String: Any],
               let content = message["content"] as? String {
                return content
            }

        case .google:
            if let candidates = json["candidates"] as? [[String: Any]],
               let first = candidates.first,
               let content = first["content"] as? [String: Any],
               let parts = content["parts"] as? [[String: Any]],
               let firstPart = parts.first,
               let text = firstPart["text"] as? String {
                return text
            }
        }

        return "(Empty response)"
    }

    /// Extracts a user-friendly error message from an API error response body.
    static func parseErrorMessage(from body: String, statusCode: Int) -> String {
        if let data = body.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let error = json["error"] as? [String: Any],
               let message = error["message"] as? String {
                return message
            }
            if let message = json["message"] as? String {
                return message
            }
        }
        return "HTTP \(statusCode)"
    }

    // MARK: - Provider-Specific Builders

    private static func buildAnthropicRequest(
        config: AIRequestConfig,
        messages: [[String: String]],
        systemPrompt: String?
    ) throws -> URLRequest {
        let url = URL(string: "https://api.anthropic.com/v1/messages")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(config.apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")

        var body: [String: Any] = [
            "model": config.model.isEmpty ? "claude-haiku-4-5-20251001" : config.model,
            "max_tokens": config.maxTokens,
            "messages": messages,
        ]
        if let systemPrompt, !systemPrompt.isEmpty {
            body["system"] = systemPrompt
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = config.timeoutInterval
        return request
    }

    private static func buildOpenAIRequest(
        config: AIRequestConfig,
        messages: [[String: String]],
        systemPrompt: String?,
        baseURL: String
    ) throws -> URLRequest {
        guard let url = URL(string: baseURL)?.appendingPathComponent("v1/chat/completions") else {
            throw AIRequestError.missingBaseURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "content-type")

        var allMessages: [[String: String]] = []
        if let systemPrompt, !systemPrompt.isEmpty {
            allMessages.append(["role": "system", "content": systemPrompt])
        }
        allMessages.append(contentsOf: messages)

        let defaultModel = config.provider == .custom ? config.model : "gpt-4.1-nano"
        let body: [String: Any] = [
            "model": config.model.isEmpty ? defaultModel : config.model,
            "max_tokens": config.maxTokens,
            "messages": allMessages,
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = config.timeoutInterval
        return request
    }

    private static func buildGoogleRequest(
        config: AIRequestConfig,
        messages: [[String: String]],
        systemPrompt: String?
    ) -> URLRequest {
        let effectiveModel = config.model.isEmpty ? "gemini-2.0-flash" : config.model
        let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(effectiveModel):generateContent?key=\(config.apiKey)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")

        let contents = messages.map { msg -> [String: Any] in
            let role = msg["role"] == "assistant" ? "model" : "user"
            return ["role": role, "parts": [["text": msg["content"] ?? ""]]]
        }

        var body: [String: Any] = [
            "contents": contents,
            "generationConfig": ["maxOutputTokens": config.maxTokens],
        ]
        if let systemPrompt, !systemPrompt.isEmpty {
            body["systemInstruction"] = ["parts": [["text": systemPrompt]]]
        }

        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = config.timeoutInterval
        return request
    }
}

// MARK: - Errors

enum AIRequestError: Error, LocalizedError {
    case invalidResponse
    case missingBaseURL

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "Invalid server response"
        case .missingBaseURL: return "Custom base URL is required"
        }
    }
}
