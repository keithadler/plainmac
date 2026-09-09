import XCTest
@testable import Plain

/// The app's own checks, run again under XCTest so `swift test` and CI see them.
///
/// They live in TestKit rather than in XCTest because `Plain selftest` has to run them from inside the shipped
/// app, where XCTest is not present. This is the same set, reported the way a test runner expects.
final class SuiteTests: XCTestCase {
    @MainActor private func runSuite(_ name: String) {
        let results = TestKit.run(filter: name + "/")
        // Counted, not just non-empty: a filter that stops matching would otherwise pass silently having run
        // nothing at all, which is the shape of green that hides everything.
        XCTAssertGreaterThan(results.count, 20, "only \(results.count) cases named \(name)")
        for r in results { for f in r.failures { XCTFail("\(r.suite)/\(r.name): \(f)") } }
    }

    @MainActor func testEngine() { runSuite("engine") }
}
