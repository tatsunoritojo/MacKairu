import XCTest
@testable import KairuCore

final class CharacterTests: XCTestCase {
    func testSelectableExcludesGirl() {
        XCTAssertEqual(Character.selectable.count, 4)
        XCTAssertFalse(Character.selectable.contains(.girl))
        XCTAssertTrue(Character.allCases.contains(.girl))
    }

    func testLabelsAndEmoji() {
        for c in Character.allCases {
            XCTAssertFalse(c.label.isEmpty)
            XCTAssertFalse(c.emoji.isEmpty)
        }
        XCTAssertEqual(Character.dolphin.emoji, "🐬")
    }

    func testRawValueRoundTrip() {
        for c in Character.allCases {
            XCTAssertEqual(Character(rawValue: c.rawValue), c)
        }
    }

    func testSecretMode() {
        XCTAssertTrue(SecretMode.isTriggered(by: "裏モード"))
        XCTAssertTrue(SecretMode.isTriggered(by: "  裏 モード "))
        XCTAssertTrue(SecretMode.isTriggered(by: "うらもーど"))
        XCTAssertFalse(SecretMode.isTriggered(by: "表モード"))
        XCTAssertFalse(SecretMode.isTriggered(by: "こんにちは"))
    }
}
