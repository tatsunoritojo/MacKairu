import XCTest
@testable import KairuCore

final class MultimodalTests: XCTestCase {
    private let imgMsg = ChatMessage(
        role: .user, text: "この画面の操作を教えて",
        image: ImageAttachment(base64: "QUJD", mediaType: "image/png"))

    private func config(_ p: Provider) -> AppConfig {
        AppConfig(provider: p, apiKey: "k", model: p.defaultModel, systemPrompt: "指示")
    }

    private func body(_ p: Provider) throws -> [String: Any] {
        let req = try RequestBuilder.makeRequest(config: config(p), history: [imgMsg])
        let data = try XCTUnwrap(req.httpBody)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func testClaudeImageBlock() throws {
        let messages = try XCTUnwrap(body(.claude)["messages"] as? [[String: Any]])
        let content = try XCTUnwrap(messages.first?["content"] as? [[String: Any]])
        XCTAssertEqual(content.first?["type"] as? String, "image")
        let source = try XCTUnwrap(content.first?["source"] as? [String: Any])
        XCTAssertEqual(source["type"] as? String, "base64")
        XCTAssertEqual(source["media_type"] as? String, "image/png")
        XCTAssertEqual(source["data"] as? String, "QUJD")
        XCTAssertEqual(content.last?["type"] as? String, "text")
    }

    func testOpenAIImageURL() throws {
        let messages = try XCTUnwrap(body(.openai)["messages"] as? [[String: Any]])
        // [system, user(画像)]
        let content = try XCTUnwrap(messages.last?["content"] as? [[String: Any]])
        let imagePart = content.first { ($0["type"] as? String) == "image_url" }
        let urlObj = try XCTUnwrap(imagePart?["image_url"] as? [String: Any])
        XCTAssertEqual(urlObj["url"] as? String, "data:image/png;base64,QUJD")
    }

    func testGeminiInlineData() throws {
        let contents = try XCTUnwrap(body(.gemini)["contents"] as? [[String: Any]])
        let parts = try XCTUnwrap(contents.first?["parts"] as? [[String: Any]])
        let inline = try XCTUnwrap(parts.first?["inline_data"] as? [String: Any])
        XCTAssertEqual(inline["mime_type"] as? String, "image/png")
        XCTAssertEqual(inline["data"] as? String, "QUJD")
    }

    func testTextOnlyStillString() throws {
        // 画像なしは従来どおり content が文字列
        let req = try RequestBuilder.makeRequest(
            config: config(.claude),
            history: [ChatMessage(role: .user, text: "やあ")])
        let data = try XCTUnwrap(req.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let messages = try XCTUnwrap(json["messages"] as? [[String: Any]])
        XCTAssertEqual(messages.first?["content"] as? String, "やあ")
    }
}
