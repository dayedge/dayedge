import EventKit
import XCTest
@testable import Shell
@testable import Domain

final class EventDetailsTests: XCTestCase {
    private let store = EKEventStore()
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    private func event() -> EKEvent {
        let event = EKEvent(eventStore: store)
        event.title = "Dentist"
        event.startDate = start
        event.endDate = start.addingTimeInterval(3600)
        return event
    }

    private func roundTrip(_ original: EKEvent) -> EKEvent {
        let copy = event()
        EventDetails(original).apply(to: copy)
        return copy
    }

    /// Availability needs a saved calendar (in memory it always reads as
    /// not supported), so only the decision is tested here.
    /// Domain mirrors these EventKit raw values without importing EventKit.
    func testDefaultsMatchEventKit() {
        XCTAssertEqual(EventDetails.availabilityNotSupported, EKEventAvailability.notSupported.rawValue)
        XCTAssertEqual(EventAlarm.proximityNone, EKAlarmProximity.none.rawValue)
    }

    func testLinkTimeZoneAndMapLocationComeBack() throws {
        let original = event()
        original.url = URL(string: "https://example.com/booking/42")
        original.timeZone = TimeZone(identifier: "America/New_York")
        let place = EKStructuredLocation(title: "Dental Clinic")
        place.geoLocation = CLLocation(latitude: 52.2297, longitude: 21.0122)
        place.radius = 150
        original.structuredLocation = place

        let copy = roundTrip(original)

        XCTAssertEqual(copy.url, original.url)
        XCTAssertEqual(copy.timeZone, original.timeZone)
        let location = try XCTUnwrap(copy.structuredLocation)
        XCTAssertEqual(location.title, "Dental Clinic")
        XCTAssertEqual(try XCTUnwrap(location.geoLocation?.coordinate.latitude), 52.2297, accuracy: 0.000_001)
        XCTAssertEqual(try XCTUnwrap(location.geoLocation?.coordinate.longitude), 21.0122, accuracy: 0.000_001)
        XCTAssertEqual(location.radius, 150)
    }

    func testAFloatingEventStaysFloating() {
        let original = event()
        original.timeZone = nil
        let copy = event()
        copy.timeZone = TimeZone(identifier: "Europe/Warsaw")
        EventDetails(original).apply(to: copy)
        XCTAssertNil(copy.timeZone)
    }

    func testEveryAlarmComesBackAsItWas() throws {
        let original = event()
        original.addAlarm(EKAlarm(relativeOffset: -900))
        original.addAlarm(EKAlarm(absoluteDate: start.addingTimeInterval(-86_400)))
        let arriving = EKAlarm(relativeOffset: 0)
        arriving.structuredLocation = EKStructuredLocation(title: "Office")
        arriving.proximity = .enter
        original.addAlarm(arriving)
        let sound = EKAlarm(relativeOffset: -300)
        sound.soundName = "Glass"
        original.addAlarm(sound)

        let copy = roundTrip(original)

        // EventKit lists alarms in its own order.
        XCTAssertEqual(Set((copy.alarms ?? []).map(EventAlarm.init)), Set((original.alarms ?? []).map(EventAlarm.init)))
        XCTAssertEqual(copy.alarms?.count, 4)
        let location = try XCTUnwrap(copy.alarms?.first { $0.structuredLocation != nil })
        XCTAssertEqual(location.proximity, .enter)
        XCTAssertEqual(location.structuredLocation?.title, "Office")
        XCTAssertEqual(copy.alarms?.first { $0.soundName != nil }?.soundName, "Glass")
    }

    func testAvailabilityIsWrittenOnlyWhereTheCalendarSupportsIt() {
        XCTAssertTrue(EventDetails.supports(.free, in: [.busy, .free]))
        XCTAssertFalse(EventDetails.supports(.tentative, in: [.busy, .free]))
        XCTAssertFalse(EventDetails.supports(.free, in: []))
        XCTAssertFalse(EventDetails.supports(.notSupported, in: nil))
        XCTAssertTrue(EventDetails.supports(.busy, in: nil), "not in a calendar yet: nothing to check against")
    }

    func testApplyingReplacesAlarmsInsteadOfAddingToThem() {
        let original = event()
        original.addAlarm(EKAlarm(relativeOffset: -600))
        let copy = event()
        copy.addAlarm(EKAlarm(relativeOffset: -600))
        EventDetails(original).apply(to: copy)
        XCTAssertEqual(copy.alarms?.count, 1)
    }

    func testTheUndoDraftKeepsAlertsAndDetails() {
        let details = EventDetails(url: URL(string: "https://example.com"), timeZone: nil,
                                   availability: EKEventAvailability.busy.rawValue,
                                   alarms: [EventAlarm(relativeOffset: -900)])
        let snapshot = EventSnapshot(eventIdentifier: "e1", calendarIdentifier: "c1", calendarTitle: "Home", title: "Dentist",
                                     start: start, end: start.addingTimeInterval(3600), isAllDay: false,
                                     location: "Clinic", notes: "Bring card", hasAttendees: false, isRecurring: false,
                                     alerts: [.before(minutes: 15)], details: details)
        XCTAssertEqual(snapshot.draft.alerts, [.before(minutes: 15)])
        XCTAssertEqual(snapshot.draft.details, details)
        XCTAssertTrue(snapshot.canRecreate)
    }

    func testMeetingsAndRepeatingEventsCantBeRecreated() {
        func snapshot(attendees: Bool, recurring: Bool) -> EventSnapshot {
            EventSnapshot(eventIdentifier: "e1", calendarIdentifier: "c1", calendarTitle: "Home", title: "Sync",
                          start: start, end: start, isAllDay: false, location: nil, notes: nil,
                          hasAttendees: attendees, isRecurring: recurring)
        }
        XCTAssertFalse(snapshot(attendees: true, recurring: false).canRecreate)
        XCTAssertFalse(snapshot(attendees: false, recurring: true).canRecreate)
    }
}
