import XCTest
@testable import Whippet

final class AIRequestBuilderTests: XCTestCase {

    // MARK: - Anthropic

    func testBuildRequest_Anthropic() throws {
        let config = AIRequestConfig(
            provider: .anthropic, model: "claude-haiku-4-5-20251001",
            apiKey: "sk-ant-test", customBaseURL: "", maxTokens: 256, timeoutInterval: 30
        )
        let messages = [["role": "user", "content": "Hello"]]

        let request = try AIRequestBuilder.buildRequest(config: config, messages: messages)

        XCTAssertEqual(request.url?.host, "api.anthropic.com")
        XCTAssertEqual(request.url?.path, "/v1/messages")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-api-key"), "sk-ant-test")
        XCTAssertEqual(request.value(forHTTPHeaderField: "anthropic-version"), "2023-06-01")

        let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
        XCTAssertEqual(body["model"] as? String, "claude-haiku-4-5-20251001")
        XCTAssertEqual(body["max_tokens"] as? Int, 256)
    }

    func testBuildRequest_Anthropic_WithSystemPrompt() throws {
        let config = AIRequestConfig(
            provider: .anthropic, model: "claude-haiku-4-5-20251001",
            apiKey: "sk-ant-test", customBaseURL: "", maxTokens: 512, timeoutInterval: 60
        )
        let messages = [["role": "user", "content": "Summarize this"]]

        let request = try AIRequestBuilder.buildRequest(
            config: config, messages: messages, systemPrompt: "You are a summarizer."
        )

        let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
        XCTAssertEqual(body["system"] as? String, "You are a summarizer.")
    }

    // MARK: - OpenAI

    func testBuildRequest_OpenAI() throws {
        let config = AIRequestConfig(
            provider: .openai, model: "gpt-4.1-nano",
            apiKey: "sk-test", customBaseURL: "", maxTokens: 256, timeoutInterval: 30
        )
        let messages = [["role": "user", "content": "Hello"]]

        let request = try AIRequestBuilder.buildRequest(config: config, messages: messages)

        XCTAssertEqual(request.url?.host, "api.openai.com")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer sk-test")

        let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
        XCTAssertEqual(body["model"] as? String, "gpt-4.1-nano")
    }

    func testBuildRequest_OpenAI_WithSystemPrompt() throws {
        let config = AIRequestConfig(
            provider: .openai, model: "gpt-4.1-nano",
            apiKey: "sk-test", customBaseURL: "", maxTokens: 256, timeoutInterval: 30
        )
        let messages = [["role": "user", "content": "Hello"]]

        let request = try AIRequestBuilder.buildRequest(
            config: config, messages: messages, systemPrompt: "Be helpful."
        )

        let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
        let apiMessages = body["messages"] as! [[String: String]]
        XCTAssertEqual(apiMessages.first?["role"], "system")
        XCTAssertEqual(apiMessages.first?["content"], "Be helpful.")
    }

    // MARK: - Google

    func testBuildRequest_Google() throws {
        let config = AIRequestConfig(
            provider: .google, model: "gemini-2.0-flash",
            apiKey: "AIza-test", customBaseURL: "", maxTokens: 256, timeoutInterval: 30
        )
        let messages = [["role": "user", "content": "Hello"]]

        let request = try AIRequestBuilder.buildRequest(config: config, messages: messages)

        XCTAssertTrue(request.url?.absoluteString.contains("generativelanguage.googleapis.com") == true)
        XCTAssertTrue(request.url?.absoluteString.contains("key=AIza-test") == true)
    }

    // MARK: - Custom

    func testBuildRequest_Custom() throws {
        let config = AIRequestConfig(
            provider: .custom, model: "local-model",
            apiKey: "key", customBaseURL: "http://localhost:8080", maxTokens: 256, timeoutInterval: 30
        )
        let messages = [["role": "user", "content": "Hello"]]

        let request = try AIRequestBuilder.buildRequest(config: config, messages: messages)

        XCTAssertEqual(request.url?.host, "localhost")
        XCTAssertTrue(request.url?.path.contains("v1/chat/completions") == true)
    }

    func testBuildRequest_Custom_MissingBaseURL() {
        let config = AIRequestConfig(
            provider: .custom, model: "model",
            apiKey: "key", customBaseURL: "", maxTokens: 256, timeoutInterval: 30
        )

        XCTAssertThrowsError(try AIRequestBuilder.buildRequest(config: config, messages: []))
    }

    // MARK: - Response Parsing

    func testParseAssistantReply_Anthropic() {
        let json: [String: Any] = ["content": [["type": "text", "text": "Hello back"]]]
        let data = try! JSONSerialization.data(withJSONObject: json)

        let reply = AIRequestBuilder.parseAssistantReply(from: data, provider: .anthropic)
        XCTAssertEqual(reply, "Hello back")
    }

    func testParseAssistantReply_OpenAI() {
        let json: [String: Any] = ["choices": [["message": ["content": "Hello back"]]]]
        let data = try! JSONSerialization.data(withJSONObject: json)

        let reply = AIRequestBuilder.parseAssistantReply(from: data, provider: .openai)
        XCTAssertEqual(reply, "Hello back")
    }

    func testParseAssistantReply_Google() {
        let json: [String: Any] = ["candidates": [["content": ["parts": [["text": "Hello back"]]]]]]
        let data = try! JSONSerialization.data(withJSONObject: json)

        let reply = AIRequestBuilder.parseAssistantReply(from: data, provider: .google)
        XCTAssertEqual(reply, "Hello back")
    }

    // MARK: - Error Parsing

    func testParseErrorMessage_WithMessage() {
        let body = #"{"error": {"message": "Invalid API key"}}"#
        let result = AIRequestBuilder.parseErrorMessage(from: body, statusCode: 401)
        XCTAssertEqual(result, "Invalid API key")
    }

    func testParseErrorMessage_Fallback() {
        let result = AIRequestBuilder.parseErrorMessage(from: "not json", statusCode: 500)
        XCTAssertEqual(result, "HTTP 500")
    }
}
