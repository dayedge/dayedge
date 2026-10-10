import XCTest
@testable import Shell
@testable import Domain
@testable import Platform
@testable import UI
@testable import Agenda

/// Who may change what (`EventEditability`), the menu built from it, and
/// the coordinator's writes — against a fake editor.
@MainActor
final class EventEditingTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 2_000_000_000)

    private func event(writable: Bool = true, invitationFrom: String? = nil, invitation: Bool = false,
                       attendees: Bool = false, recurring: Bool = false, status: EventStatus = .confirmed,
                       reference: Bool = true) -> AgendaEventModel {
        AgendaEventModel(
            id: "e", startTime: "10:00", endTime: "11:00",
            startDate: start, endDate: start.addingTimeInterval(3600), title: "Review", status: status,
            isRecurring: recurring,
            editReference: reference ? EventEditReference(
                eventIdentifier: "ek", calendarIdentifier: "cal", occurrenceStart: start,
                occurrenceEnd: start.addingTimeInterval(3600), isWritable: writable,
                invitationFrom: invitationFrom, isInvitation: invitation, hasAttendees: attendees || invitation
            ) : nil
        )
    }

    // MARK: - The rules

    func testWhatCanBeChanged() {
        XCTAssertEqual(EventEditability.of(event()), .editable)
        XCTAssertEqual(EventEditability.of(event(attendees: true)), .meeting)
        XCTAssertEqual(EventEditability.of(event(invitationFrom: "Anna", invitation: true)), .invitation(organizer: "Anna"))
        XCTAssertEqual(EventEditability.of(event(writable: false)), .readOnly)
        XCTAssertEqual(EventEditability.of(event(status: .cancelled)), .readOnly, "cancelled ones have their own Remove")
        XCTAssertEqual(EventEditability.of(event(reference: false)), .readOnly, "nothing to find it by")

        XCTAssertTrue(EventEditability.editable.canEdit)
        XCTAssertFalse(EventEditability.meeting.canEdit)
        XCTAssertFalse(EventEditability.invitation(organizer: nil).canEdit)
        XCTAssertTrue(EventEditability.meeting.canDelete)
        XCTAssertTrue(EventEditability.invitation(organizer: nil).canDelete)
        XCTAssertFalse(EventEditability.readOnly.canDelete)
    }

    func testDeletingWarnsWhereNobodyIsTold() {
        XCTAssertNil(EventEditability.editable.deleteWarning)
        XCTAssertEqual(EventEditability.invitation(organizer: "Anna").deleteWarning, "Anna won't be notified. To decline, respond in Apple Calendar.")
        XCTAssertTrue(EventEditability.meeting.deleteWarning?.hasPrefix("Attendees won't be notified") == true)
        XCTAssertNotNil(EventEditability.meeting.readOnlyReason)
        XCTAssertNil(EventEditability.editable.readOnlyReason)
    }

    // MARK: - The menu

    func testTheMenuOffersDeleteWhereAllowed() {
        let plain = EventContextMenuPlan.actions(for: event(), editability: .editable)
        XCTAssertEqual(plain.suffix(2), [.divider, .deleteEvent])

        let readOnly = EventContextMenuPlan.actions(for: event(writable: false), editability: .readOnly)
        XCTAssertFalse(readOnly.contains(.deleteEvent))
    }

    // MARK: - The coordinator

    func testEditingWritesWithTheChosenSpanAndOffersUndoForOneOccurrence() async {
        let editor = FakeEventEditor()
        let notices = NoticeCenter()
        let coordinator = makeCoordinator(editor: editor, notices: notices)

        _ = await coordinator.edit(event(), EventChange(title: "Retro"))?.value
        XCTAssertEqual(editor.updates.map(\.change.title), ["Retro"])
        XCTAssertEqual(editor.updates.first?.span, .thisEvent)
        XCTAssertEqual(notices.currentNotice?.title, "Event updated")
        XCTAssertEqual(notices.currentNotice?.action?.title, "Undo")

        _ = await coordinator.edit(event(recurring: true), EventChange(start: start.addingTimeInterval(3600)), span: .futureEvents)?.value
        XCTAssertEqual(editor.updates.last?.span, .futureEvents)
        XCTAssertTrue(notices.currentNotice?.title.hasPrefix("Event moved to") == true)
        XCTAssertNil(notices.currentNotice?.action, "all future events: no Undo, like Calendar")
    }

    func testMeetingsAndInvitationsAreNeverEdited() async {
        let editor = FakeEventEditor()
        let coordinator = makeCoordinator(editor: editor, notices: NoticeCenter())
        XCTAssertNil(coordinator.edit(event(attendees: true), EventChange(title: "X")))
        XCTAssertNil(coordinator.edit(event(invitation: true), EventChange(title: "X")))
        XCTAssertTrue(editor.updates.isEmpty)
    }

    func testDeletingAnInvitationWorksWithoutUndo() async {
        let editor = FakeEventEditor()
        let notices = NoticeCenter()
        let coordinator = makeCoordinator(editor: editor, notices: notices)
        await coordinator.delete(event(invitationFrom: "Anna", invitation: true))?.value
        XCTAssertEqual(editor.deletes.count, 1)
        XCTAssertEqual(notices.currentNotice?.title, "Event deleted")
        XCTAssertNil(notices.currentNotice?.action, "someone else's meeting can't be put back")

        await coordinator.delete(event())?.value
        XCTAssertEqual(notices.currentNotice?.action?.title, "Undo", "a simple event can")
    }

    func testAlertsCanChangeOnInvitationsButNothingElse() async {
        let editor = FakeEventEditor()
        let notices = NoticeCenter()
        let coordinator = makeCoordinator(editor: editor, notices: notices)
        let invitation = event(invitationFrom: "Anna", invitation: true)
        XCTAssertTrue(EventEditability.of(invitation).canEditAlerts)
        XCTAssertFalse(EventEditability.readOnly.canEditAlerts)

        _ = await coordinator.edit(invitation, EventChange(alerts: [.before(minutes: 10)]))?.value
        XCTAssertEqual(editor.updates.map(\.change.alerts), [[.before(minutes: 10)]])
        XCTAssertEqual(notices.currentNotice?.title, "Alert changed")
        XCTAssertNil(coordinator.edit(invitation, EventChange(title: "Mine now", alerts: [])), "an alert plus anything else is refused")
    }

    func testANewRepeatRuleHasNoUndo() async {
        let editor = FakeEventEditor()
        let notices = NoticeCenter()
        let coordinator = makeCoordinator(editor: editor, notices: notices)
        _ = await coordinator.edit(event(), EventChange(recurrence: .weekly))?.value
        XCTAssertEqual(editor.updates.first?.change.recurrence, .weekly)
        XCTAssertEqual(notices.currentNotice?.title, "Repeat changed")
        XCTAssertNil(notices.currentNotice?.action)
    }

    func testAnExactRepeatRuleReachesTheEditorWithoutUndo() async {
        let editor = FakeEventEditor()
        let notices = NoticeCenter()
        let coordinator = makeCoordinator(editor: editor, notices: notices)
        let rule = TaskRecurrenceRule(frequency: .weekly, interval: 2, weekdays: [.init(weekday: 2), .init(weekday: 4)])
        _ = await coordinator.edit(event(), EventChange(recurrenceRule: rule))?.value
        XCTAssertEqual(editor.updates.first?.change.recurrenceRule, rule)
        XCTAssertEqual(notices.currentNotice?.title, "Repeat changed")
        XCTAssertNil(notices.currentNotice?.action)
        XCTAssertFalse(EventChange(recurrenceRule: rule).isAlertsOnly)
    }

    func testAlertTitlesReadLikeCalendar() {
        XCTAssertEqual(EventAlert.before(minutes: 0).title(isAllDay: false), "At time of event")
        XCTAssertEqual(EventAlert.before(minutes: 15).title(isAllDay: false), "15 minutes before")
        XCTAssertEqual(EventAlert.before(minutes: 60).title(isAllDay: false), "1 hour before")
        XCTAssertEqual(EventAlert.before(minutes: 2880).title(isAllDay: false), "2 days before")
        XCTAssertEqual(EventAlert.before(minutes: 10080).title(isAllDay: false), "1 week before")
        XCTAssertEqual(EventAlert.before(minutes: -5).title(isAllDay: false), "5 minutes after")
        XCTAssertEqual(EventAlert.before(minutes: -540).title(isAllDay: true), "On day of event (09:00)")
        XCTAssertEqual(EventAlert.before(minutes: 900).title(isAllDay: true), "1 day before (09:00)")
        XCTAssertEqual(EventAlert.before(minutes: 9540).title(isAllDay: true), "1 week before (09:00)")
        XCTAssertEqual(EventAlert.before(minutes: 900).title(isAllDay: true, format: .twelveHour), "1 day before (9:00am)")
        XCTAssertEqual(EventAlert.presets(isAllDay: true).count, 4)
        XCTAssertTrue(EventChange(alerts: []).isAlertsOnly)
        XCTAssertFalse(EventChange(title: "X", alerts: []).isAlertsOnly)
    }

    func testDeletingAsksOnlyWhenItCantBeUndone() async {
        let editor = FakeEventEditor()
        let notices = NoticeCenter()
        let decisions = DecisionCenter()
        let coordinator = makeCoordinator(editor: editor, notices: notices, decisions: decisions)

        // Own single event: gone at once, Undo in the notice, nothing asked.
        coordinator.requestDeletion(of: event())
        XCTAssertNil(decisions.current)
        XCTAssertFalse(coordinator.deletionAsks(event()))

        // An invitation can't be put back: a destructive card, ↩ on Cancel.
        coordinator.requestDeletion(of: event(invitationFrom: "Anna", invitation: true))
        XCTAssertEqual(decisions.current?.kind, .destructive)
        XCTAssertEqual(decisions.current?.message, "Anna won't be notified. To decline, respond in Apple Calendar.")
        XCTAssertEqual(decisions.current?.defaultAction?.role, .cancel, "↩ never deletes by accident")
        decisions.cancel()
        XCTAssertNil(decisions.current)

        // A repeating event asks which: Cancel · [Delete This Event ▾ This & Future].
        coordinator.requestDeletion(of: event(recurring: true))
        XCTAssertEqual(decisions.current?.actions.map(\.title), ["Cancel", "Delete This Event"])
        let future = try! XCTUnwrap(decisions.current?.actions[1].alternatives.first)
        XCTAssertEqual(future.title, "Delete This & Future Events")
        decisions.choose(future)
        try? await Task.sleep(for: .milliseconds(20))
        XCTAssertEqual(editor.deletes.last, .futureEvents)
    }

    func testARepeatingEventsChangeAsksWithThisEventAsTheDefault() async {
        let editor = FakeEventEditor()
        let decisions = DecisionCenter()
        let coordinator = makeCoordinator(editor: editor, notices: NoticeCenter(), decisions: decisions)
        var finished = false
        coordinator.editAskingSpan(event(recurring: true), EventChange(title: "Retro")) { saved in finished = !saved }
        XCTAssertEqual(decisions.current?.kind, .choice)
        XCTAssertEqual(decisions.current?.defaultAction?.title, "Change This Event", "the narrowest scope")
        XCTAssertFalse(finished)

        decisions.moveSelection(-1)
        XCTAssertEqual(decisions.current?.actions.first { $0.id == decisions.selectedID }?.title, "Cancel")
        decisions.cancel()
        XCTAssertTrue(finished, "cancelling finishes, unsaved (a resize preview goes back)")
        XCTAssertTrue(editor.updates.isEmpty)

        coordinator.editAskingSpan(event(), EventChange(title: "Retro"))
        XCTAssertNil(decisions.current, "a single event doesn't ask")
    }

    func testAcceptingReportsSavedSoADragStaysWhereItWasDropped() async throws {
        let editor = FakeEventEditor()
        let decisions = DecisionCenter()
        let coordinator = makeCoordinator(editor: editor, notices: NoticeCenter(), decisions: decisions)
        var result: Bool?
        coordinator.editAskingSpan(event(recurring: true), EventChange(start: start.addingTimeInterval(3600))) { result = $0 }
        XCTAssertNil(result, "while asking, nothing is decided — the preview stays")
        decisions.choose(try XCTUnwrap(decisions.current?.actions.last))
        for _ in 0..<50 where result == nil { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertEqual(result, true, "saved: the block stays at its new time")
        XCTAssertEqual(editor.updates.last?.span, .thisEvent)
    }

    func testANewDecisionReplacesAnUnansweredOne() {
        let decisions = DecisionCenter()
        var cancelled = 0
        func request(_ title: String) -> DecisionRequest {
            DecisionRequest(kind: .choice, title: title, actions: [DecisionAction(title: "Cancel", role: .cancel) { cancelled += 1 }])
        }
        decisions.present(request("One"))
        decisions.present(request("Two"))
        XCTAssertEqual(decisions.current?.title, "Two", "never stacked")
        XCTAssertEqual(cancelled, 1, "the first counts as cancelled")
    }

    func testUndoingANewRepeatingEventRemovesTheWholeSeries() async throws {
        let editor = FakeEventEditor()
        let notices = NoticeCenter()
        let coordinator = makeCoordinator(editor: editor, notices: notices)
        let start = Date(timeIntervalSince1970: 2_000_000_000)
        _ = try await coordinator.create(EventDraft(title: "Standup", start: start, end: start.addingTimeInterval(900),
                                                    recurrenceRule: TaskRecurrenceRule(frequency: .daily)))
        notices.currentNotice?.action?.handler()
        await settle { !editor.deletes.isEmpty }
        XCTAssertEqual(editor.deletes, [.futureEvents], "the series, not just its first occurrence")

        _ = try await coordinator.create(EventDraft(title: "Lunch", start: start, end: start.addingTimeInterval(3600)))
        notices.currentNotice?.action?.handler()
        await settle { editor.deletes.count == 2 }
        XCTAssertEqual(editor.deletes.last, .thisEvent)
    }

    func testAFailedUndoOfANewEventIsSaid() async throws {
        let editor = FakeEventEditor()
        editor.deleteFailure = EventEditError.notFound
        let notices = NoticeCenter()
        let coordinator = makeCoordinator(editor: editor, notices: notices)
        let start = Date(timeIntervalSince1970: 2_000_000_000)
        _ = try await coordinator.create(EventDraft(title: "Lunch", start: start, end: start.addingTimeInterval(3600)))
        notices.currentNotice?.action?.handler()
        await settle { notices.currentNotice?.title == "Couldn’t undo" }
        XCTAssertEqual(notices.currentNotice?.title, "Couldn’t undo")
    }

    /// Lets the Undo's task run.
    private func settle(until done: () -> Bool) async {
        for _ in 0..<200 where !done() { await Task.yield() }
    }

    func testWithoutAnEditorEverythingIsReadOnly() {
        let coordinator = makeCoordinator(editor: nil, notices: NoticeCenter())
        XCTAssertEqual(coordinator.editability(of: event()), .readOnly)
    }

    private func makeCoordinator(editor: FakeEventEditor?, notices: NoticeCenter,
                                 decisions: DecisionCenter? = nil) -> EventActionCoordinator {
        EventActionCoordinator(
            appleCalendar: NoCalendarOpener(), removalService: NoRemoval(),
            occurrenceFinder: NoOccurrences(), noticeCenter: notices,
            reminderSuppression: ReminderSuppressionStore(defaults: UserDefaults(suiteName: "EventEditingTests.\(UUID())")!),
            editor: editor, decisions: decisions ?? DecisionCenter(),
            onNavigateOccurrence: { _ in }
        )
    }
}

