import XCTest
@testable import Shell
@testable import Platform

final class AppleCalendarBridgeTests: XCTestCase {
    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    func testExactURLShapeMatchesTheSpecExample() {
        // 2026-09-22 15:45:00 +02:00 == 2026-09-22 13:45:00 UTC
        var plusTwo = Calendar(identifier: .gregorian)
        plusTwo.timeZone = TimeZone(secondsFromGMT: 2 * 3600)!
        let date = plusTwo.date(from: DateComponents(year: 2026, month: 9, day: 22, hour: 15, minute: 45))!

        let url = AppleCalendarBridge.deepLinkURL(
            calendarItemIdentifier: "52F02092-C5FC-40D2-84C6-9C1D5469B62F",
            occurrenceDate: date
        )

        XCTAssertEqual(
            url?.absoluteString,
            "ical://ekevent/20260922T134500Z/52F02092-C5FC-40D2-84C6-9C1D5469B62F?method=show&options=more"
        )
    }

    func testDateComponentIsAlwaysUTCWithNoOffsetOrPunctuation() {
        let date = utc.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: 0, minute: 0, second: 0))!
        let url = AppleCalendarBridge.deepLinkURL(calendarItemIdentifier: "abc", occurrenceDate: date)

        let datePart = url?.absoluteString.split(separator: "/")[2]
        XCTAssertEqual(datePart, "20260101T000000Z")
        XCTAssertFalse(datePart?.contains("-") ?? true)
        XCTAssertFalse(datePart?.contains(":") ?? true)
        XCTAssertFalse(datePart?.contains("+") ?? true)
    }

    func testIdentifierWithReservedCharactersIsPercentEncoded() {
        let date = utc.date(from: DateComponents(year: 2026, month: 1, day: 1))!
        let url = AppleCalendarBridge.deepLinkURL(calendarItemIdentifier: "ABC/DEF?GHI", occurrenceDate: date)

        // The reserved characters must not have restructured the URL —
        // encoded, they can't be mistaken for path/query separators, so
        // `.query` stays exactly `method=show&options=more` rather than
        // being corrupted by the identifier's own literal `?`.
        XCTAssertEqual(url?.query, "method=show&options=more")
        XCTAssertEqual(
            url?.absoluteString,
            "ical://ekevent/20260101T000000Z/ABC%2FDEF%3FGHI?method=show&options=more"
        )
    }

    func testPlainUUIDIdentifierRoundTripsUnencoded() {
        let date = utc.date(from: DateComponents(year: 2026, month: 1, day: 1))!
        let url = AppleCalendarBridge.deepLinkURL(
            calendarItemIdentifier: "52F02092-C5FC-40D2-84C6-9C1D5469B62F", occurrenceDate: date
        )

        XCTAssertEqual(
            url?.absoluteString,
            "ical://ekevent/20260101T000000Z/52F02092-C5FC-40D2-84C6-9C1D5469B62F?method=show&options=more"
        )
    }
}
