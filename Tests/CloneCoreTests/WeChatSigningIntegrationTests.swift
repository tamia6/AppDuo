import XCTest
@testable import CloneCore

/// Opt in with APPDUO_TEST_WECHAT_PATH=/Applications/WeChat.app.
/// Builds disposable copies without launching WeChat or reading its user data.
final class WeChatSigningIntegrationTests: XCTestCase {
    func testInstalledWeChatSigning() throws {
        guard let path = ProcessInfo.processInfo.environment["APPDUO_TEST_WECHAT_PATH"] else {
            throw XCTSkip("Set APPDUO_TEST_WECHAT_PATH to test an installed WeChat bundle")
        }
        let source = URL(fileURLWithPath: path)
        let info = try Inspector.inspect(source)
        guard info.bundleID == "com.tencent.xinWeChat" else {
            throw XCTSkip("APPDUO_TEST_WECHAT_PATH must point to WeChat")
        }
        var recipe = Recipes.match(info, recipes: try Recipes.load())
        // No links to real home-directory data are needed for signing verification.
        recipe.symlinks = []
        let manifestPath = "Contents/MacOS/XPlayer.app/Contents/Frameworks/vk_swiftshader_icd.json"
        let original = source.appendingPathComponent(manifestPath)
        let bytes = try Data(contentsOf: original)
        let signature = try Command.run("/usr/bin/xattr", ["-px", "com.apple.cs.CodeDirectory", original.path])
        for injection in [Injection.auto, .launcher, .dylib] {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent("appduo-wechat-signing-" + UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: root) }
            var config = CloneConfiguration(source: source, name: "SigningFixture", destination: root.appendingPathComponent("Clone.app"), dataDirectory: root.appendingPathComponent("Data"), recipe: recipe)
            config.injection = injection
            print("WeChat \(info.version), hard clone, injection=\(config.injection.rawValue)")
            _ = try CloneEngine().build(config) { print($0) }
            let clonedManifest = config.destination.appendingPathComponent(manifestPath)
            XCTAssertEqual(try Data(contentsOf: clonedManifest), bytes)
            XCTAssertEqual(try Command.run("/usr/bin/xattr", ["-px", "com.apple.cs.CodeDirectory", clonedManifest.path]), signature)
            try Command.run("/usr/bin/codesign", ["--verify", "--deep", "--strict", config.destination.path])
        }
        XCTAssertEqual(try Data(contentsOf: original), bytes)
        XCTAssertEqual(try Command.run("/usr/bin/xattr", ["-px", "com.apple.cs.CodeDirectory", original.path]), signature)
    }
}
