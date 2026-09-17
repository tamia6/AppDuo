import XCTest
@testable import CloneCore
final class CoreTests: XCTestCase {
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
