import Foundation
import XCTest
@testable import Shell
@testable import Intelligence

/// A diagnostic baseline, not a claim that chrono already supports every phrase.
/// Reference: Wednesday 2026-09-23 at noon, in the host's local time zone.
/// Expected dates are the intended calendar-navigation targets, not chrono output.
final class ChronoBaselineTests: XCTestCase {
    private struct Case {
        let query: String
        let expected: String
    }

    // D = a specific day; M = a month. Year phrases navigate to January.
    // For week phrases, D means Monday of
    // that week. "Next Friday" means Friday of next calendar week, while bare
    // "Friday" means the next occurrence. Weekends target Saturday. Times of
    // day are intentionally judged only by their navigation day because
    // SearchIntent currently has no time-of-day destination.
    private let cases: [Case] = """
    today|D 2026-09-23
    tomorrow|D 2026-09-24
    yesterday|D 2026-09-22
    next week|D 2026-09-28
    last week|D 2026-09-14
    previous week|D 2026-09-14
    this week|D 2026-09-21
    next month|M 2026-10-01
    last month|M 2026-08-01
    previous month|M 2026-08-01
    this month|M 2026-09-01
    next year|M 2027-01-01
    last year|M 2025-01-01
    previous year|M 2025-01-01
    this year|M 2026-01-01
    in a week|D 2026-09-30
    in two weeks|D 2026-10-07
    in three weeks|D 2026-10-14
    a week from now|D 2026-09-30
    two weeks from now|D 2026-10-07
    one week ago|D 2026-09-16
    two weeks ago|D 2026-09-09
    a month from now|D 2026-10-23
    in one month|D 2026-10-23
    in two months|D 2026-11-23
    one month ago|D 2026-08-23
    two months ago|D 2026-07-23
    a year from now|D 2027-09-23
    in one year|D 2027-09-23
    one year ago|D 2025-09-23
    two years ago|D 2024-09-23
    next Monday|D 2026-09-28
    next Tuesday|D 2026-09-29
    next Wednesday|D 2026-09-30
    next Thursday|D 2026-10-01
    next Friday|D 2026-10-02
    next Saturday|D 2026-10-03
    next Sunday|D 2026-10-04
    last Monday|D 2026-09-21
    last Tuesday|D 2026-09-22
    last Wednesday|D 2026-09-16
    last Thursday|D 2026-09-17
    last Friday|D 2026-09-18
    last Saturday|D 2026-09-19
    last Sunday|D 2026-09-20
    this Monday|D 2026-09-21
    this Friday|D 2026-09-25
    Monday|D 2026-09-28
    Friday|D 2026-09-25
    Monday next week|D 2026-09-28
    Friday next week|D 2026-10-02
    Monday last week|D 2026-09-14
    Friday last week|D 2026-09-18
    the first day of this month|D 2026-09-01
    the first day of next month|D 2026-10-01
    the first day of last month|D 2026-08-01
    the last day of this month|D 2026-09-30
    the last day of next month|D 2026-10-31
    the last day of last month|D 2026-08-31
    beginning of this month|D 2026-09-01
    beginning of next month|D 2026-10-01
    beginning of last month|D 2026-08-01
    end of this month|D 2026-09-30
    end of next month|D 2026-10-31
    end of last month|D 2026-08-31
    beginning of the year|D 2026-01-01
    start of the year|D 2026-01-01
    end of the year|D 2026-12-31
    beginning of next year|D 2027-01-01
    end of next year|D 2027-12-31
    January 1|D 2027-01-01
    December 31|D 2026-12-31
    January 1 next year|D 2027-01-01
    December 31 this year|D 2026-12-31
    September 23|D 2026-09-23
    23 September|D 2026-09-23
    September 23 2026|D 2026-09-23
    23 September 2026|D 2026-09-23
    the 23rd of September|D 2026-09-23
    the 23rd of September 2026|D 2026-09-23
    Christmas|D 2026-12-25
    Christmas Day|D 2026-12-25
    Christmas this year|D 2026-12-25
    Christmas next year|D 2027-12-25
    New Year's Day|D 2027-01-01
    New Year's Eve|D 2026-12-31
    New Year's Day next year|D 2027-01-01
    the day before Christmas|D 2026-12-24
    the day after Christmas|D 2026-12-26
    two days before Christmas|D 2026-12-23
    two days after Christmas|D 2026-12-27
    three days before New Year's Eve|D 2026-12-28
    the week before Christmas|D 2026-12-14
    the week after Christmas|D 2026-12-28
    next weekend|D 2026-10-03
    this weekend|D 2026-09-26
    last weekend|D 2026-09-19
    next Monday morning|D 2026-09-28
    next Monday afternoon|D 2026-09-28
    next Monday evening|D 2026-09-28
    tomorrow morning|D 2026-09-24
    tomorrow afternoon|D 2026-09-24
    tomorrow evening|D 2026-09-24
    tonight|D 2026-09-23
    tomorrow at 9|D 2026-09-24
    tomorrow at 9am|D 2026-09-24
    tomorrow at 14:00|D 2026-09-24
    next Friday at noon|D 2026-10-02
    next Friday at midnight|D 2026-10-02
    Friday at 5pm|D 2026-09-25
    in 3 days|D 2026-09-26
    3 days from now|D 2026-09-26
    3 days ago|D 2026-09-20
    in 10 days|D 2026-10-03
    10 days from now|D 2026-10-03
    10 days ago|D 2026-09-13
    """.split(separator: "\n").map { line in
        let parts = line.split(separator: "|", maxSplits: 1)
        return Case(query: String(parts[0]), expected: String(parts[1]))
    }