@MainActor
private final class FakeEventEditor: CalendarEventEditing {
    var updates: [(change: EventChange, span: EventSpan)] = []
    var deletes: [EventSpan] = []
    var deleteFailure: Error?

    func writableCalendars() async -> [WritableCalendar] { [] }

    func create(_ draft: EventDraft) async throws -> EventSnapshot {
        snapshot(hasAttendees: false, isRecurring: draft.recurrenceRule != nil)
    }

    func update(_ target: EventEditReference, _ change: EventChange, span: EventSpan) async throws -> (before: EventSnapshot, after: EventSnapshot) {
        updates.append((change, span))
        return (snapshot(hasAttendees: false), snapshot(hasAttendees: false))
    }

    func delete(_ target: EventEditReference, span: EventSpan) async throws -> EventSnapshot {
        if let deleteFailure { throw deleteFailure }
        deletes.append(span)
        return snapshot(hasAttendees: target.hasAttendees)
    }

    private func snapshot(hasAttendees: Bool, isRecurring: Bool = false) -> EventSnapshot {
        EventSnapshot(eventIdentifier: "ek", calendarIdentifier: "cal", calendarTitle: "Work", title: "Review",
                      start: Date(timeIntervalSince1970: 2_000_000_000), end: Date(timeIntervalSince1970: 2_000_003_600),
                      isAllDay: false, location: nil, notes: nil, hasAttendees: hasAttendees, isRecurring: isRecurring)
    }
}

