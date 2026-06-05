import XCTest
@testable import KairuCore

final class ProviderTests: XCTestCase {
    func testAllCases() {
        XCTAssertEqual(Provider.allCases.count, 3)
        XCTAssertEqual(Provider.claude.rawValue, "claude")
        XCTAssertEqual(Provider.openai.rawValue, "openai")
        XCTAssertEqual(Provider.gemini.rawValue, "gemini")
    }

    func testLabelsAndURLs() {
        for p in Provider.allCases {
            XCTAssertFalse(p.label.isEmpty)
            XCTAssertTrue(p.keyURL.hasPrefix("https://"), "\(p) のキー URL が https でない")
        }
    }

    func testModelsNonEmptyAndDefaultIsFirst() {
        for p in Provider.allCases {
            XCTAssertFalse(p.models.isEmpty, "\(p) のモデル候補が空")
            XCTAssertEqual(p.defaultModel, p.models.first)
        }
        XCTAssertEqual(Provider.claude.defaultModel, "claude-opus-4-8")
    }

    func testModelNote() {
        XCTAssertEqual(Provider.claude.modelNote("claude-opus-4-8"), "高性能・おすすめ")
        XCTAssertEqual(Provider.claude.modelNote("unknown-model"), "")
    }
}
