import XCTest
@testable import Plain

final class SuiteTests: XCTestCase {
    @MainActor private func runSuite(_ name: String) {
        let results = TestKit.run(filter: name + "/")
        XCTAssertFalse(results.isEmpty)
        for r in results { for f in r.failures { XCTFail("\(r.suite)/\(r.name): \(f)") } }
    }
    @MainActor func testCollector() { runSuite("Collector") }
    @MainActor func testNames() { runSuite("Names") }
    @MainActor func testLedger() { runSuite("Ledger") }
    @MainActor func testCLI() { runSuite("CLI") }
}
