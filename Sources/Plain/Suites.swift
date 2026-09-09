//  Plain for Mac — MIT licensed. See LICENSE.
//
//  Which suites `plainmac selftest` runs, and how the result is said.

import Foundation

enum Suites {
    @MainActor
    static func run(filter: String?, list: Bool, json wantsJSON: Bool) -> Int32 {
        if list {
            for s in TestKit.suites { for c in s.cases { CLI.out("\(s.name)/\(c.name)") } }
            return 0
        }

        let results = TestKit.run(filter: filter)
        let failed = results.filter { !$0.passed && $0.skipped == nil }
        let checks = results.reduce(0) { $0 + $1.checks }
        let ms = results.reduce(0.0) { $0 + $1.ms }

        if wantsJSON {
            CLI.out(CLI.json([
                "cases": results.count, "checks": checks, "failed": failed.count,
                "ms": Int(ms),
                "failures": failed.flatMap { r in r.failures.map { "\(r.suite)/\(r.name): \($0)" } },
            ]))
        } else {
            for r in results where !r.passed && r.skipped == nil {
                for f in r.failures { CLI.out("  FAIL  \(r.suite)/\(r.name): \(f)") }
            }
            for r in results where r.skipped != nil {
                CLI.out("  skip  \(r.suite)/\(r.name): \(r.skipped!)")
            }
            CLI.out("app: \(checks) checks in \(results.count) cases, \(failed.count) failed in \(Int(ms)) ms")
        }
        return failed.isEmpty ? 0 : 1
    }
}
