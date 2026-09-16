import XCTest
@testable import KairuCore

final class ChatRequestGateTests: XCTestCase {
    func testNewRequestInvalidatesPreviousRequest() {
        var gate = ChatRequestGate()
        let first = gate.begin()
        let second = gate.begin()

        XCTAssertFalse(gate.isCurrent(first))
        XCTAssertTrue(gate.isCurrent(second))
    }

    func testInvalidateRejectsDelayedResponse() {
        var gate = ChatRequestGate()
        let request = gate.begin()

        gate.invalidate()

        XCTAssertFalse(gate.isCurrent(request))
        XCTAssertFalse(gate.finish(request))
    }

    func testOnlyCurrentRequestCanFinish() {
        var gate = ChatRequestGate()
        let request = gate.begin()

        XCTAssertTrue(gate.finish(request))
        XCTAssertNil(gate.currentID)
        XCTAssertFalse(gate.finish(request))
    }
}
