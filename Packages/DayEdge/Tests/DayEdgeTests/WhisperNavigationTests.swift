import XCTest
import TimeWhisper
@testable import Intelligence

final class WhisperNavigationTests: XCTestCase {
    func testExistingNavigationQueries() async throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.firstWeekday = 2
        let reference = calendar.date(from: DateComponents(year: 2026, month: 9, day: 23, hour: 12))!
        let parser = NaturalLanguageParser(spellCheckerFactory: { NoSpellChecker() })
        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Golden/search-pipeline.txt")
        let queries = try String(contentsOf: fixture, encoding: .utf8).split(separator: "\n").map {
            String($0.components(separatedBy: " → ")[0])
        }
        var actual: [String] = []
        for query in queries {
            let found = await parser.findTemporal(query, referenceDate: reference, calendar: calendar)
            let intent = found.flatMap { TemporalPresentation.navigation($0, calendar: calendar) }
            let value: String
            switch intent {
            case .jumpToDate(let date): value = "D " + iso(date, calendar: calendar)
            case .jumpToMonth(let date): value = "M " + iso(date, calendar: calendar)
            default: value = "—"
            }
            actual.append("\(query) → \(value)")
        }
        GoldenSnapshot.assertMatches(actual, named: "search-pipeline")
    }

    private func iso(_ date: Date, calendar: Calendar) -> String {
        let value = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", value.year!, value.month!, value.day!)
    }
}
