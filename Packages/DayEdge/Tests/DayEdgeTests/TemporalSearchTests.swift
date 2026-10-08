import Foundation
import XCTest
@testable import Shell
@testable import Intelligence

final class TemporalSearchTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "Europe/Warsaw")!
        value.locale = Locale(identifier: "en_US_POSIX")
        value.firstWeekday = 2
        return value
    }

    private var reference: Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: 23, hour: 12))!
    }

    private func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    private var noSpelling: TemporalQueryNormalizer {
        TemporalQueryNormalizer(suggestions: { _ in [] })
    }

    func testEveryAlias() {
        let examples: [(String, String)] = [
            ("prev", "previous"), ("nxt", "next"), ("cur", "this"),
            ("wk", "week"), ("wks", "weeks"),
            ("mo", "month"), ("mos", "months"), ("mth", "month"), ("mths", "months"),
            ("yr", "year"), ("yrs", "years"), ("yer", "year"), ("beg", "start"),
            ("mon", "monday"), ("tue", "tuesday"), ("tues", "tuesday"),
            ("wed", "wednesday"), ("thu", "thursday"), ("thur", "thursday"),
            ("thurs", "thursday"), ("fri", "friday"), ("sat", "saturday"),
            ("sun", "sunday"),
            ("bom", "start of month"), ("eom", "end of month"),
            ("boy", "start of year"), ("eoy", "end of year")
        ]
        for (query, expected) in examples {
            XCTAssertEqual(noSpelling.normalize(query).normalized, expected, query)
        }
    }

    func testTypoCorrectionsUseOnlyUnambiguousWhitelistedSuggestions() {
        let suggestions: [String: [String]] = [
            "previuos": ["pervious", "previous"], "prevoius": ["previous"],
            "nexxt": ["next"], "moth": ["mosh", "month"],
            "mont": ["most", "month"], "weeek": ["week"],
            "beggining": ["beginning"], "weeekend": ["weekend"],
            "fryday": ["fry day", "Friday"]
        ]
        let normalizer = TemporalQueryNormalizer(suggestions: { suggestions[$0] ?? [] })
        let examples: [(String, String)] = [
            ("previuos moth", "previous month"),
            ("prevoius month", "previous month"),
            ("nexxt mont", "next month"),
            ("weeek", "week"), ("beggining", "start"),
            ("weeekend", "weekend"),
            ("meeting with Jon next fryday", "meeting with jon next friday")
        ]
        for (query, expected) in examples {
            XCTAssertEqual(normalizer.normalize(query).normalized, expected, query)
        }
        let result = normalizer.normalize("previuos moth")
        XCTAssertEqual(result.original, "previuos moth")
        XCTAssertEqual(result.corrections.map(\.reason), [.spelling, .spelling])
    }

    func testAmbiguousAndUnknownWordsStayUntouched() {
        let normalizer = TemporalQueryNormalizer(suggestions: { token in
            if token == "meeting" { return ["morning", "midnight"] }
            return ["office", "person"]
        })
        XCTAssertEqual(normalizer.normalize("May mar jun jul in on at of to").normalized,
                       "may mar jun jul in on at of to")
        XCTAssertEqual(normalizer.normalize("meeting next to office").normalized,
                       "meeting next to office")
        XCTAssertEqual(normalizer.normalize("Jon").normalized, "jon")
    }

    func testWhitespacePunctuationAndBoundaryCanonicalization() {
        XCTAssertEqual(noSpelling.normalize("  Prev   Moth  ").normalized, "previous moth")
        XCTAssertEqual(noSpelling.normalize("NXT MTH?").normalized, "next month")
        XCTAssertEqual(noSpelling.normalize("beg next mo").normalized, "start next month")
        XCTAssertEqual(noSpelling.normalize("beginning of next month").normalized, "start of next month")
        XCTAssertEqual(noSpelling.normalize("first day of next month").normalized, "start of next month")
        XCTAssertEqual(noSpelling.normalize("the last day of this month").normalized, "the end of this month")
        XCTAssertEqual(noSpelling.normalize("mon nxt wk").normalized, "monday next week")
        XCTAssertEqual(noSpelling.normalize("thurs last wk").normalized, "thursday last week")
    }

    func testPeriodsAndBoundaries() {
        let parser = TemporalIntentParser()
        let expected: [(String, SearchIntent)] = [
            ("previous week", .jumpToDate(day(2026, 9, 14))),
            ("next month", .jumpToMonth(day(2026, 10, 1))),
            ("next year", .jumpToMonth(day(2027, 1, 1))),
            ("this year", .jumpToMonth(day(2026, 1, 1))),
            ("start next month", .jumpToDate(day(2026, 10, 1))),
            ("end of last month", .jumpToDate(day(2026, 8, 31))),
            ("the start of the year", .jumpToDate(day(2026, 1, 1))),
            ("end of next year", .jumpToDate(day(2027, 12, 31))),
            ("this weekend", .jumpToDate(day(2026, 9, 26))),
            ("next weekend", .jumpToDate(day(2026, 10, 3))),
            ("last weekend", .jumpToDate(day(2026, 9, 19)))
        ]
        for (query, intent) in expected {
            XCTAssertEqual(parser.resolve(query, referenceDate: reference, calendar: calendar), intent, query)
        }
    }

    func testWeekdayConventionsAndWholeQueryRule() {
        let parser = TemporalIntentParser()
        let expected: [(String, SearchIntent)] = [
            ("this monday", .jumpToDate(day(2026, 9, 21))),
            ("next monday", .jumpToDate(day(2026, 9, 28))),
            ("last monday", .jumpToDate(day(2026, 9, 21))),
            ("monday", .jumpToDate(day(2026, 9, 28))),
            ("monday last week", .jumpToDate(day(2026, 9, 14))),
            ("next sunday", .jumpToDate(day(2026, 10, 4))),
            ("today", .jumpToDate(day(2026, 9, 23))),
            ("tomorrow", .jumpToDate(day(2026, 9, 24)))
        ]
        for (query, intent) in expected {
            XCTAssertEqual(parser.resolve(query, referenceDate: reference, calendar: calendar), intent, query)
        }
        XCTAssertNil(parser.resolve("meeting next to office", referenceDate: reference, calendar: calendar))
        XCTAssertNil(parser.resolve("meeting with jon next friday", referenceDate: reference, calendar: calendar))
        XCTAssertNil(parser.resolve("christmas", referenceDate: reference, calendar: calendar))
    }

    func testWeekFirstThenTheDay() {
        let parser = TemporalIntentParser()
        let expected: [(String, SearchIntent)] = [
            ("next week monday", .jumpToDate(day(2026, 9, 28))),
            ("next week sunday", .jumpToDate(day(2026, 10, 4))),
            ("this week friday", .jumpToDate(day(2026, 9, 25))),
            ("this week monday", .jumpToDate(day(2026, 9, 21))),
            ("last week tuesday", .jumpToDate(day(2026, 9, 15))),
            ("previous week wednesday", .jumpToDate(day(2026, 9, 16)))
        ]
        for (query, intent) in expected {
            XCTAssertEqual(parser.resolve(query, referenceDate: reference, calendar: calendar), intent, query)
            // Same meaning as the day-first order.
            let words = query.split(separator: " ")
            let dayFirst = "\(words[2]) \(words[0]) \(words[1])"
            XCTAssertEqual(parser.resolve(dayFirst, referenceDate: reference, calendar: calendar), intent, dayFirst)
        }
        XCTAssertNil(parser.resolve("next week monday meeting", referenceDate: reference, calendar: calendar), "still the whole query")
        XCTAssertNil(parser.resolve("week next monday", referenceDate: reference, calendar: calendar))
    }

    func testDayOfAMonthPhrase() {
        let parser = TemporalIntentParser()
        let expected: [(String, SearchIntent)] = [
            ("next month 12", .jumpToDate(day(2026, 10, 12))),
            ("12 next month", .jumpToDate(day(2026, 10, 12))),
            ("12th next month", .jumpToDate(day(2026, 10, 12))),
            ("next month 1st", .jumpToDate(day(2026, 10, 1))),
            ("the 3rd of next month", .jumpToDate(day(2026, 10, 3))),
            ("this month 30", .jumpToDate(day(2026, 9, 30))),
            ("last month 28", .jumpToDate(day(2026, 8, 28))),
            ("previous month 31", .jumpToDate(day(2026, 8, 31))),
            ("next month 31", .jumpToDate(day(2026, 10, 31)))
        ]
        for (query, intent) in expected {
            XCTAssertEqual(parser.resolve(query, referenceDate: reference, calendar: calendar), intent, query)
        }
        let rejected = [
            "this month 31",          // September has 30 days
            "next month 0", "next month 32", "next month 12 13",
            "next week 12",           // a day number needs a month
            "next month 12 meeting",  // still the whole query
            "12", "12th", "month 12"  // no direction
        ]
        for query in rejected {
            XCTAssertNil(parser.resolve(query, referenceDate: reference, calendar: calendar), query)
        }
    }

    func testOffsetsFromToday() {
        let parser = TemporalIntentParser()
        let expected: [(String, SearchIntent)] = [
            ("in 3 weeks", .jumpToDate(day(2026, 10, 14))),
            ("in 10 days", .jumpToDate(day(2026, 10, 3))),
            ("in 2 months", .jumpToDate(day(2026, 11, 23))),
            ("in 1 year", .jumpToDate(day(2027, 9, 23))),
            ("in a week", .jumpToDate(day(2026, 9, 30))),
            ("in two weeks", .jumpToDate(day(2026, 10, 7))),
            ("in one month", .jumpToDate(day(2026, 10, 23))),
            ("three days ago", .jumpToDate(day(2026, 9, 20))),
            ("twelve days from now", .jumpToDate(day(2026, 10, 5))),
            ("3 weeks from now", .jumpToDate(day(2026, 10, 14))),
            ("10 days from today", .jumpToDate(day(2026, 10, 3))),
            ("2 days ago", .jumpToDate(day(2026, 9, 21))),
            ("a month ago", .jumpToDate(day(2026, 8, 23))),
            ("today + 3 weeks", .jumpToDate(day(2026, 10, 14))),
            ("today - 2 days", .jumpToDate(day(2026, 9, 21))),
            ("+10 days", .jumpToDate(day(2026, 10, 3))),
            ("+ 10 days", .jumpToDate(day(2026, 10, 3))),
            ("-2 days", .jumpToDate(day(2026, 9, 21)))
        ]
        for (query, intent) in expected {
            XCTAssertEqual(parser.resolve(query, referenceDate: reference, calendar: calendar), intent, query)
        }
        let rejected = ["in 3", "in weeks", "in 0 days", "in 3 hours", "3 weeks", "in 3 weeks friday",
                        "3 weeks from tomorrow", "today 3 weeks", "in 1000 days", "meeting in 3 weeks"]
        for query in rejected {
            XCTAssertNil(parser.resolve(query, referenceDate: reference, calendar: calendar), query)
        }
    }

    func testWeekNumbers() {
        let parser = TemporalIntentParser()
        let expected: [(String, SearchIntent)] = [
            ("week 42", .jumpToDate(day(2026, 10, 12))),
            ("week 1", .jumpToDate(day(2025, 12, 29))),   // ISO week 1 of 2026 starts in December
            ("week 42 2027", .jumpToDate(day(2027, 10, 18))),
            ("week 53 2026", .jumpToDate(day(2026, 12, 28)))  // 2026 has 53 ISO weeks
        ]
        for (query, intent) in expected {
            XCTAssertEqual(parser.resolve(query, referenceDate: reference, calendar: calendar), intent, query)
        }
        for query in ["week 54", "week 0", "week 53 2027", "week 42 27", "week", "42 week"] {
            XCTAssertNil(parser.resolve(query, referenceDate: reference, calendar: calendar), query)
        }
    }

    func testPipelineOffsetsAreDaysNotMonths() async {
        // Chrono alone read "in 3 weeks" as a month.
        let pipeline = SearchIntentPipeline(stages: [TemporalSearchIntentStage(normalizer: noSpelling)])
        let expected: [(String, SearchIntent)] = [
            ("In 3 Weeks", .jumpToDate(day(2026, 10, 14))),
            ("in 2 wks", .jumpToDate(day(2026, 10, 7))),
            ("wk 42", .jumpToDate(day(2026, 10, 12)))
        ]
        for (query, intent) in expected {
            let actual = await pipeline.resolve(query, referenceDate: reference, calendar: calendar)
            XCTAssertEqual(actual, intent, query)
        }
    }

    func testPipelineShortNamesInTheNewOrders() async {
        let pipeline = SearchIntentPipeline(stages: [TemporalSearchIntentStage(normalizer: noSpelling)])
        let expected: [(String, SearchIntent)] = [
            ("next week mon", .jumpToDate(day(2026, 9, 28))),
            ("Next Week Fri", .jumpToDate(day(2026, 10, 2))),
            ("nxt wk tue", .jumpToDate(day(2026, 9, 29))),
            ("next mo 12", .jumpToDate(day(2026, 10, 12))),
            ("12th nxt mth", .jumpToDate(day(2026, 10, 12)))
        ]
        for (query, intent) in expected {
            let actual = await pipeline.resolve(query, referenceDate: reference, calendar: calendar)
            XCTAssertEqual(actual, intent, query)
        }
    }

    func testPipelineUsesNormalizedMatchButPassesOriginalToFallback() async {
        let temporal = TemporalSearchIntentStage(normalizer: noSpelling)
        let pipeline = SearchIntentPipeline(stages: [temporal, EchoStage()])
        let match = await pipeline.resolve("  Prev WK  ", referenceDate: reference, calendar: calendar)
        XCTAssertEqual(match, .jumpToDate(day(2026, 9, 14)))
        let fallback = await pipeline.resolve("  Meeting next to Office  ", referenceDate: reference, calendar: calendar)
        XCTAssertEqual(fallback, .freeTextSearch("Meeting next to Office"))
    }

    func testPipelineTypoAndCompactBoundaryExamples() async {
        let substitutions: [String: [String]] = [
            "moth": ["mosh", "month"], "previuos": ["previous"],
            "weeekend": ["weekend"], "fryday": ["Friday"]
        ]
        let normalizer = TemporalQueryNormalizer(suggestions: { substitutions[$0] ?? [] })
        let pipeline = SearchIntentPipeline(stages: [
            TemporalSearchIntentStage(normalizer: normalizer), EchoStage()
        ])
        let expected: [(String, SearchIntent)] = [
            ("prev moth", .jumpToMonth(day(2026, 8, 1))),
            ("previuos moth", .jumpToMonth(day(2026, 8, 1))),
            ("nxt mo", .jumpToMonth(day(2026, 10, 1))),
            ("eom", .jumpToDate(day(2026, 9, 30))),
            ("weeekend", .jumpToDate(day(2026, 9, 26))),
            ("mon next wk", .jumpToDate(day(2026, 9, 28)))
        ]
        for (query, intent) in expected {
            let actual = await pipeline.resolve(query, referenceDate: reference, calendar: calendar)
            XCTAssertEqual(actual, intent, query)
        }
        let embedded = await pipeline.resolve(
            "Meeting with Jon next fryday", referenceDate: reference, calendar: calendar
        )
        XCTAssertEqual(embedded, .freeTextSearch("Meeting with Jon next fryday"))
    }

    private struct EchoStage: SearchIntentPipelineStage {
        let name = "echo"
        func resolve(_ text: String, referenceDate: Date, calendar: Calendar) async -> SearchIntent? {
            .freeTextSearch(text)
        }
    }
}
