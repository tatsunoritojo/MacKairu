import XCTest
@testable import KairuCore

final class FatnessTests: XCTestCase {
    func testLevels() {
        XCTAssertEqual(Fatness.level(messageCount: 0), 0.0, accuracy: 0.0001)
        XCTAssertEqual(Fatness.level(messageCount: 15), 0.5, accuracy: 0.0001)
        XCTAssertEqual(Fatness.level(messageCount: 30), 1.0, accuracy: 0.0001)
    }

    func testCappedAtOne() {
        XCTAssertEqual(Fatness.level(messageCount: 100), 1.0, accuracy: 0.0001)
    }

    func testNeverNegative() {
        XCTAssertEqual(Fatness.level(messageCount: -5), 0.0, accuracy: 0.0001)
    }
}
