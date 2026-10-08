import AppKit
import XCTest
@testable import Shell
@testable import Domain
@testable import Platform
@testable import UI

final class EventContextMenuPlanTests: XCTestCase {
    private func removalReference() -> EventRemovalReference {
        EventRemovalReference(
            eventIdentifier: "abc", calendarIdentifier: "cal-1",
            occurrenceStart: Date(timeIntervalSince1970: 0), occurrenceEnd: Date(timeIntervalSince1970: 3600)
        )
    }

    private func recurrenceReference() -> RecurringSeriesReference {
        RecurringSeriesReference(
            seriesIdentifier: "series-1", calendarIdentifier: "cal-1",
            sourceEventID: "occurrence-1", sourceStart: Date(timeIntervalSince1970: 0),
            sourceOccurrenceDate: Date(timeIntervalSince1970: 0)
        )
    }

    func testOnlineMeetingMenu() {
        let event = AgendaEventModel(
            title: "Standup", videoService: .zoom, videoURL: "https://zoom.us/j/123456789"
        )
        XCTAssertEqual(
            EventContextMenuPlan.actions(for: event),
            [.joinVideoCall, .copyMeetingLink, .openInAppleCalendar]
        )
    }

    func testPlainEventMenu() {
        let event = AgendaEventModel(title: "1:1")
        XCTAssertEqual(EventContextMenuPlan.actions(for: event), [.openInAppleCalendar])
    }

    func testEventWithMappableLocationMenu() {
        let event = AgendaEventModel(title: "Coffee", subtitle: "Blue Bottle Coffee")
        XCTAssertEqual(
            EventContextMenuPlan.actions(for: event),
            [.openLocationInMaps(location: "Blue Bottle Coffee"), .openInAppleCalendar]
        )
    }

    func testEventWithGenericLocationOmitsMapsItem() {
        let event = AgendaEventModel(title: "Standup", subtitle: "Office")
        XCTAssertEqual(EventContextMenuPlan.actions(for: event), [.openInAppleCalendar])
    }

    func testGenuinelyCancelledWritableEventOffersRemoval() {
        let event = AgendaEventModel(title: "Cancelled Meeting", status: .cancelled, removalReference: removalReference())
        XCTAssertEqual(
            EventContextMenuPlan.actions(for: event),
            [.openInAppleCalendar, .divider, .removeFromCalendar]
        )
    }

    /// A merely *declined* event also carries `.cancelled` status (see
    /// `CalendarEventMapper.eventStatus(for:)`) but must never offer
    /// removal — it's still a live meeting for every other attendee.
    func testDeclinedEventDoesNotOfferRemoval() {
        let event = AgendaEventModel(title: "Declined Meeting", status: .cancelled, removalReference: nil)
        XCTAssertEqual(EventContextMenuPlan.actions(for: event), [.openInAppleCalendar])
    }

    func testCancelledEventNeverShowsJoinOrCopyLinkEvenWithAMeetingLink() {
        let event = AgendaEventModel(
            title: "Cancelled Call", status: .cancelled,
            videoService: .zoom, videoURL: "https://zoom.us/j/123456789",
            removalReference: removalReference()
        )
        XCTAssertEqual(
            EventContextMenuPlan.actions(for: event),
            [.openInAppleCalendar, .divider, .removeFromCalendar]
        )
    }

    func testRecurringMeetingGroupsLikeCalendar() {
        let event = AgendaEventModel(
            title: "Standup", videoService: .zoom, isRecurring: true,
            videoURL: "https://zoom.us/j/123456789", recurrenceReference: recurrenceReference()
        )
        XCTAssertEqual(EventContextMenuPlan.actions(for: event), [
            .joinVideoCall, .copyMeetingLink, .openInAppleCalendar, .divider,
            .nextOccurrence, .previousOccurrence
        ], "the event's own actions, then its occurrences — next first, as in Calendar")
    }

    func testCancelledRecurringEventStillOffersNavigationAndRemoval() {
        let event = AgendaEventModel(
            title: "Cancelled meeting", status: .cancelled, isRecurring: true,
            removalReference: removalReference(), recurrenceReference: recurrenceReference()
        )
        XCTAssertEqual(EventContextMenuPlan.actions(for: event), [
            .openInAppleCalendar, .divider,
            .nextOccurrence, .previousOccurrence, .divider,
            .removeFromCalendar
        ])
    }

    func testRecurringEventWithoutReliableSeriesIdentityOmitsNavigation() {
        let event = AgendaEventModel(title: "Birthday", isRecurring: true)
        XCTAssertEqual(EventContextMenuPlan.actions(for: event), [.openInAppleCalendar])
    }

