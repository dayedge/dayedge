import XCTest
@testable import Shell
@testable import Domain

final class RecurringOccurrenceResolverTests: XCTestCase {
    private let hour: TimeInterval = 3_600

    private func reference() -> RecurringSeriesReference {
        RecurringSeriesReference(
            seriesIdentifier: "series", calendarIdentifier: "work",
            sourceEventID: "source", sourceStart: Date(timeIntervalSince1970: 10 * hour),
            sourceOccurrenceDate: Date(timeIntervalSince1970: 10 * hour)
        )
    }

    private func candidate(
        _ id: String, at hour: Double, series: String = "series", calendar: String = "work",
        occurrenceHour: Double? = nil, relevant: Bool = true
    ) -> RecurringOccurrenceCandidate {
        RecurringOccurrenceCandidate(
            seriesIdentifier: series, calendarIdentifier: calendar, eventID: id,
            startDate: Date(timeIntervalSince1970: hour * self.hour),
            occurrenceDate: occurrenceHour.map { Date(timeIntervalSince1970: $0 * self.hour) },
            isRelevant: relevant
        )
    }

    func testFindsNearestInEitherDirectionRegardlessOfFetchOrder() {
        let values = [candidate("later", at: 30), candidate("previous", at: 8),
                      candidate("next", at: 12), candidate("earlier", at: 2)]
        XCTAssertEqual(RecurringOccurrenceResolver.closest(to: reference(), direction: .next, among: values)?.eventID, "next")
        XCTAssertEqual(RecurringOccurrenceResolver.closest(to: reference(), direction: .previous, among: values)?.eventID, "previous")
    }

    func testSkipsCancelledDeclinedAndDuplicateSeriesOnOtherCalendars() {
        let values = [candidate("cancelled", at: 11, relevant: false),
                      candidate("other-calendar", at: 11, calendar: "personal"),
                      candidate("other-series", at: 11, series: "different"),
                      candidate("next", at: 13)]
        XCTAssertEqual(RecurringOccurrenceResolver.closest(to: reference(), direction: .next, among: values)?.eventID, "next")
    }

    func testMovedSourceIsNotReturnedAsItsOwnNeighbor() {
        let values = [candidate("moved-source", at: 9, occurrenceHour: 10),
                      candidate("previous", at: 8, occurrenceHour: 8)]
        XCTAssertEqual(RecurringOccurrenceResolver.closest(to: reference(), direction: .previous, among: values)?.eventID, "previous")
    }

    func testTargetAndMissingNeighbor() {
        let values = [candidate("next", at: 24)]
        XCTAssertEqual(
            RecurringOccurrenceResolver.closest(to: reference(), direction: .next, among: values),
            OccurrenceNavigationTarget(eventID: "next", startDate: Date(timeIntervalSince1970: 24 * hour))
        )
        XCTAssertNil(RecurringOccurrenceResolver.closest(to: reference(), direction: .previous, among: values))
    }

    func testSearchWindowsRemainContiguousAndStopAtConfiguredHorizon() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let start = Date(timeIntervalSince1970: 0)
        for direction in [OccurrenceDirection.previous, .next] {
            let years = direction == .next
                ? AppConfiguration.recurrenceNavigationHorizonYears
                : -AppConfiguration.recurrenceNavigationHorizonYears
            let limit = calendar.date(byAdding: .year, value: years, to: start)!
            var cursor = start
            var count = 0
            while let window = RecurringOccurrenceResolver.nextSearchWindow(
                from: cursor, limit: limit, direction: direction, calendar: calendar
            ) {
                XCTAssertEqual(direction == .next ? window.start : window.end, cursor)
                cursor = direction == .next ? window.end : window.start
                count += 1
                XCTAssertLessThan(count, 25)
            }
            XCTAssertEqual(cursor, limit)
        }
    }
}
