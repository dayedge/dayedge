import XCTest
@testable import Shell
@testable import Domain
@testable import Intelligence

@MainActor
final class ChatEventCacheTests: XCTestCase {
    func testReadsADayOnceUntilTheCalendarChanges() {
        let center = NotificationCenter()
        var reads = 0
        var title = "Standup"
        let cache = ChatEventCache(load: { _ in
            reads += 1
            return [AgendaEventModel(id: "a", title: title), AgendaEventModel(id: "b", title: "Review")]
        }, notificationCenter: center)
        let day = Calendar.current.startOfDay(for: Date())

        XCTAssertEqual(cache.event("a", on: day)?.title, "Standup")
        XCTAssertEqual(cache.event("b", on: day)?.title, "Review")
        XCTAssertNil(cache.event("gone", on: day))
        XCTAssertEqual(reads, 1, "one read per day, however many rows ask")

        title = "Standup (moved)"
        center.post(name: .calendarEventsDidChange, object: nil)
        XCTAssertEqual(cache.event("a", on: day)?.title, "Standup (moved)")
        XCTAssertEqual(reads, 2)
        XCTAssertEqual(cache.revision, 1)
    }
}
