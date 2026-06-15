import XCTest
@testable import KairuCore

final class WhirlAccumulatorTests: XCTestCase {

    /// まっすぐ運ぶだけ（方向転換なし）ではスコアは溜まらない。
    func testStraightDragDoesNotAccumulate() {
        var w = WhirlAccumulator()
        w.begin(at: CGPoint(x: 0, y: 0))
        for i in 1...20 {
            w.add(CGPoint(x: Double(i) * 10, y: 0)) // 一直線
        }
        XCTAssertEqual(w.score, 0, accuracy: 0.0001)
        XCTAssertFalse(w.exceedsThreshold)
    }

    /// 大きく折り返してブンブン振り回すと閾値を超える。
    func testZigzagAccumulatesPastThreshold() {
        var w = WhirlAccumulator()
        w.begin(at: CGPoint(x: 0, y: 0))
        // 左右に大きく往復（毎回 180 度の方向転換・十分な移動量）。
        var x = 0.0
        for i in 0..<40 {
            x += (i % 2 == 0) ? 40 : -40
            w.add(CGPoint(x: x, y: 0))
        }
        XCTAssertGreaterThan(w.score, WhirlAccumulator.threshold)
        XCTAssertTrue(w.exceedsThreshold)
    }

    /// 微小な移動（3px 以下）は無視される。
    func testTinyMovementsIgnored() {
        var w = WhirlAccumulator()
        w.begin(at: CGPoint(x: 0, y: 0))
        for i in 1...50 {
            // 2px ずつ方向を変えても、距離が閾値未満なので加算されない。
            w.add(CGPoint(x: Double(i % 2) * 2, y: 0))
        }
        XCTAssertEqual(w.score, 0, accuracy: 0.0001)
    }

    /// decay でスコアは時間とともに冷め、0 未満にはならない。
    func testDecayCoolsDownToZero() {
        var w = WhirlAccumulator()
        w.begin(at: CGPoint(x: 0, y: 0))
        var x = 0.0
        for i in 0..<40 {
            x += (i % 2 == 0) ? 40 : -40
            w.add(CGPoint(x: x, y: 0))
        }
        let hot = w.score
        XCTAssertGreaterThan(hot, 0)
        w.decay(dt: 1.0)
        XCTAssertEqual(w.score, max(0, hot - WhirlAccumulator.decayPerSec), accuracy: 0.0001)
        // 十分に時間を進めれば 0 に張り付く（負にはならない）。
        for _ in 0..<100 { w.decay(dt: 1.0) }
        XCTAssertEqual(w.score, 0, accuracy: 0.0001)
    }

    /// reset / begin でスコアと履歴がクリアされる。
    func testResetClearsScore() {
        var w = WhirlAccumulator()
        w.begin(at: CGPoint(x: 0, y: 0))
        var x = 0.0
        for i in 0..<20 {
            x += (i % 2 == 0) ? 40 : -40
            w.add(CGPoint(x: x, y: 0))
        }
        XCTAssertGreaterThan(w.score, 0)
        w.reset()
        XCTAssertEqual(w.score, 0, accuracy: 0.0001)
    }
}
