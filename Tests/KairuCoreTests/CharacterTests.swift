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

    func testGirlStateFileNameMapping() {
        XCTAssertEqual(GirlState.from(fileName: "noticed"), .idle)
        XCTAssertEqual(GirlState.from(fileName: "waiting"), .notice)
        XCTAssertEqual(GirlState.from(fileName: "pampering"), .pamper)
        XCTAssertEqual(GirlState.from(fileName: "pampering2"), .pamperLoop)
        XCTAssertEqual(GirlState.from(fileName: "afterglowing"), .end)
        XCTAssertEqual(GirlState.from(fileName: "sad"), .sad)
        // 状態名そのままも通る
        XCTAssertEqual(GirlState.from(fileName: "idle"), .idle)
        XCTAssertEqual(GirlState.from(fileName: "pamperLoop"), .pamperLoop)
        XCTAssertNil(GirlState.from(fileName: "random"))
    }

    func testGirlStateFileName() {
        XCTAssertEqual(GirlState.idle.fileName, "idle.png")
        XCTAssertEqual(GirlState.allCases.count, 6)
    }

    func testSecretMode() {
        XCTAssertTrue(SecretMode.isTriggered(by: "裏モード"))
        XCTAssertTrue(SecretMode.isTriggered(by: "  裏 モード "))
        XCTAssertTrue(SecretMode.isTriggered(by: "うらもーど"))
        XCTAssertFalse(SecretMode.isTriggered(by: "表モード"))
        XCTAssertFalse(SecretMode.isTriggered(by: "こんにちは"))
    }
}
