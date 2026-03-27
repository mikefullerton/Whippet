import Foundation
import os

/// A single message in a mini chat conversation.
struct ChatMessage: Identifiable, Equatable {
    let id = UUID()
    let role: Role
    let content: String

    enum Role: Equatable {
        case user
        case assistant
        case error
    }
}

/// Drives a compact inline chat control that talks to the configured AI provider.
/// Reads provider/model from a SettingsViewModel and the API key from Keychain.
final class MiniChatViewModel: ObservableObject {

    @Published var messages: [ChatMessage] = []
    @Published var inputText: String = ""
    @Published var isLoading: Bool = false

    private weak var settingsViewModel: SettingsViewModel?

    init(settingsViewModel: SettingsViewModel) {
        self.settingsViewModel = settingsViewModel
    }

    // MARK: - Send

    func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isLoading else { return }

        let userMessage = ChatMessage(role: .user, content: text)
        messages.append(userMessage)
        inputText = ""
        isLoading = true

        guard let settings = settingsViewModel else {
            appendError("Settings not available")
            return
        }

        guard settings.aiSummariesEnabled else {
            appendError("AI features are disabled — enable them above")
            return
        }

        let provider = settings.aiProvider
        let model = settings.aiModel
        let customBaseURL = settings.aiBaseURL

        // Read API key from Keychain — never hold it longer than the request
        let apiKey = KeychainHelper.get(forKey: SettingsViewModel.aiAPIKeyKey) ?? ""
        guard !apiKey.isEmpty else {
            appendError("No API key configured")
            return
        }

        let history = messages.filter { $0.role != .error }
        let apiMessages = history.map { msg -> [String: String] in
            let role: String
            switch msg.role {
            case .user: role = "user"
            case .assistant: role = "assistant"
            case .error: role = "user"
            }
            return ["role": role, "content": msg.content]
        }

        Task.detached(priority: .userInitiated) { [weak self] in
            do {
                let config = AIRequestConfig(
                    provider: provider, model: model, apiKey: apiKey,
                    customBaseURL: customBaseURL, maxTokens: 256, timeoutInterval: 30
                )
                let request = try AIRequestBuilder.buildRequest(config: config, messages: apiMessages)

                let (data, response) = try await URLSession.shared.data(for: request)

                guard let http = response as? HTTPURLResponse else {
                    throw AIRequestError.invalidResponse
                }

                if http.statusCode == 200 || http.statusCode == 201 {
                    let reply = AIRequestBuilder.parseAssistantReply(from: data, provider: provider)
                    await MainActor.run {
                        self?.messages.append(ChatMessage(role: .assistant, content: reply))
                        self?.isLoading = false
                    }
                } else {
                    let body = String(data: data, encoding: .utf8) ?? ""
                    let message = AIRequestBuilder.parseErrorMessage(from: body, statusCode: http.statusCode)
                    await MainActor.run {
                        self?.appendError(message)
                    }
                }
            } catch {
                await MainActor.run {
                    self?.appendError(error.localizedDescription)
                }
            }
        }
    }

    func clearHistory() {
        messages.removeAll()
    }

    // MARK: - Private

    private func appendError(_ text: String) {
        messages.append(ChatMessage(role: .error, content: text))
        isLoading = false
    }
}
