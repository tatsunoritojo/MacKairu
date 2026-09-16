import XCTest
@testable import KairuCore

final class WindowPlacementTests: XCTestCase {
    private let main = CGRect(x: 0, y: 0, width: 1440, height: 900)

    func testOffscreenSavedPositionReturnsToNearestScreen() {
        let saved = CGRect(x: 3000, y: 1600, width: 300, height: 220)

        let result = WindowPlacement.constrainedFrame(
            saved, visibleFrames: [main], keepTopVisible: false)

        XCTAssertEqual(result, CGRect(x: 1140, y: 680, width: 300, height: 220))
    }

    func testNegativeCoordinateDisplayIsSelectedByIntersection() {
        let left = CGRect(x: -1280, y: 0, width: 1280, height: 800)
        let frame = CGRect(x: -1200, y: 700, width: 400, height: 300)

        let result = WindowPlacement.constrainedFrame(
            frame, visibleFrames: [main, left], keepTopVisible: false)

        XCTAssertEqual(result.origin, CGPoint(x: -1200, y: 500))
    }

    func testFullyVisibleWindowSpanningAdjacentDisplaysKeepsItsPosition() {
        let right = CGRect(x: 1440, y: 0, width: 1440, height: 900)
        let frame = CGRect(x: 1300, y: 200, width: 300, height: 220)

        let result = WindowPlacement.constrainedFrame(
            frame, visibleFrames: [main, right], keepTopVisible: false)

        XCTAssertEqual(result, frame)
    }

    func testSeparateSpacesConstrainsSpanningWindowToOneDisplay() {
        let right = CGRect(x: 1440, y: 0, width: 1440, height: 900)
        let frame = CGRect(x: 1300, y: 200, width: 300, height: 220)

        let result = WindowPlacement.constrainedFrame(
            frame, visibleFrames: [main, right], keepTopVisible: false,
            allowSpanningDisplays: false)

        XCTAssertEqual(result.origin.x, 1440)
    }

    func testOverlappingDisplaysDoNotHidePartiallyOffscreenWindow() {
        let mirrored = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let frame = CGRect(x: 1300, y: 200, width: 280, height: 220)

        let result = WindowPlacement.constrainedFrame(
            frame, visibleFrames: [main, mirrored], keepTopVisible: false)

        XCTAssertEqual(result.maxX, main.maxX)
    }

    func testOversizedOpenWindowKeepsTopAndRightControlsVisible() {
        let frame = CGRect(x: 100, y: 100, width: 1800, height: 1200)

        let result = WindowPlacement.constrainedFrame(
            frame, visibleFrames: [main], keepTopVisible: true)

        XCTAssertEqual(result.maxX, main.maxX)
        XCTAssertEqual(result.maxY, main.maxY)
    }

    func testOversizedClosedWindowKeepsBottomAndRightCharacterVisible() {
        let frame = CGRect(x: 100, y: 100, width: 1800, height: 1200)

        let result = WindowPlacement.constrainedFrame(
            frame, visibleFrames: [main], keepTopVisible: false)

        XCTAssertEqual(result.maxX, main.maxX)
        XCTAssertEqual(result.minY, main.minY)
    }
}