    func testChronoNavigationBaseline() async {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.firstWeekday = 2
        let reference = calendar.date(from: DateComponents(year: 2026, month: 9, day: 23, hour: 12))!
        var outputCalendar = Calendar(identifier: .gregorian)
        outputCalendar.timeZone = .current
        let formatter = DateFormatter()
        formatter.calendar = outputCalendar
        formatter.timeZone = outputCalendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"

        var counts = ["OK": 0, "NO RESULT": 0, "WRONG": 0]
        print("\nCHRONO BASELINE — reference 2026-09-23 12:00 (host local time)")
        print("Status     | Query                              | Expected     | Actual")
        print("-----------+------------------------------------+--------------+----------------")
        for item in cases {
            let actual: String
            if let intent = await ChronoSearchIntentStage().resolve(item.query, referenceDate: reference, calendar: calendar) {
                switch intent {
                case .jumpToDate(let date): actual = "D " + formatter.string(from: date)
                case .jumpToMonth(let date): actual = "M " + formatter.string(from: date)
                case .freeTextSearch(let text): actual = "search " + text
                }
            } else {
                actual = "—"
            }
            let status = actual == "—" ? "NO RESULT" : (actual == item.expected ? "OK" : "WRONG")
            counts[status, default: 0] += 1
            print(String(format: "%-10s | %-34s | %-12s | %@",
                         (status as NSString).utf8String!, (item.query as NSString).utf8String!,
                         (item.expected as NSString).utf8String!, actual))
        }
        print("TOTAL: \(cases.count)  OK: \(counts["OK"]!)  NO RESULT: \(counts["NO RESULT"]!)  WRONG: \(counts["WRONG"]!)\n")
        XCTAssertEqual(cases.count, 116, "Keep the full user-supplied query set in this baseline")
    }

    /// NSDataDetector has no reference-date parameter: relative expressions
    /// are evaluated against the wall clock. This comparison is meaningful
    /// against the fixed oracle only on its reference day. Keep the original
    /// deterministic Chrono test above for future runs.
    func testNSDataDetectorSideBySideBaseline() async throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.firstWeekday = 2
        let now = Date.now
        let referenceDay = calendar.date(from: DateComponents(year: 2026, month: 9, day: 23))!
        guard calendar.isDate(now, inSameDayAs: referenceDay) else {
            throw XCTSkip("NSDataDetector uses the actual date; this fixed-oracle comparison requires 2026-09-23 locally")
        }

