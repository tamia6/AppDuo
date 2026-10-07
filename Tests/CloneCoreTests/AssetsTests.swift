import XCTest
@testable import CloneCore

final class AssetsTests: XCTestCase {
    func testPackagedResourcesDoNotEvaluateSwiftPMFallback() throws {
        let fm = FileManager.default
        let temporary = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? fm.removeItem(at: temporary) }
        // Match both bundle layouts SwiftPM has emitted on supported toolchains.
        for nested in ["Contents/Resources/Resources", "Resources"] {
            // Foundation caches bundle layouts by URL; give each fixture its own path.
            let app = temporary.appendingPathComponent(UUID().uuidString + ".app")
            let resources = app.appendingPathComponent("Contents/Resources")
            try fm.createDirectory(at: resources, withIntermediateDirectories: true)
            try Plist.write(["CFBundleIdentifier": "com.appduo.resource-test", "CFBundlePackageType": "APPL"],
                            to: app.appendingPathComponent("Contents/Info.plist"))
            let resourceBundle = resources.appendingPathComponent("AppDuo_CloneCore.bundle")
            let expected = resourceBundle.appendingPathComponent(nested)
            try fm.createDirectory(at: expected, withIntermediateDirectories: true)
            if nested.hasPrefix("Contents/") {
                try Plist.write(["CFBundleIdentifier": "com.appduo.resources", "CFBundlePackageType": "BNDL"],
                                to: resourceBundle.appendingPathComponent("Contents/Info.plist"))
            }
            let result = Assets.resourceRoot(in: try XCTUnwrap(Bundle(url: app))) {
                XCTFail("Packaged apps must not evaluate the old SwiftPM accessor, which can fatalError")
                return temporary
            }
            XCTAssertEqual(result.resolvingSymlinksInPath(), expected.resolvingSymlinksInPath())
            try fm.removeItem(at: resourceBundle)
        }
    }

    func testDevelopmentUsesSwiftPMFallback() throws {
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".bundle")
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporary) }
        var calls = 0
        let expected = URL(fileURLWithPath: "/swiftpm/Resources")
        let result = Assets.resourceRoot(in: try XCTUnwrap(Bundle(url: temporary))) {
            calls += 1
            return expected
        }
        XCTAssertEqual(result, expected)
        XCTAssertEqual(calls, 1)
    }
}
