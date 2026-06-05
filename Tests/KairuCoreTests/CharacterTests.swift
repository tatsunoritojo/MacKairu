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
        // 追加状態
        XCTAssertEqual(GirlState.from(fileName: "rest"), .rest)
        XCTAssertEqual(GirlState.from(fileName: "doze"), .doze)
        XCTAssertEqual(GirlState.from(fileName: "run"), .run)
        XCTAssertEqual(GirlState.from(fileName: "run2"), .run2)
        XCTAssertEqual(GirlState.from(fileName: "dash"), .run)
        XCTAssertEqual(GirlState.from(fileName: "hold"), .hold)
        XCTAssertEqual(GirlState.from(fileName: "grab"), .hold)
        XCTAssertEqual(GirlState.from(fileName: "drag"), .drag)
        XCTAssertEqual(GirlState.from(fileName: "teaching"), .teaching)
        XCTAssertEqual(GirlState.from(fileName: "tip"), .teaching)
        XCTAssertEqual(GirlState.from(fileName: "teaching2"), .teaching2)
        XCTAssertEqual(GirlState.from(fileName: "confused"), .dizzy)
        XCTAssertEqual(GirlState.from(fileName: "confused2"), .dizzy2)
        XCTAssertEqual(GirlState.from(fileName: "dizzy"), .dizzy)
        XCTAssertEqual(GirlState.from(fileName: "thinking"), .thinking)
        XCTAssertEqual(GirlState.from(fileName: "thiking2"), .thinking2)
        XCTAssertEqual(GirlState.from(fileName: "greeting"), .greet)
        XCTAssertEqual(GirlState.from(fileName: "greeting2"), .greet2)
        XCTAssertEqual(GirlState.from(fileName: "greeting3"), .greet3)
        // 状態名そのままも通る
        XCTAssertEqual(GirlState.from(fileName: "idle"), .idle)
        XCTAssertEqual(GirlState.from(fileName: "pamperLoop"), .pamperLoop)
        XCTAssertNil(GirlState.from(fileName: "random"))
    }

    func testGirlStateFileName() {
        XCTAssertEqual(GirlState.idle.fileName, "idle.png")
        XCTAssertEqual(GirlState.allCases.count, 21)
    }

    func testImageChainFallsBackToIdle() {
        // 新規状態は近い既存画像→idle の順でフォールバックする。
        XCTAssertEqual(GirlState.doze.imageChain, [.doze, .rest, .idle])
        XCTAssertEqual(GirlState.run2.imageChain, [.run2, .run, .idle])
        XCTAssertEqual(GirlState.drag.imageChain.last, .idle)
        XCTAssertEqual(GirlState.idle.imageChain, [.idle, .idle])
    }

    func testSecretMode() {
        XCTAssertTrue(SecretMode.isTriggered(by: "裏モード"))
        XCTAssertTrue(SecretMode.isTriggered(by: "  裏 モード "))
        XCTAssertTrue(SecretMode.isTriggered(by: "うらもーど"))
        XCTAssertFalse(SecretMode.isTriggered(by: "表モード"))
        XCTAssertFalse(SecretMode.isTriggered(by: "こんにちは"))
    }
}
