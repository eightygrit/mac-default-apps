// What the Swift test programs share: counting a check, saying which failed, and the summary at the end.
import Foundation

var checks = 0
var failures = 0
let verbose = ProcessInfo.processInfo.environment["VERBOSE"] == "1"

func check<T: Equatable>(_ name: String, _ actual: T, _ expected: T) {
    checks += 1
    if actual == expected {
        if verbose { print("ok    \(name)") }
    } else {
        failures += 1
        print("FAIL  \(name)\n        expected: \(expected)\n        actual:   \(actual)")
    }
}

func section(_ title: String) { if verbose { print("\n-- \(title)") } }

/// Prints the summary and ends the program: status 1 if any check failed.
func finish() -> Never {
    print("\(checks - failures) of \(checks) checks passed" + (failures == 0 ? "" : ", \(failures) FAILED"))
    exit(failures == 0 ? 0 : 1)
}
