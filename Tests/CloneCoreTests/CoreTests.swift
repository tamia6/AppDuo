import XCTest
@testable import CloneCore
final class CoreTests: XCTestCase {
    func testLaunchMatchesClonePathIncludingAliasesButNotOriginal() throws {
        let fm = FileManager.default
        let base = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let clone = base.appendingPathComponent("WeWork.app")
        let alias = base.appendingPathComponent("Alias.app")
        try fm.createDirectory(at: clone, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: base) }
        try fm.createSymbolicLink(at: alias, withDestinationURL: clone)
        XCTAssertTrue(Inspector.sameApplication(alias, as: clone))
        XCTAssertTrue(Inspector.sameApplication(URL(fileURLWithPath: clone.path, isDirectory: true), as: URL(fileURLWithPath: clone.path, isDirectory: false)))
        XCTAssertFalse(Inspector.sameApplication(base.appendingPathComponent("WeChat.app"), as: clone))
        XCTAssertFalse(Inspector.sameApplication(nil, as: clone))
    }
    func testLegacyStorageRemainsAccessibleThroughAppDuo() throws {
        let fm = FileManager.default
        let base = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let legacy = base.appendingPathComponent("ATBCloneSwift")
        let root = base.appendingPathComponent("AppDuo")
        try fm.createDirectory(at: legacy, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: base) }
        try Data("[]".utf8).write(to: legacy.appendingPathComponent("clones.json"))
        try CloneRepository.prepareRoot(root, legacy: legacy)
        try CloneRepository.prepareRoot(root, legacy: legacy)
        XCTAssertEqual(root.resolvingSymlinksInPath(), legacy.resolvingSymlinksInPath())
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("clones.json")), Data("[]".utf8))
        try fm.removeItem(at: root)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        try CloneRepository.prepareRoot(root, legacy: legacy)
        XCTAssertNotEqual(root.resolvingSymlinksInPath(), legacy.resolvingSymlinksInPath())
    }
    func testRecipesAndValidation() throws {
        XCTAssertGreaterThanOrEqual(try Recipes.load().count, 34)
        XCTAssertThrowsError(try validateName("../unsafe"))
        XCTAssertNoThrow(try validateName("WeWork 工作"))
        var proxy = ProxySettings(); proxy.username = "a@b"
        XCTAssertTrue(try proxy.url(password: "p:/@").contains("a%40b"))
        proxy.port = 0; XCTAssertThrowsError(try proxy.url())
    }
    func testMalformedMachOIsRejected() throws {
        XCTAssertThrowsError(try MachO.inject(Data([0, 1, 2]), library: "@executable_path/test.dylib"))
    }
}
