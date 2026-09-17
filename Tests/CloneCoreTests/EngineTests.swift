import XCTest
@testable import CloneCore

final class EngineTests: XCTestCase {
    func fixture() throws -> (URL, CloneConfiguration) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("atb-native-test-" + UUID().uuidString)
        let source = root.appendingPathComponent("Original.app")
        let mac = source.appendingPathComponent("Contents/MacOS")
        try FileManager.default.createDirectory(at: mac, withIntermediateDirectories: true)
        let code = root.appendingPathComponent("test.c")
        try """
        #include <libproc.h>
        #include <stdio.h>
        #include <stdlib.h>
        #include <unistd.h>
        int main(int argc, char **argv) {
          char path[4096]; proc_pidpath(getpid(), path, sizeof(path));
          printf("%s\\n%s\\n", path, getenv("ATB_TEST") ?: "missing");
          for (int i = 1; i < argc; ++i) puts(argv[i]);
          return 0;
        }
        """.write(to: code, atomically: true, encoding: .utf8)
        try Command.run("/usr/bin/xcrun", ["clang", "-Wl,-headerpad,0x1000", code.path, "-o", mac.appendingPathComponent("Original").path])
        try Plist.write(["CFBundleIdentifier": "com.atb.test", "CFBundleExecutable": "Original", "CFBundlePackageType": "APPL", "CFBundleIconName": "AppIcon"], to: source.appendingPathComponent("Contents/Info.plist"))
        var recipe = Recipe(bundleID: "com.atb.test", appName: "Original")
        recipe.environment = ["ATB_TEST": "quote' slash\\ $value\n中文", "HOME": "{{ATB_DATA_DIR}}/Home", "TMPDIR": "{{ATB_DATA_DIR}}/Tmp"]
        recipe.stripSandbox = true
        let config = CloneConfiguration(source: source, name: "WeWork", destination: root.appendingPathComponent("WeWork.app"), dataDirectory: root.appendingPathComponent("Data/WeWork"), recipe: recipe)
        return (root, config)
    }
    func testRealHardAndSoftClonesAndIconUpdates() throws {
        for strategy in Strategy.allCases {
            for injection in [Injection.dylib, .launcher] where strategy == .hard || injection == .launcher {
                let (root, base) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
                var c = base; c.recipe.strategy = strategy; c.injection = injection
                if strategy == .hard {
                let entitlements = root.appendingPathComponent("original-entitlements.plist")
                try Plist.write(["com.apple.application-identifier": "TEAM.com.atb.test", "com.apple.developer.team-identifier": "TEAM"], to: entitlements)
                try Command.run("/usr/bin/codesign", ["--force", "--sign", "-", "--entitlements", entitlements.path, c.source.appendingPathComponent("Contents/MacOS/Original").path])
                }
                let icon = root.appendingPathComponent("Chosen.icns"); try Data(contentsOf: Assets.icon).write(to: icon); c.customIcon = icon
                let sourceBytes = try Data(contentsOf: c.source.appendingPathComponent("Contents/MacOS/Original"))
                let first = try CloneEngine().build(c)
                try FileManager.default.removeItem(at: icon)
                var updated = first.configuration; updated.language = "en"
                let second = try CloneEngine().build(updated, updating: true)
                XCTAssertNil(second.configuration.customIcon)
                XCTAssertEqual(try Data(contentsOf: c.destination.appendingPathComponent("Contents/Resources/ATBCloneIcon.icns")), try Data(contentsOf: Assets.icon))
                let metadata = try Plist.read(c.destination.appendingPathComponent("Contents/Info.plist"))
                XCTAssertEqual(metadata["CFBundleIdentifier"] as? String, c.bundleID)
                let entitlements = try Command.run("/usr/bin/codesign", ["-d", "--entitlements", ":-", c.destination.path])
                XCTAssertFalse(entitlements.contains("com.apple.application-identifier"))
                XCTAssertFalse(entitlements.contains("com.apple.developer.team-identifier"))
                XCTAssertEqual(metadata["CFBundleIconFile"] as? String, "ATBCloneIcon.icns")
                XCTAssertNil(metadata["CFBundleIconName"])
                let executable = try XCTUnwrap(metadata["CFBundleExecutable"] as? String)
                let result = try Command.run(c.destination.appendingPathComponent("Contents/MacOS/" + executable).path, [])
                XCTAssertTrue(result.contains("quote' slash\\ $value\n中文"), result)
                XCTAssertTrue(result.contains(strategy == .hard ? "/WeWork\n" : "/Original\n"), result)
                XCTAssertEqual(try Data(contentsOf: c.source.appendingPathComponent("Contents/MacOS/Original")), sourceBytes)
                // A bad icon must not destroy the existing signed clone.
                updated.customIcon = root.appendingPathComponent("missing.icns")
                XCTAssertThrowsError(try CloneEngine().build(updated, updating: true))
                XCTAssertTrue(FileManager.default.fileExists(atPath: c.destination.path))
                try Command.run("/usr/bin/codesign", ["--verify", "--deep", "--strict", c.destination.path])
            }
        }
    }
    func testNativeLanguageKeepsRegisteredMainExecutable() throws {
        let (root, base) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        var config = base; config.language = "en"; config.injection = .auto
        config.recipe.appType = "cocoa"
        _ = try CloneEngine().build(config)
        let metadata = try Plist.read(config.destination.appendingPathComponent("Contents/Info.plist"))
        XCTAssertEqual(metadata["CFBundleExecutable"] as? String, config.name)
        let signing = try Command.run("/usr/bin/codesign", ["-dv", config.destination.appendingPathComponent("Contents/MacOS/" + config.name).path])
        XCTAssertTrue(signing.contains("Identifier=" + config.bundleID), signing)
        let preferences = try Plist.read(config.dataDirectory.appendingPathComponent("Home/Library/Preferences/" + config.bundleID + ".plist"))
        XCTAssertEqual(preferences["AppleLanguages"] as? [String], ["en"])
    }

    func testHelperCollisionFailsBeforeRenaming() throws {
        let (root, c) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let main = c.source.appendingPathComponent("Contents/MacOS/Original")
        let helper = main.deletingLastPathComponent().appendingPathComponent("Helper")
        try FileManager.default.copyItem(at: main, to: helper)
        let bytes = try Data(contentsOf: helper)
        XCTAssertThrowsError(try ProcessNames.rename(in: c.source, main: main, name: "Helper"))
        XCTAssertEqual(try Data(contentsOf: helper), bytes)
        XCTAssertFalse(try helper.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink ?? true)
    }
}
