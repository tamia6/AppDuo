import XCTest
@testable import CloneCore

final class SigningTests: XCTestCase {
    func testNestedGenericSignatureSurvivesAttributeCleanup() throws {
        let (root, config) = try EngineTests().fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let relative = "Contents/MacOS/XPlayer.app"
        let nested = config.source.appendingPathComponent(relative)
        let main = nested.appendingPathComponent("Contents/MacOS/XPlayer")
        let manifestPath = "Contents/Frameworks/vk_swiftshader_icd.json"
        let manifest = nested.appendingPathComponent(manifestPath)
        let fm = FileManager.default
        try fm.createDirectory(at: main.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.createDirectory(at: manifest.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.copyItem(at: config.source.appendingPathComponent("Contents/MacOS/Original"), to: main)
        try Plist.write(["CFBundleIdentifier": "com.atb.test.xplayer", "CFBundleExecutable": "XPlayer", "CFBundlePackageType": "APPL"], to: nested.appendingPathComponent("Contents/Info.plist"))
        let bytes = Data("{\"ICD\":{\"library_path\":\"./libvk_swiftshader.dylib\"}}".utf8)
        try bytes.write(to: manifest)
        // WeChat ships this non-Mach-O component with its signature in xattrs.
        try Command.run("/usr/bin/codesign", ["--force", "--sign", "-", manifest.path])
        try Command.run("/usr/bin/codesign", ["--force", "--sign", "-", nested.path])
        let originalSignature = try Command.run("/usr/bin/xattr", ["-px", "com.apple.cs.CodeDirectory", manifest.path])
        try Command.run("/usr/bin/xattr", ["-w", "com.apple.quarantine", "0081;00000000;Fixture;", nested.path])
        try Command.run("/usr/bin/xattr", ["-wx", "com.apple.FinderInfo", String(repeating: "00", count: 32), manifest.path])
        try Command.run("/usr/bin/xattr", ["-w", "com.apple.ResourceFork", "fixture detritus", manifest.path])

        _ = try CloneEngine().build(config)

        let clonedNested = config.destination.appendingPathComponent(relative)
        let clonedManifest = clonedNested.appendingPathComponent(manifestPath)
        XCTAssertEqual(try Data(contentsOf: clonedManifest), bytes)
        XCTAssertEqual(try Command.run("/usr/bin/xattr", ["-px", "com.apple.cs.CodeDirectory", clonedManifest.path]), originalSignature)
        let attributes = try Command.run("/usr/bin/xattr", [clonedManifest.path])
        XCTAssertFalse(attributes.contains("com.apple.FinderInfo"))
        XCTAssertFalse(attributes.contains("com.apple.ResourceFork"))
        XCTAssertFalse(try Command.run("/usr/bin/xattr", [clonedNested.path]).contains("com.apple.quarantine"))
        try Command.run("/usr/bin/codesign", ["--verify", "--deep", "--strict", config.destination.path])
        try Data("tampered".utf8).write(to: clonedManifest)
        XCTAssertThrowsError(try Command.run("/usr/bin/codesign", ["--verify", "--deep", "--strict", config.destination.path]))
        XCTAssertEqual(try Data(contentsOf: manifest), bytes)
        XCTAssertEqual(try Command.run("/usr/bin/xattr", ["-px", "com.apple.cs.CodeDirectory", manifest.path]), originalSignature)
    }
}
