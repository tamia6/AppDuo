import XCTest
@testable import CloneCore

final class AppUpdateTests: XCTestCase {
    func testMissingOrMalformedKeyDisablesUpdates() {
        XCTAssertNil(AppUpdateConfiguration(publicKey: nil, architecture: "arm64"))
        XCTAssertNil(AppUpdateConfiguration(publicKey: "not a key", architecture: "arm64"))
        XCTAssertNil(AppUpdateConfiguration(publicKey: Data(repeating: 0, count: 16).base64EncodedString(), architecture: "arm64"))
    }
    func testArchitectureUsesSeparateHTTPSFeeds() throws {
        let key = Data(repeating: 1, count: 32).base64EncodedString()
        let arm = try XCTUnwrap(AppUpdateConfiguration(publicKey: key, architecture: "arm64"))
        let intel = try XCTUnwrap(AppUpdateConfiguration(publicKey: key, architecture: "x86_64"))
        XCTAssertEqual(arm.feedURL.absoluteString, "https://github.com/tamia6/AppDuo/releases/latest/download/appcast-arm64.xml")
        XCTAssertEqual(intel.feedURL.absoluteString, "https://github.com/tamia6/AppDuo/releases/latest/download/appcast-x86_64.xml")
        XCTAssertNil(AppUpdateConfiguration(publicKey: key, architecture: "unknown"))
    }
    func testInstallationWaitsForCloneOperationAndRunsOnce() {
        let gate = UpdateInstallationGate()
        var installs = 0
        XCTAssertTrue(gate.postponeIfBusy(true) { installs += 1 })
        gate.resumeIfIdle(isBusy: true)
        XCTAssertEqual(installs, 0)
        gate.resumeIfIdle(isBusy: false)
        gate.resumeIfIdle(isBusy: false)
        XCTAssertEqual(installs, 1)
        XCTAssertFalse(gate.postponeIfBusy(false) { installs += 1 })
        XCTAssertEqual(installs, 1)
    }
}
