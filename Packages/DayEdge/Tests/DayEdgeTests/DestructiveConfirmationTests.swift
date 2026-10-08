import AppKit
import XCTest
@testable import Shell
@testable import Domain
@testable import Platform
@testable import UI

@MainActor
final class DestructiveConfirmationTests: XCTestCase {
    func testRemovalCopyMatchesScope() {
        XCTAssertEqual(CalendarRemovalScope.occurrence.title, "Remove this occurrence?")
        XCTAssertEqual(CalendarRemovalScope.occurrence.message, "Other events in this series won’t be affected.")
        XCTAssertEqual(CalendarRemovalScope.event.title, "Remove this event?")
        XCTAssertEqual(CalendarRemovalScope.event.message, "This removes it from your calendar.")
        XCTAssertEqual(CalendarRemovalScope.futureOccurrences.message, "Earlier events in this series won’t be affected.")
        XCTAssertEqual(CalendarRemovalScope.series.title, "Remove this series?")
        XCTAssertEqual(CalendarRemovalScope.series.message, "All occurrences in this series will be removed.")
    }

    func testSuccessfulEventKitRemovalShowsSuccessNotice() {
        let removal = FakeRemovalService()
        let notices = NoticeCenter()
        let coordinator = makeCoordinator(removal: removal, notices: notices)

        coordinator.removeCancelledEvent(event(isRecurring: true))

        XCTAssertEqual(removal.calls, 1)
        XCTAssertEqual(notices.currentNotice?.style, .success)
        XCTAssertEqual(notices.currentNotice?.title, "Occurrence removed")
        XCTAssertNil(notices.currentNotice?.action, "Committed EventKit removal must not offer fake Undo")
    }

    func testFailedEventKitRemovalShowsErrorNotice() {
        let removal = FakeRemovalService(error: EventRemovalError.calendarNotWritable)
        let notices = NoticeCenter()
        let coordinator = makeCoordinator(removal: removal, notices: notices)

        coordinator.removeCancelledEvent(event(isRecurring: false))

        XCTAssertEqual(removal.calls, 1)
        XCTAssertEqual(notices.currentNotice?.style, .error)
        XCTAssertEqual(notices.currentNotice?.title, "Couldn’t remove event")
        XCTAssertEqual(notices.currentNotice?.message, "This calendar can no longer be modified.")
    }

    func testMuteNoticeUndoRestoresTheSameOccurrence() {
        let suite = "ReminderActionTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let suppression = ReminderSuppressionStore(defaults: defaults)
        let notices = NoticeCenter()
        let coordinator = makeCoordinator(
            removal: FakeRemovalService(), notices: notices,
            reminderSuppression: suppression
        )
        let start = Date.now.addingTimeInterval(3600)
        let key = ReminderOccurrenceKey.eventKit(
            calendarIdentifier: "work", isRecurring: true,
            seriesIdentifier: "daily", calendarItemIdentifier: "item",
            eventIdentifier: "event", startDate: start, occurrenceDate: start
        )!
        let event = AgendaEventModel(
            startTime: "10:00", endTime: "10:30", startDate: start,
            endDate: start.addingTimeInterval(1800), title: "Standup",
            reminderOccurrenceKey: key
        )

        coordinator.muteReminders(for: event)
        XCTAssertTrue(suppression.isMuted(event))
        XCTAssertEqual(notices.currentNotice?.title, "Reminders muted")
        XCTAssertEqual(notices.currentNotice?.action?.title, "Undo")

        notices.performAction(for: notices.currentNotice!.id)
        XCTAssertFalse(suppression.isMuted(event))
        XCTAssertEqual(notices.currentNotice?.title, "Reminders restored")
    }

    private func event(isRecurring: Bool) -> AgendaEventModel {
        let reference = EventRemovalReference(
            eventIdentifier: "event", calendarIdentifier: "calendar",
            occurrenceStart: .now, occurrenceEnd: .now.addingTimeInterval(3600)
        )
        return AgendaEventModel(
            title: "Cancelled", status: .cancelled, isRecurring: isRecurring,
            removalReference: reference
        )
    }

    private func makeCoordinator(
        removal: FakeRemovalService, notices: NoticeCenter,
        reminderSuppression: ReminderSuppressionStore? = nil
    ) -> EventActionCoordinator {
        EventActionCoordinator(
            appleCalendar: FakeCalendarOpener(), removalService: removal,
            occurrenceFinder: FakeOccurrenceFinder(), noticeCenter: notices,
            reminderSuppression: reminderSuppression ?? ReminderSuppressionStore(),
            onNavigateOccurrence: { _ in }
        )
    }
}

private final class FakeRemovalService: CalendarEventRemoving {
    let error: Error?
    var calls = 0

    init(error: Error? = nil) { self.error = error }

    func removeCancelledOccurrence(_ reference: EventRemovalReference) throws {
        calls += 1
        if let error { throw error }
    }
}

private struct FakeCalendarOpener: AppleCalendarOpening {
    func openWithDetails(calendarItemIdentifier: String, occurrenceDate: Date) -> Bool { true }
}

private actor FakeOccurrenceFinder: RecurringOccurrenceFinding {
    func adjacent(to reference: RecurringSeriesReference, direction: OccurrenceDirection) async -> OccurrenceNavigationTarget? {
        nil
    }
}