    func testRecurringAllDayEventOffersNavigation() {
        let event = AgendaEventModel(
            title: "Birthday", isRecurring: true, recurrenceReference: recurrenceReference()
        )
        XCTAssertTrue(event.isAllDay)
        XCTAssertEqual(EventContextMenuPlan.actions(for: event), [
            .openInAppleCalendar, .divider, .nextOccurrence, .previousOccurrence
        ])
    }

    func testReminderActionIsItsOwnGroupAndTracksMuteState() {
        let start = Date(timeIntervalSince1970: 2_000_000_000)
        let key = ReminderOccurrenceKey.eventKit(
            calendarIdentifier: "work", isRecurring: true,
            seriesIdentifier: "daily", calendarItemIdentifier: "item",
            eventIdentifier: "event", startDate: start, occurrenceDate: start
        )!
        let event = AgendaEventModel(
            startTime: "10:00", endTime: "10:30", startDate: start,
            endDate: start.addingTimeInterval(1800), title: "Standup",
            status: .cancelled, isRecurring: true,
            removalReference: removalReference(), reminderOccurrenceKey: key,
            recurrenceReference: recurrenceReference()
        )
        XCTAssertEqual(EventContextMenuPlan.actions(for: event), [
            .openInAppleCalendar, .divider, .nextOccurrence, .previousOccurrence, .divider,
            .muteReminders, .divider, .removeFromCalendar
        ])
        XCTAssertEqual(EventContextMenuPlan.actions(for: event, remindersMuted: true), [
            .openInAppleCalendar, .divider, .nextOccurrence, .previousOccurrence, .divider,
            .restoreReminders, .divider, .removeFromCalendar
        ])
    }

    func testDividersOnlyBetweenGroupsThatHaveSomething() {
        let menus = [
            EventContextMenuPlan.actions(for: AgendaEventModel(title: "1:1")),
            EventContextMenuPlan.actions(for: AgendaEventModel(title: "Mine"), editability: .editable),
            EventContextMenuPlan.actions(for: AgendaEventModel(title: "Birthday", isRecurring: true,
                                                               recurrenceReference: recurrenceReference()))
        ]
        for menu in menus {
            XCTAssertNotEqual(menu.first, .divider)
            XCTAssertNotEqual(menu.last, .divider)
            XCTAssertFalse(zip(menu, menu.dropFirst()).contains { $0 == .divider && $1 == .divider })
        }
        XCTAssertEqual(menus[1], [.openInAppleCalendar, .divider, .deleteEvent])
    }

    func testEveryItemHasASymbolAndTheShortcutsAreThePanels() {
        let items: [EventContextMenuAction] = [
            .joinVideoCall, .copyMeetingLink, .openLocationInMaps(location: "x"), .openInAppleCalendar,
            .nextOccurrence, .previousOccurrence, .muteReminders, .restoreReminders, .removeFromCalendar, .deleteEvent
        ]
        for item in items {
            let symbol = try? XCTUnwrap(item.symbolName)
            XCTAssertNotNil(symbol.flatMap { NSImage(systemSymbolName: $0, accessibilityDescription: nil) }, "\(item)")
        }
        let shortcuts = items.compactMap(\.shortcut).compactMap { ShortcutCommand.action($0).defaultShortcut?.displayLabel }
        XCTAssertEqual(shortcuts, ["⌘J", "⇧⌘C", "⌘O", "⌘]", "⌘["])
        XCTAssertNil(EventContextMenuAction.deleteEvent.shortcut, "never a key for deleting")
    }

    func testShowInCalendarIsOfferedOnlyForSearchResults() {
        let event = AgendaEventModel(title: "Standup", videoService: .zoom, videoURL: "https://zoom.us/j/123456789")
        XCTAssertFalse(EventContextMenuPlan.actions(for: event).contains(.showInCalendar), "the agenda already shows it")
        XCTAssertEqual(EventContextMenuPlan.actions(for: event, inSearch: true),
                       [.joinVideoCall, .copyMeetingLink, .showInCalendar, .openInAppleCalendar],
                       "in DayEdge, then in Apple Calendar")
        XCTAssertNotNil(EventContextMenuAction.showInCalendar.symbolName.flatMap { NSImage(systemSymbolName: $0, accessibilityDescription: nil) })
        XCTAssertNil(EventContextMenuAction.showInCalendar.shortcut, "its key is search's Tab, not a panel shortcut")
    }
}