private struct NoCalendarOpener: AppleCalendarOpening {
    func openWithDetails(calendarItemIdentifier: String, occurrenceDate: Date) -> Bool { true }
}

private final class NoRemoval: CalendarEventRemoving {
    func removeCancelledOccurrence(_ reference: EventRemovalReference) throws {}
}

private actor NoOccurrences: RecurringOccurrenceFinding {
    func adjacent(to reference: RecurringSeriesReference, direction: OccurrenceDirection) async -> OccurrenceNavigationTarget? { nil }
}

final class TimelineResizeTests: XCTestCase {
    func testEdgesSnapToQuarterHoursAndStayValid() {
        // 10:07–11:00, bottom dragged down 20 min → 11:15 (11:20 snaps to 11:15).
        XCTAssertEqual(TimelineResize.resized(start: 607, end: 660, edge: .bottom, deltaMinutes: 20).end, 675)
        // Top dragged up 31 min from 10:00 → 9:30.
        XCTAssertEqual(TimelineResize.resized(start: 600, end: 660, edge: .top, deltaMinutes: -31).start, 570)
        // Never shorter than 15 minutes, either way.
        XCTAssertEqual(TimelineResize.resized(start: 600, end: 660, edge: .top, deltaMinutes: 300).start, 645)
        XCTAssertEqual(TimelineResize.resized(start: 600, end: 660, edge: .bottom, deltaMinutes: -300).end, 615)
        // Never off the day.
        XCTAssertEqual(TimelineResize.resized(start: 30, end: 90, edge: .top, deltaMinutes: -120).start, 0)
        XCTAssertEqual(TimelineResize.resized(start: 1380, end: 1410, edge: .bottom, deltaMinutes: 120).end, 1440)
        // The other edge never moves.
        XCTAssertEqual(TimelineResize.resized(start: 600, end: 660, edge: .bottom, deltaMinutes: 40).start, 600)
    }
}

