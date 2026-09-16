import XCTest
@testable import KairuCore

final class LaunchTargetTests: XCTestCase {
    func testInstalledAppTakesPriorityOverDevelopmentBundle() {
        let path = LaunchTarget.preferredAppPath(
            installedAppPath: "/Applications/Kairu.app",
            currentBundlePath: "/repo/Kairu.app",
            installedAppExists: true)

        XCTAssertEqual(path, "/Applications/Kairu.app")
    }

    func testDevelopmentBundleIsRejectedWhenInstalledAppDoesNotExist() {
        let path = LaunchTarget.preferredAppPath(
            installedAppPath: "/Applications/Kairu.app",
            currentBundlePath: "/repo/Kairu.app",
            installedAppExists: false)

        XCTAssertNil(path)
    }

    func testApplicationFolderBundleIsAllowedAsFallback() {
        let path = LaunchTarget.preferredAppPath(
            installedAppPath: "/Applications/Kairu.app",
            currentBundlePath: "/Applications/Kairu Preview.app",
            installedAppExists: false)

        XCTAssertEqual(path, "/Applications/Kairu Preview.app")
    }
}
