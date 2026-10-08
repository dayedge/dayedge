import XCTest
@testable import Shell
@testable import Domain
@testable import UI

final class MeetingHUDOccurrenceTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func date(_ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: 21, hour: hour, minute: minute))!
    }

    private func event(
        _ id: String, start: Date, end: Date,
        status: EventStatus = .confirmed,
        videoService: VideoConferenceService? = .zoom,
        videoURL: String? = "https://zoom.us/j/1",
        attendees: [EventAttendee] = [],
        isAllDayLiteral: Bool = false
    ) -> AgendaEventModel {
        AgendaEventModel(
            id: id,
            startTime: isAllDayLiteral ? nil : "09:00", endTime: isAllDayLiteral ? nil : "10:00",
            startDate: start, endDate: end,
            title: id, status: status,
            videoService: videoService,
            tint: .orange,
            videoURL: videoURL,
            attendees: attendees
        )
    }

    private func attendee(_ name: String) -> EventAttendee {
        EventAttendee(name: name, status: .accepted)
    }

    private func configuration(showFor: MeetingHUDShowFor = .meetingsWithLink, leadMinutes: Int = 15) -> MeetingHUDConfiguration {
        var configuration = MeetingHUDConfiguration.default
        configuration.showFor = showFor
        configuration.leadTimeMinutes = leadMinutes
        return configuration
    }

    func testEventWithinLeadWindowIsResolved() {
        let meeting = event("Planning", start: date(10), end: date(11))
        let occurrence = resolveMeetingHUDOccurrence(events: [meeting], now: date(9, 50), configuration: configuration())

        XCTAssertEqual(occurrence?.id, "Planning")
        XCTAssertEqual(occurrence?.start, date(10))
        XCTAssertEqual(occurrence?.end, date(11))
    }

    func testEventOutsideLeadWindowIsNotResolved() {
        let meeting = event("Later", start: date(10), end: date(11))
        let occurrence = resolveMeetingHUDOccurrence(events: [meeting], now: date(9, 0), configuration: configuration())
        XCTAssertNil(occurrence)
    }

    func testAtStartTimingDoesNotShowBeforeTheMeeting() {
        let meeting = event("Planning", start: date(10), end: date(11))
        XCTAssertNil(resolveMeetingHUDOccurrence(
            events: [meeting], now: date(9, 59), configuration: configuration(leadMinutes: 0)
        ))
        XCTAssertEqual(
            resolveMeetingHUDOccurrence(
                events: [meeting], now: date(10), configuration: configuration(leadMinutes: 0)
            )?.id,
            "Planning"
        )
    }

    func testRemovedLeadTimeOptionFallsBackToFiveMinutes() {
        XCTAssertEqual(MeetingHUDSettings.normalizedLeadTime(10), 5)
        XCTAssertEqual(MeetingHUDSettings.normalizedLeadTime(15), 5)
        XCTAssertEqual(MeetingHUDSettings.normalizedLeadTime(0), 0)
        XCTAssertEqual(MeetingHUDSettings.normalizedLeadTime(1), 1)
        XCTAssertEqual(MeetingHUDSettings.normalizedLeadTime(5), 5)
    }

    func testBackToBackMeetingsHandOffAtNextStart() {
        let first = event("First", start: date(10), end: date(11))
        let second = event("Second", start: date(10, 30), end: date(11, 30))
        let occurrence = resolveMeetingHUDOccurrence(events: [first, second], now: date(10, 30), configuration: configuration())
        XCTAssertEqual(occurrence?.id, "Second")
    }

    func testShowForAllTimedEventsIncludesEventsWithNoLink() {
        let meeting = event("Personal Block", start: date(10), end: date(11), videoService: nil, videoURL: nil)
        let occurrence = resolveMeetingHUDOccurrence(
            events: [meeting], now: date(9, 50), configuration: configuration(showFor: .allTimedEvents)
        )
        XCTAssertEqual(occurrence?.id, "Personal Block")
        XCTAssertNil(occurrence?.meetingURL)
    }

    func testShowForMeetingsWithLinkExcludesEventsWithNoLink() {
        let meeting = event("Personal Block", start: date(10), end: date(11), videoService: nil, videoURL: nil)
        let occurrence = resolveMeetingHUDOccurrence(
            events: [meeting], now: date(9, 50), configuration: configuration(showFor: .meetingsWithLink)
        )
        XCTAssertNil(occurrence)
    }

    func testCancelledEventIsExcluded() {
        let meeting = event("Cancelled", start: date(10), end: date(11), status: .cancelled)
        let occurrence = resolveMeetingHUDOccurrence(events: [meeting], now: date(9, 50), configuration: configuration())
        XCTAssertNil(occurrence)
    }

    func testAllDayEventIsExcluded() {
        let meeting = event("All Day", start: date(0), end: date(23, 59), isAllDayLiteral: true)
        let occurrence = resolveMeetingHUDOccurrence(events: [meeting], now: date(9, 50), configuration: configuration())
        XCTAssertNil(occurrence)
    }

    func testEmptyAttendeesYieldsNilParticipantCount() {
        let meeting = event("Solo", start: date(10), end: date(11), attendees: [])
        let occurrence = resolveMeetingHUDOccurrence(events: [meeting], now: date(9, 50), configuration: configuration())
        XCTAssertNil(occurrence?.participantCount)
    }

    func testNonEmptyAttendeesYieldsCount() {
        let meeting = event("Group", start: date(10), end: date(11), attendees: [attendee("A"), attendee("B"), attendee("C")])
        let occurrence = resolveMeetingHUDOccurrence(events: [meeting], now: date(9, 50), configuration: configuration())
        XCTAssertEqual(occurrence?.participantCount, 3)
    }

    func testResolvedOccurrenceRetainsCompleteEventDetails() {
        let attendees = [attendee("Alex"), attendee("Sam")]
        let meeting = AgendaEventModel(
            id: "Planning",
            startTime: "10:00",
            endTime: "11:00",
            startDate: date(10),
            endDate: date(11),
            title: "Planning",
            subtitle: "Conference Room",
            videoService: .zoom,
            hasLinkIcon: true,
            isRecurring: true,
            tint: .orange,
            calendarName: "Work",
            notes: "Bring the roadmap",
            videoURL: "https://zoom.us/j/1",
            attendees: attendees,
            myResponseStatus: .accepted
        )

        let occurrence = resolveMeetingHUDOccurrence(
            events: [meeting], now: date(9, 50), configuration: configuration()
        )

        XCTAssertEqual(occurrence?.event, meeting)
        XCTAssertEqual(occurrence?.event.calendarName, "Work")
        XCTAssertEqual(occurrence?.event.notes, "Bring the roadmap")
        XCTAssertEqual(occurrence?.event.attendees, attendees)
        XCTAssertEqual(occurrence?.event.myResponseStatus, .accepted)
    }
}