extension TimelineResizeTests {
    func testMovingKeepsTheLengthSnapsAndStaysInTheDay() {
        let moved = TimelineResize.resized(start: 600, end: 645, edge: .body, deltaMinutes: 52)
        XCTAssertEqual(moved.start, 645, "10:00 + 52 min snaps to 10:45")
        XCTAssertEqual(moved.end - moved.start, 45, "same length")
        XCTAssertEqual(TimelineResize.resized(start: 60, end: 120, edge: .body, deltaMinutes: -300).start, 0)
        XCTAssertEqual(TimelineResize.resized(start: 1320, end: 1410, edge: .body, deltaMinutes: 300).end, 1440)
    }
}

extension EventEditingTests {
    func testARepeatedRequestWhileSavingIsIgnored() async {
        let editor = FakeEventEditor()
        let notices = NoticeCenter()
        let coordinator = EventActionCoordinator(
            appleCalendar: NoCalendarOpener(), removalService: NoRemoval(),
            occurrenceFinder: NoOccurrences(), noticeCenter: notices,
            reminderSuppression: ReminderSuppressionStore(defaults: UserDefaults(suiteName: "EventEditingTests.\(UUID())")!),
            editor: editor, decisions: DecisionCenter(),
            onNavigateOccurrence: { _ in }
        )
        let event = AgendaEventModel(
            id: "e", startTime: "10:00", endTime: "11:00",
            startDate: Date(timeIntervalSince1970: 2_000_000_000), endDate: Date(timeIntervalSince1970: 2_000_003_600),
            title: "Review",
            editReference: EventEditReference(eventIdentifier: "ek", calendarIdentifier: "cal",
                                              occurrenceStart: Date(timeIntervalSince1970: 2_000_000_000),
                                              occurrenceEnd: Date(timeIntervalSince1970: 2_000_003_600),
                                              isWritable: true, invitationFrom: nil, isInvitation: false)
        )
        let move = EventChange(start: Date(timeIntervalSince1970: 2_000_086_400))
        let first = coordinator.edit(event, move)
        let second = coordinator.edit(event, move)
        XCTAssertNotNil(first)
        XCTAssertNil(second, "the same occurrence is already being saved")
        _ = await first?.value
        XCTAssertEqual(editor.updates.count, 1)
    }
}

final class SeriesIdentifierTests: XCTestCase {
    func testAnOccurrencesRecurrenceSuffixIsNotPartOfItsSeries() {
        XCTAssertEqual(CalendarEventMapper.seriesIdentifier("DFC30B98-B0C6/RID=812636100"), "DFC30B98-B0C6")
        XCTAssertEqual(CalendarEventMapper.seriesIdentifier("DFC30B98-B0C6"), "DFC30B98-B0C6")
    }
}
