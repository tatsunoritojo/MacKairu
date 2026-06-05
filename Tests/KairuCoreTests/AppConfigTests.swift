import XCTest
@testable import KairuCore

final class AppConfigTests: XCTestCase {
    func testDefaultSystemPrompt() {
        XCTAssertFalse(AppConfig.defaultSystemPrompt.isEmpty)
        XCTAssertTrue(AppConfig.defaultSystemPrompt.contains("Mac"))
        XCTAssertTrue(AppConfig.defaultSystemPrompt.contains("MacKairu"))
    }

    func testDefaultModel() {
        XCTAssertEqual(AppConfig.defaultModel(for: .claude), "claude-opus-4-8")
        XCTAssertEqual(AppConfig.defaultModel(for: .openai), "gpt-4o")
        XCTAssertEqual(AppConfig.defaultModel(for: .gemini), "gemini-2.5-flash")
    }

    func testHasKey() {
        XCTAssertFalse(makeConfig(key: "").hasKey)
        XCTAssertFalse(makeConfig(key: "   ").hasKey)
        XCTAssertTrue(makeConfig(key: "sk-xxx").hasKey)
    }

    func testEffectiveSystemPromptFallsBackToDefault() {
        var c = makeConfig(key: "k")
        c.systemPrompt = nil
        XCTAssertEqual(c.effectiveSystemPrompt, AppConfig.defaultSystemPrompt)
        c.systemPrompt = "カスタム指示"
        XCTAssertEqual(c.effectiveSystemPrompt, "カスタム指示")
    }

    func testSanitizedForDiskRemovesKey() {
        let c = makeConfig(key: "secret-key")
        let sanitized = c.sanitizedForDisk()
        XCTAssertEqual(sanitized.apiKey, "")
        XCTAssertEqual(sanitized.provider, c.provider)
        XCTAssertEqual(sanitized.model, c.model)
        XCTAssertEqual(sanitized.systemPrompt, c.systemPrompt)
    }

    func testCodableRoundTripDoesNotLosePrompt() throws {
        let c = makeConfig(key: "k")
        let data = try JSONEncoder().encode(c)
        let decoded = try JSONDecoder().decode(AppConfig.self, from: data)
        XCTAssertEqual(decoded, c)
    }

    func testEncodedDiskJSONHasNoPlaintextKey() throws {
        // 保存形式（sanitizedForDisk）に鍵が含まれないこと
        let c = makeConfig(key: "super-secret")
        let data = try JSONEncoder().encode(c.sanitizedForDisk())
        let str = String(data: data, encoding: .utf8) ?? ""
        XCTAssertFalse(str.contains("super-secret"))
    }

    private func makeConfig(key: String) -> AppConfig {
        AppConfig(provider: .claude, apiKey: key, model: "claude-opus-4-8",
                  systemPrompt: "テスト指示")
    }
}
