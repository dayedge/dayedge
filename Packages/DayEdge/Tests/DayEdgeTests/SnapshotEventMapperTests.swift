import CalendarIndex
import XCTest
@testable import Shell
@testable import Domain
@testable import Platform

/// `CalendarEventMapper.agendaEventModel(from: OccurrenceSnapshot, …)`
/// without EventKit: hand-made snapshots, the rules the live path follows.
final class SnapshotEventMapperTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_791_000_000)
    private let work = CalendarSnapshot(identifier: "cal", title: "Work",
                                        color: .init(red: 1, green: 0, blue: 0), allowsModifications: true)

    private func snapshot(_ configure: (inout OccurrenceSnapshot) -> Void = { _ in }) -> OccurrenceSnapshot {
        var s = OccurrenceSnapshot(calendarIdentifier: "cal", eventIdentifier: "ev-1", calendarItemIdentifier: "item-1",
                                   externalIdentifier: "UID-1", occurrenceDate: start,
                                   start: start, end: start.addingTimeInterval(3600), title: "Planning")
        configure(&s)
        return s
    }

    private func model(_ s: OccurrenceSnapshot, calendar: CalendarSnapshot? = nil) -> AgendaEventModel {
        CalendarEventMapper.agendaEventModel(from: s, calendar: calendar ?? work)
    }

    private func me(_ status: ParticipationStatus) -> [AttendeeSnapshot] {
        [AttendeeSnapshot(name: "Me", email: "me@example.com", status: status, isCurrentUser: true),
         AttendeeSnapshot(name: nil, email: nil, status: .accepted, isCurrentUser: false)]
    }

    func testBasicsMatchTheLiveRules() {
        let m = model(snapshot())
        XCTAssertEqual(m.id, "ev-1-\(start.timeIntervalSince1970)")
        XCTAssertEqual(m.title, "Planning")
        XCTAssertEqual(m.calendarName, "Work")
        XCTAssertEqual(m.startTime, CalendarEventMapper.timeFormatter.string(from: start))
        XCTAssertEqual(model(snapshot { $0.title = "" }).title, "(no title)")
        XCTAssertNil(model(snapshot { $0.isAllDay = true }).startTime)
    }

    func testStatusFromCancellationAndMyAnswer() {
        XCTAssertEqual(model(snapshot()).status, .confirmed)
        XCTAssertEqual(model(snapshot { $0.status = .canceled }).status, .cancelled)
        for (answer, expected) in [(ParticipationStatus.accepted, EventStatus.confirmed), (.declined, .cancelled),
                                   (.tentative, .tentative), (.pending, .tentative)] {
            let m = model(snapshot { $0.attendees = me(answer); $0.participation = answer })
            XCTAssertEqual(m.status, expected, "\(answer)")
        }
        let declined = model(snapshot { $0.attendees = me(.declined); $0.participation = .declined })
        XCTAssertEqual(declined.myResponseStatus, .declined)
        XCTAssertEqual(declined.attendees.map(\.name), ["Me", "Unknown"])
    }

    func testMeetingLinkPrefersEventURLThenServiceHostThenAnyLink() {
        XCTAssertEqual(model(snapshot { $0.url = "https://zoom.us/j/1" }).videoService, .zoom)
        let inNotes = model(snapshot { $0.notes = "Agenda https://example.com/doc join https://teams.microsoft.com/l/x" })
        XCTAssertEqual(inNotes.videoService, .teams)
        XCTAssertEqual(inNotes.videoURL, "https://teams.microsoft.com/l/x")
        let plain = model(snapshot { $0.location = "https://example.com/room" })
        XCTAssertNil(plain.videoService)
        XCTAssertEqual(plain.videoURL, "https://example.com/room")
        XCTAssertEqual(model(snapshot { $0.url = "https://example.com" }).videoService, .other)
    }

    func testRemovalReferenceOnlyForCancelledOnWritableCalendar() {
        XCTAssertNil(model(snapshot()).removalReference)
        XCTAssertNotNil(model(snapshot { $0.status = .canceled }).removalReference)
        var readOnly = work
        readOnly.allowsModifications = false
        XCTAssertNil(model(snapshot { $0.status = .canceled }, calendar: readOnly).removalReference)
    }

    func testEditReferenceForAnInvitation() {
        let invite = model(snapshot {
            $0.attendees = me(.pending)
            $0.hasAttendees = true
            $0.organizer = OrganizerSnapshot(name: "Boss", email: nil, isCurrentUser: false)
            $0.isInvitation = true
        })
        XCTAssertEqual(invite.editReference?.invitationFrom, "Boss")
        XCTAssertEqual(invite.editReference?.isInvitation, true)
        XCTAssertEqual(invite.editReference?.hasAttendees, true)
        XCTAssertNil(model(snapshot { $0.eventIdentifier = nil }).editReference)
    }

    func testRecurrenceReferenceAndRepeatRule() {
        XCTAssertNil(model(snapshot()).recurrenceReference)
        XCTAssertFalse(model(snapshot()).isRecurring)

        let weekly = model(snapshot {
            $0.isRecurring = true
            $0.hasOwnRecurrenceRules = true
            $0.recurrence = RecurrenceDescription(frequency: .weekly)
        })
        XCTAssertTrue(weekly.isRecurring)
        XCTAssertEqual(weekly.recurrence, .weekly)
        XCTAssertEqual(weekly.recurrenceRule?.frequency, .weekly)
        XCTAssertEqual(weekly.recurrenceReference?.seriesIdentifier, "UID-1")

        // A detached occurrence: series rule, series id without "/RID=".
        let detached = model(snapshot {
            $0.isRecurring = true
            $0.isDetached = true
            $0.externalIdentifier = "UID-1/RID=42"
            $0.recurrence = RecurrenceDescription(frequency: .monthly, daysOfWeek: [.init(weekday: 2, weekNumber: 1)])
        })
        XCTAssertTrue(detached.isRecurring)
        XCTAssertEqual(detached.recurrenceReference?.seriesIdentifier, "UID-1")
        guard case .custom = detached.recurrence else { return XCTFail("monthly on a weekday is custom") }

        // Series rule found for an item that isn't marked detached: repeating, no series reference.
        let exception = model(snapshot { $0.recurrence = RecurrenceDescription(frequency: .daily) })
        XCTAssertTrue(exception.isRecurring)
        XCTAssertNil(exception.recurrenceReference)
    }

    func testAlertsSkipLocationAlarms() {
        let alarmDate = start.addingTimeInterval(-86400)
        let m = model(snapshot {
            $0.alarms = [AlarmSnapshot(relativeOffset: -900), AlarmSnapshot(absoluteDate: alarmDate),
                         AlarmSnapshot(relativeOffset: 0, isLocationBased: true)]
        })
        XCTAssertEqual(m.alerts, [.before(minutes: 15), .at(alarmDate)])
    }

    func testReminderKeyUsesTheRawOccurrenceDate() {
        let single = model(snapshot())
        let live = ReminderOccurrenceKey.eventKit(calendarIdentifier: "cal", isRecurring: true, seriesIdentifier: "UID-1",
                                                  calendarItemIdentifier: "item-1", eventIdentifier: "ev-1",
                                                  startDate: start, occurrenceDate: start)
        XCTAssertEqual(single.reminderOccurrenceKey, live)
    }
}
