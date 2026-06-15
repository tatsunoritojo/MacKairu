import XCTest
@testable import KairuCore

final class LoadAssessmentTests: XCTestCase {

    private func make(memCritical: Bool = false, memWarning: Bool = false,
                      footprintMB: Double = 0, messageCount: Int = 0,
                      imageMessageCount: Int = 0) -> LoadAssessment {
        LoadAssessment(memCritical: memCritical, memWarning: memWarning,
                       footprintMB: footprintMB, messageCount: messageCount,
                       imageMessageCount: imageMessageCount)
    }

    func testIdleIsNotUnderLoad() {
        let a = make()
        XCTAssertFalse(a.isUnderLoad)
        XCTAssertFalse(a.isSevere)
    }

    func testMemCriticalIsSevere() {
        let a = make(memCritical: true)
        XCTAssertTrue(a.isSevere)
        XCTAssertTrue(a.isUnderLoad)
    }

    func testMemWarningIsUnderLoadButNotSevere() {
        let a = make(memWarning: true)
        XCTAssertTrue(a.isUnderLoad)
        XCTAssertFalse(a.isSevere)
    }

    func testFootprintThresholds() {
        XCTAssertFalse(make(footprintMB: 699).isUnderLoad)
        XCTAssertTrue(make(footprintMB: 700).isUnderLoad)
        XCTAssertFalse(make(footprintMB: 1199).isSevere)
        XCTAssertTrue(make(footprintMB: 1200).isSevere)
    }

    func testMessageCountThresholds() {
        XCTAssertFalse(make(messageCount: 39).isUnderLoad)
        XCTAssertTrue(make(messageCount: 40).isUnderLoad)
        XCTAssertFalse(make(messageCount: 79).isSevere)
        XCTAssertTrue(make(messageCount: 80).isSevere)
    }

    func testImageCountThresholds() {
        XCTAssertFalse(make(imageMessageCount: 4).isUnderLoad)
        XCTAssertTrue(make(imageMessageCount: 5).isUnderLoad)
        XCTAssertFalse(make(imageMessageCount: 9).isSevere)
        XCTAssertTrue(make(imageMessageCount: 10).isSevere)
    }
}
