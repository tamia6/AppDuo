import XCTest
@testable import CloneCore

final class ExecutableNameTests: XCTestCase {
    func testBuiltInPoliciesAndLegacyDecoding() throws {
        let recipes = try Recipes.load()
        let wecom = try XCTUnwrap(recipes.first { $0.bundleID == "com.tencent.WeWorkMac" })
        let wechat = try XCTUnwrap(recipes.first { $0.bundleID == "com.tencent.xinWeChat" })
        XCTAssertEqual(wecom.preserveMainExecutableName, true)
        XCTAssertNotEqual(wechat.preserveMainExecutableName, true)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(wecom)) as? [String: Any])
        object.removeValue(forKey: "preserveMainExecutableName")
        let legacy = try JSONDecoder().decode(Recipe.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertNil(legacy.preserveMainExecutableName)
        let (_, base) = try EngineTests().fixture()
        defer { try? FileManager.default.removeItem(at: base.source.deletingLastPathComponent()) }
        let config = CloneConfiguration(source: base.source, name: base.name, destination: base.destination, dataDirectory: base.dataDirectory, recipe: wecom)
        XCTAssertEqual(config.injection, .dylib)
    }

    func testCreateAndUpdateKeepWeComNameAndRenameWeChat() throws {
        for id in ["com.tencent.WeWorkMac", "com.tencent.xinWeChat"] {
            for injection in [Injection.dylib, .launcher] {
                let (root, base) = try EngineTests().fixture()
                defer { try? FileManager.default.removeItem(at: root) }
                // Match Intel clang output, which has no implicit ad-hoc signature.
                try Command.run("/usr/bin/codesign", ["--remove-signature", base.source.appendingPathComponent("Contents/MacOS/Original").path], acceptFailure: true)
                var c = base
                let recipe = try XCTUnwrap(Recipes.load().first { $0.bundleID == id })
                c.recipe = recipe; c.recipe.environment = base.recipe.environment; c.recipe.symlinks = []
                c.injection = injection
                let sourcePlist = c.source.appendingPathComponent("Contents/Info.plist")
                var source = try Plist.read(sourcePlist); source["CFBundleIdentifier"] = id
                try Plist.write(source, to: sourcePlist)
                _ = try CloneEngine().build(c)
                let marker = c.dataDirectory.appendingPathComponent("keep.txt")
                try Data("existing user data".utf8).write(to: marker)
                _ = try CloneEngine().build(c, updating: true)
                XCTAssertEqual(try Data(contentsOf: marker), Data("existing user data".utf8))
                let plist = try Plist.read(c.destination.appendingPathComponent("Contents/Info.plist"))
                let exe = try XCTUnwrap(plist["CFBundleExecutable"] as? String)
                let expectedMain = id == "com.tencent.WeWorkMac" ? "Original" : c.name
                XCTAssertEqual(exe, injection == .dylib ? expectedMain : c.name + "-Launcher")
                let output = try Command.run(c.destination.appendingPathComponent("Contents/MacOS/" + exe).path, [])
                XCTAssertTrue(output.contains("/" + expectedMain + "\n"), output)
                XCTAssertTrue(output.contains("quote' slash\\ $value\n中文"), output)
                let main = c.destination.appendingPathComponent("Contents/MacOS/" + expectedMain)
                XCTAssertFalse(try main.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink ?? true)
            }
        }
    }

    func testUpdatingLegacyWeComUsesCurrentPolicyWithoutMovingData() async throws {
        let (root, base) = try EngineTests().fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        var c = base; c.recipe.bundleID = "com.tencent.WeWorkMac"; c.injection = .dylib
        var source = try Plist.read(c.source.appendingPathComponent("Contents/Info.plist"))
        source["CFBundleIdentifier"] = c.recipe.bundleID
        try Plist.write(source, to: c.source.appendingPathComponent("Contents/Info.plist"))
        let repository = CloneRepository(root: root.appendingPathComponent("Records"))
        let before = try await repository.build(c, password: "", updating: false, log: { _ in })
        XCTAssertNil(before[0].configuration.recipe.preserveMainExecutableName)
        let marker = c.dataDirectory.appendingPathComponent("keep.txt")
        try Data("do not move or delete".utf8).write(to: marker)
        let after = try await repository.build(before[0].configuration, password: "", updating: true, log: { _ in })
        XCTAssertEqual(after[0].configuration.recipe.preserveMainExecutableName, true)
        XCTAssertEqual(after[0].id, before[0].id)
        XCTAssertEqual(after[0].createdAt, before[0].createdAt)
        XCTAssertEqual(after[0].configuration.dataDirectory, c.dataDirectory)
        XCTAssertEqual(try Data(contentsOf: marker), Data("do not move or delete".utf8))
        let plist = try Plist.read(c.destination.appendingPathComponent("Contents/Info.plist"))
        XCTAssertEqual(plist["CFBundleExecutable"] as? String, "Original")
    }
}
