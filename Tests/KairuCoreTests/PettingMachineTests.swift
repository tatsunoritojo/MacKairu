import XCTest
@testable import KairuCore

final class PettingMachineTests: XCTestCase {

    /// 頭ゾーン内・低速で滞在 → idle から notice へ。
    private func near(_ dt: Double = 0.05, speed: Double = 0, wobble: Double = 0) -> PettingMachine.Input {
        .init(dt: dt, inZone: true, speed: speed, xWobble: wobble, enabled: true)
    }
    private func away(_ dt: Double = 0.05, speed: Double = 0) -> PettingMachine.Input {
        .init(dt: dt, inZone: false, speed: speed, xWobble: 0, enabled: true)
    }

    func testStartsIdle() {
        let m = PettingMachine()
        XCTAssertEqual(m.state, .idle)
        XCTAssertFalse(m.isBeingPatted)
    }

    func testIdleToNoticeAfterHover() {
        var m = PettingMachine()
        // noticeHoverTime=0.18。0.05刻みで 4 回（0.20秒）滞在すれば notice。
        for _ in 0..<4 { m.update(near()) }
        XCTAssertEqual(m.state, .notice)
    }

    func testFastCursorDoesNotNotice() {
        var m = PettingMachine()
        // noticeSpeedMax=1200 超かつ撫で動作なし(wobble 0)なら気づかない。
        for _ in 0..<10 { m.update(near(speed: 1500)) }
        XCTAssertEqual(m.state, .idle)
    }

    func testPetMotionFromIdleJumpsStraightToPamper() {
        var m = PettingMachine()
        // 明確な撫で動作なら notice を飛ばして即 pamper（反応の速さ）。
        m.update(near(wobble: 40))
        XCTAssertEqual(m.state, .pamper)
        XCTAssertTrue(m.isBeingPatted)
    }

    func testNoticeToPamperByDwell() {
        var m = PettingMachine()
        // 頭ゾーンに低速で滞在し続ければ、撫で動作なしでも甘える。
        for _ in 0..<8 { m.update(near()) }
        XCTAssertTrue(m.isBeingPatted) // pamper か pamperLoop
    }

    func testPamperToLoopThenOscillates() {
        var m = PettingMachine()
        m.update(near(wobble: 40)) // 即 pamper
        // pamperFlipInterval=0.25 を超えると pamperLoop。
        for _ in 0..<6 { m.update(near(wobble: 40)) }
        XCTAssertEqual(m.state, .pamperLoop)
        // loopFlipInterval=0.5 ごとに表示が往復する。
        let before = m.display
        for _ in 0..<11 { m.update(near(wobble: 40)) }
        XCTAssertNotEqual(m.display, before)
        XCTAssertEqual(m.state, .pamperLoop) // 論理状態は維持
    }

    func testBriefExitDoesNotEndPamper() {
        var m = PettingMachine()
        m.update(near(wobble: 40)) // pamper
        // 一瞬（猶予 0.35s 未満）ゾーン外に出ても撫では終わらない（ヒステリシス）。
        for _ in 0..<5 { m.update(away()) } // 0.25s 離脱
        XCTAssertTrue(m.isBeingPatted)
        // 戻ればそのまま継続。
        m.update(near(wobble: 40))
        XCTAssertTrue(m.isBeingPatted)
    }

    func testSustainedExitEndsPamperAfterGrace() {
        var m = PettingMachine()
        m.update(near(wobble: 40)) // pamper
        // 猶予 0.35s を超えて離れ続けると end（余韻）へ。
        for _ in 0..<9 { m.update(away()) } // 0.45s 離脱
        XCTAssertEqual(m.state, .end)
        // endDuration=0.5 経過で idle に戻る。
        for _ in 0..<11 { m.update(away()) }
        XCTAssertEqual(m.state, .idle)
    }

    func testCanRePetImmediatelyAfterRelease() {
        var m = PettingMachine()
        m.update(near(wobble: 40))            // pamper
        for _ in 0..<9 { m.update(away()) }   // 猶予超で end へ
        XCTAssertEqual(m.state, .end)
        // 余韻中でも撫で直したら即復帰（撫でたい時に撫でられる）。
        m.update(near(wobble: 40))
        XCTAssertEqual(m.state, .pamper)
        XCTAssertTrue(m.isBeingPatted)
    }

    func testDisabledReturnsToIdle() {
        var m = PettingMachine()
        for _ in 0..<4 { m.update(near()) } // notice
        m.update(.init(dt: 0.05, inZone: true, speed: 0, xWobble: 0, enabled: false))
        XCTAssertEqual(m.state, .idle)
    }