        let detector = try NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue)
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = calendar.locale
        formatter.dateFormat = "yyyy-MM-dd"

        var chronoCounts = ["OK": 0, "NO RESULT": 0, "WRONG": 0]
        var detectorCounts = ["OK": 0, "NO RESULT": 0, "WRONG": 0]
        print("\nCHRONO vs NSDATADETECTOR — wall-clock reference \(now), local date 2026-09-23")
        print("Both require exactly one full-string match. Detector dates have no D/M intent kind.")
        print("Query                              | Expected     | Chrono              | NSDataDetector")
        print("-----------------------------------+--------------+---------------------+---------------------")
        for item in cases {
            let chrono: String
            if let intent = await ChronoSearchIntentStage().resolve(item.query, referenceDate: now, calendar: calendar) {
                switch intent {
                case .jumpToDate(let date): chrono = "D " + formatter.string(from: date)
                case .jumpToMonth(let date): chrono = "M " + formatter.string(from: date)
                case .freeTextSearch: chrono = "—"
                }
            } else {
                chrono = "—"
            }

            let fullRange = NSRange(item.query.startIndex..<item.query.endIndex, in: item.query)
            let matches = detector.matches(in: item.query, options: [], range: fullRange)
            let detectedDate: String
            if matches.count == 1, matches[0].range == fullRange, let date = matches[0].date {
                detectedDate = formatter.string(from: date)
            } else {
                detectedDate = "—"
            }

            let expectedDate = String(item.expected.dropFirst(2))
            let chronoStatus = chrono == "—" ? "NO RESULT" : (chrono == item.expected ? "OK" : "WRONG")
            let detectorStatus = detectedDate == "—" ? "NO RESULT" : (detectedDate == expectedDate ? "OK" : "WRONG")
            chronoCounts[chronoStatus, default: 0] += 1
            detectorCounts[detectorStatus, default: 0] += 1
            let chronoCell = "\(chronoStatus): \(chrono)"
            let detectorCell = "\(detectorStatus): \(detectedDate)"
            let queryColumn = item.query.padding(toLength: 34, withPad: " ", startingAt: 0)
            let expectedColumn = item.expected.padding(toLength: 12, withPad: " ", startingAt: 0)
            let chronoColumn = chronoCell.padding(toLength: 19, withPad: " ", startingAt: 0)
            print("\(queryColumn) | \(expectedColumn) | \(chronoColumn) | \(detectorCell)")
        }
        print("TOTAL \(cases.count): Chrono OK \(chronoCounts["OK"]!), NO RESULT \(chronoCounts["NO RESULT"]!), WRONG \(chronoCounts["WRONG"]!)")
        print("TOTAL \(cases.count): NSDataDetector OK \(detectorCounts["OK"]!), NO RESULT \(detectorCounts["NO RESULT"]!), WRONG \(detectorCounts["WRONG"]!)\n")
    }

    /// Reports the effect of the app-specific stage without changing
    /// the Chrono-only baseline or depending on its score for test success.
    func testFullSearchPipelineBaseline() async {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.firstWeekday = 2
        let reference = calendar.date(from: DateComponents(year: 2026, month: 9, day: 23, hour: 12))!
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = calendar.locale
        formatter.dateFormat = "yyyy-MM-dd"

        var counts = ["OK": 0, "NO RESULT": 0, "WRONG": 0]
        var snapshot: [String] = []
        print("\nFULL SEARCH PIPELINE — reference 2026-09-23 12:00, local time")
        print("Status     | Query                              | Expected     | Actual")
        print("-----------+------------------------------------+--------------+----------------")
        for item in cases {
            let intent = await SearchIntentPipeline.live.resolve(item.query, referenceDate: reference, calendar: calendar)
            let actual: String
            switch intent {
            case .jumpToDate(let date): actual = "D " + formatter.string(from: date)
            case .jumpToMonth(let date): actual = "M " + formatter.string(from: date)
            case .freeTextSearch: actual = "—"
            }
            let status = actual == "—" ? "NO RESULT" : (actual == item.expected ? "OK" : "WRONG")
            counts[status, default: 0] += 1
            snapshot.append("\(item.query) → \(actual)")
            print(String(format: "%-10s | %-34s | %-12s | %@",
                         (status as NSString).utf8String!, (item.query as NSString).utf8String!,
                         (item.expected as NSString).utf8String!, actual))
        }
        print("TOTAL: \(cases.count)  OK: \(counts["OK"]!)  NO RESULT: \(counts["NO RESULT"]!)  WRONG: \(counts["WRONG"]!)\n")
        // What every query resolves to today (right or wrong): a change
        // shows up as a diff — an intended fix is accepted with
        // DAYEDGE_UPDATE_GOLDEN=1, an accident fails.
        GoldenSnapshot.assertMatches(snapshot, named: "search-pipeline")
    }
}
