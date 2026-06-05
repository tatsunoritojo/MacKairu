import XCTest
@testable import KairuCore

final class SelfDestructTests: XCTestCase {
    func testTriggers() {
        XCTAssertTrue(SelfDestruct.isTriggered(by: "お前を消す方法"))
        XCTAssertTrue(SelfDestruct.isTriggered(by: "  お前を消す方法  "))   // 前後空白
        XCTAssertTrue(SelfDestruct.isTriggered(by: "お前を 消す 方法"))     // 途中スペース
        XCTAssertTrue(SelfDestruct.isTriggered(by: "ねえ、お前を消す方法を教えて")) // 部分一致
        XCTAssertTrue(SelfDestruct.isTriggered(by: "おまえを消す方法"))     // ひらがな
    }

    func testDoesNotTrigger() {
        XCTAssertFalse(SelfDestruct.isTriggered(by: "ファイルを消す方法"))
        XCTAssertFalse(SelfDestruct.isTriggered(by: "スクリーンショットの撮り方"))
        XCTAssertFalse(SelfDestruct.isTriggered(by: ""))
        XCTAssertFalse(SelfDestruct.isTriggered(by: "お前は誰？"))
    }
}
