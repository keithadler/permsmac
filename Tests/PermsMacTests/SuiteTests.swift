import XCTest
@testable import PermsMac

final class SuiteTests: XCTestCase {
    @MainActor private func runSuite(_ name: String) {
        let results = TestKit.run(filter: name + "/")
        XCTAssertFalse(results.isEmpty)
        for r in results { for f in r.failures { XCTFail("\(r.suite)/\(r.name): \(f)") } }
    }
    @MainActor func testCatalog() { runSuite("Catalog") }
    @MainActor func testTCC() { runSuite("TCC") }
    @MainActor func testHistory() { runSuite("History") }
    @MainActor func testStartup() { runSuite("Startup") }
    @MainActor func testCLI() { runSuite("CLI") }
}
