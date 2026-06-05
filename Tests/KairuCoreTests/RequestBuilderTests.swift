import XCTest
@testable import KairuCore

final class RequestBuilderTests: XCTestCase {
    private let history = [
        ChatMessage(role: .user, text: "こんにちは"),
        ChatMessage(role: .assistant, text: "やあ"),
        ChatMessage(role: .user, text: "スクショの撮り方は？"),
    ]

    private func config(_ p: Provider, key: String = "test-key") -> AppConfig {
        AppConfig(provider: p, apiKey: key, model: p.defaultModel, systemPrompt: "指示")
    }

    private func body(_ req: URLRequest) throws -> [String: Any] {
        let data = try XCTUnwrap(req.httpBody)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    // MARK: - Claude

    func testClaudeRequest() throws {
        let req = try RequestBuilder.makeRequest(config: config(.claude), history: history)
        XCTAssertEqual(req.url?.absoluteString, "https://api.anthropic.com/v1/messages")
        XCTAssertEqual(req.httpMethod, "POST")
        XCTAssertEqual(req.value(forHTTPHeaderField: "x-api-key"), "test-key")
        XCTAssertEqual(req.value(forHTTPHeaderField: "anthropic-version"), "2023-06-01")

        let body = try body(req)
        XCTAssertEqual(body["model"] as? String, "claude-opus-4-8")
        XCTAssertEqual(body["system"] as? String, "指示")
        let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
        XCTAssertEqual(messages.count, 3)
        XCTAssertEqual(messages.first?["role"] as? String, "user")
        XCTAssertEqual(messages[1]["role"] as? String, "assistant")
    }

    // MARK: - OpenAI

    func testOpenAIRequest() throws {
        let req = try RequestBuilder.makeRequest(config: config(.openai), history: history)
        XCTAssertEqual(req.url?.absoluteString, "https://api.openai.com/v1/chat/completions")
        XCTAssertEqual(req.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")

        let body = try body(req)
        let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
        // 先頭が system、その後に会話履歴
        XCTAssertEqual(messages.first?["role"] as? String, "system")
        XCTAssertEqual(messages.first?["content"] as? String, "指示")
        XCTAssertEqual(messages.count, 4)
    }

    // MARK: - Gemini

    func testGeminiRequest() throws {
        let req = try RequestBuilder.makeRequest(config: config(.gemini), history: history)
        let url = try XCTUnwrap(req.url?.absoluteString)
        XCTAssertTrue(url.contains("gemini-2.5-flash:generateContent"))
        XCTAssertTrue(url.contains("key=test-key"))

        let body = try body(req)
        XCTAssertNotNil(body["system_instruction"])
        let contents = try XCTUnwrap(body["contents"] as? [[String: Any]])
        XCTAssertEqual(contents.first?["role"] as? String, "user")
        // assistant は "model" にマップされる
        XCTAssertEqual(contents[1]["role"] as? String, "model")
    }

    // MARK: - 応答解析

    func testParseClaudeReply() {
        let json: [String: Any] = ["content": [["type": "text", "text": "答えです"]]]
        XCTAssertEqual(RequestBuilder.parseReply(provider: .claude, json: json), "答えです")
    }

    func testParseOpenAIReply() {
        let json: [String: Any] = ["choices": [["message": ["content": "答えです"]]]]
        XCTAssertEqual(RequestBuilder.parseReply(provider: .openai, json: json), "答えです")
    }

    func testParseGeminiReply() {
        let json: [String: Any] = ["candidates": [["content": ["parts": [["text": "答えです"]]]]]]
        XCTAssertEqual(RequestBuilder.parseReply(provider: .gemini, json: json), "答えです")
    }

    func testParseReplyReturnsNilOnGarbage() {
        XCTAssertNil(RequestBuilder.parseReply(provider: .claude, json: ["foo": "bar"]))
        XCTAssertNil(RequestBuilder.parseReply(provider: .openai, json: [:]))
    }

    func testParseError() {
        let json: [String: Any] = ["error": ["message": "invalid api key"]]
        XCTAssertEqual(RequestBuilder.parseError(json), "invalid api key")
        XCTAssertNil(RequestBuilder.parseError(["ok": true]))
    }
}
