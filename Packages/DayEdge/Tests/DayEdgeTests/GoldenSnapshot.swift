import Foundation
import XCTest

/// A plain-text snapshot of what a parser produces for a fixed set of
/// phrases, kept in `Tests/DayEdgeTests/Golden/`. Any difference fails
/// with the changed lines. When a change is intended, run the tests with
/// `DAYEDGE_UPDATE_GOLDEN=1` to rewrite the snapshot, and review its diff
/// in the commit.
enum GoldenSnapshot {
    static func assertMatches(_ lines: [String], named name: String, filePath: StaticString = #filePath,
                              file: StaticString = #filePath, line: UInt = #line) {
        let url = URL(fileURLWithPath: "\(filePath)").deletingLastPathComponent()
            .appendingPathComponent("Golden/\(name).txt")
        let actual = lines.joined(separator: "\n") + "\n"
        if ProcessInfo.processInfo.environment["DAYEDGE_UPDATE_GOLDEN"] == "1" {
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? actual.write(to: url, atomically: true, encoding: .utf8)
            return
        }
        guard let expected = try? String(contentsOf: url, encoding: .utf8) else {
            return XCTFail("No snapshot \(name).txt — run with DAYEDGE_UPDATE_GOLDEN=1 to create it", file: file, line: line)
        }
        guard expected != actual else { return }
        let old = expected.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let new = actual.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var changes: [String] = []
        for index in 0..<max(old.count, new.count) {
            let before = index < old.count ? old[index] : "(none)"
            let after = index < new.count ? new[index] : "(none)"
            if before != after { changes.append("  was: \(before)\n  now: \(after)") }
        }
        XCTFail("\(name): \(changes.count) line(s) changed (DAYEDGE_UPDATE_GOLDEN=1 to accept):\n" + changes.prefix(40).joined(separator: "\n"),
                file: file, line: line)
    }
}
