import XCTest
@testable import CloneCore

final class EngineTests: XCTestCase {
    func testNestedCodeBundleIsResealedAfterSigningItsExecutable() throws {
        let (root, config) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let bundle = config.source.appendingPathComponent("Contents/Helpers/Updater.bundle")
        let executable = bundle.appendingPathComponent("Contents/MacOS/SoftwareUpdaterExecutable")
        try FileManager.default.createDirectory(at: executable.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: config.source.appendingPathComponent("Contents/MacOS/Original"), to: executable)
        try Plist.write(["CFBundleIdentifier": "com.atb.updater", "CFBundleExecutable": "SoftwareUpdaterExecutable", "CFBundlePackageType": "BNDL"], to: bundle.appendingPathComponent("Contents/Info.plist"))
        let helper = bundle.appendingPathComponent("Contents/Helpers/tool")
        try FileManager.default.createDirectory(at: helper.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: executable, to: helper)
        try Command.run("/usr/bin/codesign", ["--force", "--sign", "-", helper.path])
        try Command.run("/usr/bin/codesign", ["--force", "--sign", "-", bundle.path])
        _ = try CloneEngine().build(config)
        try Command.run("/usr/bin/codesign", ["--verify", "--deep", "--strict", config.destination.path])
    }
    func testLaunchArgumentsPersistAndExpandOnCreateAndEdit() async throws {
        for strategy in Strategy.allCases {
            let (root, base) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
            var config = base; config.recipe.strategy = strategy
            config.recipe.arguments = ["--recipe-default", "--profile={{ATB_DATA_DIR}}", " spaces 中文 ' \" \\ $HOME; $(echo test) "]
            let repository = CloneRepository(root: root.appendingPathComponent("Records"))
            _ = try await repository.build(config, password: "", updating: false, log: { _ in })
            var records = try await repository.load()
            XCTAssertEqual(records[0].configuration.recipe.arguments, config.recipe.arguments)
            let launcher = config.destination.appendingPathComponent("Contents/MacOS/WeWork-Launcher")
            let result = try Command.run(launcher.path, ["forwarded argument"])
            XCTAssertTrue(result.hasSuffix("--recipe-default\n--profile=\(config.dataDirectory.path)\n spaces 中文 ' \" \\ $HOME; $(echo test) \nforwarded argument\n"), result)
            var edited = records[0].configuration
            edited.recipe.arguments = ["--edited={{ATB_DATA_DIR}}/Profile with spaces"]
            _ = try await repository.build(edited, password: "", updating: true, log: { _ in })
            records = try await repository.load()
            XCTAssertEqual(records[0].configuration.recipe.arguments, edited.recipe.arguments)
            XCTAssertTrue(try Command.run(launcher.path, []).hasSuffix("--edited=\(config.dataDirectory.path)/Profile with spaces\n"))
            edited.recipe.arguments = []
            _ = try await repository.build(edited, password: "", updating: true, log: { _ in })
            records = try await repository.load()
            XCTAssertEqual(records[0].configuration.recipe.arguments, [])
            let metadata = try Plist.read(config.destination.appendingPathComponent("Contents/Info.plist"))
            let executable = try XCTUnwrap(metadata["CFBundleExecutable"] as? String)
            let cleared = try Command.run(config.destination.appendingPathComponent("Contents/MacOS/" + executable).path, [])
            XCTAssertFalse(cleared.contains("--edited="), cleared)
        }
    }
    func testRepositoryUpdateAcceptsEquivalentPaths() async throws {
        let (root, config) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = CloneRepository(root: root.appendingPathComponent("Records"))
        let records = try await repository.build(config, password: "", updating: false, log: { _ in })
        var edited = records[0].configuration
        edited.destination = URL(fileURLWithPath: edited.destination.path, isDirectory: true)
        edited.displayName = "Updated name"
        let updated = try await repository.build(edited, password: "", updating: true, log: { _ in })
        XCTAssertEqual(updated.count, 1)
        XCTAssertEqual(updated[0].configuration.displayName, "Updated name")
        XCTAssertEqual(updated[0].id, records[0].id)
        let alias = root.appendingPathComponent("Alias.app")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: config.destination)
        var duplicate = config; duplicate.id = UUID(); duplicate.name = "Another"; duplicate.destination = alias
        do {
            _ = try await repository.build(duplicate, password: "", updating: false, log: { _ in })
            XCTFail("Equivalent destination must be rejected")
        } catch { XCTAssertEqual(error.localizedDescription, "分身名称或位置已存在") }
        edited.destination = root.appendingPathComponent("Different.app")
        do {
            _ = try await repository.build(edited, password: "", updating: true, log: { _ in })
            XCTFail("A genuinely different destination must be rejected")
        } catch { XCTAssertEqual(error.localizedDescription, "找不到待更新分身") }
    }
    func testSourceUpdateDetectionAndUpgrade() throws {
        let (root, config) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let sourcePlist = config.source.appendingPathComponent("Contents/Info.plist")
        var metadata = try Plist.read(sourcePlist)
        metadata["CFBundleShortVersionString"] = "1.9"
        metadata["CFBundleVersion"] = "9"
        try Plist.write(metadata, to: sourcePlist)
        _ = try CloneEngine().build(config)
        XCTAssertNil(try CloneUpdates.availableVersion(for: config))
        for (version, build, expected) in [("1.10", "1", "1.10" as String?), ("1.8", "99", nil), ("1.9", "10", "1.9 (10)"), ("1.9", "8", nil)] {
            metadata["CFBundleShortVersionString"] = version
            metadata["CFBundleVersion"] = build
            try Plist.write(metadata, to: sourcePlist)
            XCTAssertEqual(try CloneUpdates.availableVersion(for: config), expected)
        }
        metadata["CFBundleShortVersionString"] = "1.10"
        try Plist.write(metadata, to: sourcePlist)
        var soft = config; soft.recipe.strategy = .soft
        XCTAssertNil(try CloneUpdates.availableVersion(for: soft))
        let marker = config.dataDirectory.appendingPathComponent("keep.txt")
        try Data("login data".utf8).write(to: marker)
        _ = try CloneEngine().build(config, updating: true)
        XCTAssertNil(try CloneUpdates.availableVersion(for: config))
        XCTAssertEqual(try Data(contentsOf: marker), Data("login data".utf8))
        try FileManager.default.removeItem(at: sourcePlist)
        XCTAssertThrowsError(try CloneUpdates.availableVersion(for: config))
    }
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