    func testResetClearsState() {
        var m = PettingMachine()
        for _ in 0..<4 { m.update(near()) }
        m.reset()
        XCTAssertEqual(m.state, .idle)
        XCTAssertEqual(m.display, .idle)
    }

    // MARK: - 遠い待機（rest / doze）

    func testFarCursorShowsRestThenDoze() {
        var m = PettingMachine()
        let far = PettingMachine.Input(dt: 0.1, inZone: false, speed: 0, xWobble: 0,
                                       distance: 1000, enabled: true)
        m.update(far)
        XCTAssertEqual(m.state, .idle)      // 論理状態は待機のまま
        XCTAssertEqual(m.display, .rest)    // 表示は開き目
        // restOpenDuration=2.4 を超えると とろけ目(doze)へ。
        for _ in 0..<25 { m.update(far) }
        XCTAssertEqual(m.state, .idle)
        XCTAssertEqual(m.display, .doze)
    }

    func testNearCursorShowsAlertIdle() {
        var m = PettingMachine()
        // 近い（restRadius=360 以内）が頭ゾーン外 → きりっとした idle 表示。
        let near = PettingMachine.Input(dt: 0.05, inZone: false, speed: 0, xWobble: 0,
                                        distance: 100, enabled: true)
        m.update(near)
        XCTAssertEqual(m.display, .idle)
    }

    // MARK: - ドラッグ（hold / drag）

    func testHoldShowsHold() {
        var m = PettingMachine()
        m.update(PettingMachine.Input(dt: 0.05, inZone: false, speed: 0, xWobble: 0,
                                      enabled: true, isHeld: true, isDragging: false))
        XCTAssertEqual(m.state, .hold)
        XCTAssertFalse(m.isBeingPatted)
    }

    func testDraggingShowsDrag() {
        var m = PettingMachine()
        m.update(PettingMachine.Input(dt: 0.05, inZone: false, speed: 0, xWobble: 0,
                                      enabled: true, isHeld: true, isDragging: true))
        XCTAssertEqual(m.state, .drag)
    }

    func testHoldOverridesPamper() {
        var m = PettingMachine()
        for _ in 0..<4 { m.update(near()) }
        m.update(near(wobble: 40)) // pamper
        XCTAssertEqual(m.state, .pamper)
        // 掴まれたら撫でを中断して hold へ。
        m.update(PettingMachine.Input(dt: 0.05, inZone: true, speed: 0, xWobble: 40,
                                      enabled: true, isHeld: true))
        XCTAssertEqual(m.state, .hold)
    }

    func testReleaseReturnsToIdle() {
        var m = PettingMachine()
        m.update(PettingMachine.Input(dt: 0.05, inZone: false, speed: 0, xWobble: 0,
                                      enabled: true, isHeld: true, isDragging: true))
        XCTAssertEqual(m.state, .drag)
        m.update(.init(dt: 0.05, inZone: false, speed: 0, xWobble: 0, enabled: true))
        XCTAssertEqual(m.state, .idle)
    }

    func testHoldWorksEvenWhenNadeDisabled() {
        var m = PettingMachine()
        // enabled=false（なで反応 OFF）でも掴みは成立する。
        m.update(PettingMachine.Input(dt: 0.05, inZone: false, speed: 0, xWobble: 0,
                                      enabled: false, isHeld: true, isDragging: true))
        XCTAssertEqual(m.state, .drag)
    }

    // MARK: - 駆け出し（run）

    func testMovingShowsRunCycle() {
        var m = PettingMachine()
        // dt=0.2 で runFlipInterval=0.16 を 1 ステップで超える。
        let move = PettingMachine.Input(dt: 0.2, inZone: false, speed: 0, xWobble: 0,
                                        enabled: true, isMoving: true)
        m.update(move)
        XCTAssertEqual(m.state, .run)
        XCTAssertEqual(m.display, .run)
        // 足を入れ替えて run2 へ。
        m.update(move)
        XCTAssertEqual(m.display, .run2)
        XCTAssertEqual(m.state, .run) // 論理状態は run のまま
    }

    func testHoldBeatsMoving() {
        var m = PettingMachine()
        m.update(PettingMachine.Input(dt: 0.05, inZone: false, speed: 0, xWobble: 0,
                                      enabled: true, isHeld: true, isMoving: true))
        XCTAssertEqual(m.state, .hold) // 掴みが移動より優先
    }

    func testStopMovingReturnsToIdle() {
        var m = PettingMachine()
        m.update(PettingMachine.Input(dt: 0.1, inZone: false, speed: 0, xWobble: 0,
                                      enabled: true, isMoving: true))
        XCTAssertEqual(m.state, .run)
        m.update(.init(dt: 0.1, inZone: false, speed: 0, xWobble: 0, enabled: true))
        XCTAssertEqual(m.state, .idle)
    }
}
