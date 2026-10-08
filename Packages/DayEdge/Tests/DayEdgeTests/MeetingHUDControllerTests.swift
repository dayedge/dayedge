import EventKit
import XCTest
@testable import Shell
@testable import Domain
@testable import UI

@MainActor
final class MeetingHUDControllerTests: XCTestCase {
    /// A `class`, not a `struct`, and `sections` is mutable — lets tests
    /// simulate an event being edited (same id, different fields)
    /// between two `refresh()` calls on the *same* controller.
    private final class StubCalendarDataProvider: CalendarDataProviding {
        var sections: [AgendaDaySection]
        var isAuthorized = true
        init(sections: [AgendaDaySection]) { self.sections = sections }
        func days(for monthAnchor: Date, selectedDate: Date, calendar: Calendar) -> [DayCellModel] { [] }
        func agendaSections(in range: DateInterval, calendar: Calendar) async -> [AgendaDaySection] {
            sections.filter { $0.date >= range.start && $0.date <= range.end }
        }
        func events(for date: Date, calendar: Calendar) -> [AgendaEventModel] { [] }
    }

    private final class FakePresenter: MeetingHUDPresenting {
        private(set) var shownOccurrences: [MeetingHUDOccurrence] = []
        private(set) var shownDisplays: [MeetingHUDDisplay] = []
        private(set) var hideCount = 0
        private(set) var lastOnJoin: (() -> Void)?
        private(set) var lastOnSnoozeSmart: (() -> Void)?
        private(set) var lastOnSnoozeDuration: ((TimeInterval) -> Void)?
        private(set) var lastOnDismiss: (() -> Void)?

        func show(_ occurrence: MeetingHUDOccurrence, display: MeetingHUDDisplay, actions: MeetingHUDActions) {
            shownOccurrences.append(occurrence)
            shownDisplays.append(display)
            lastOnJoin = actions.join
            lastOnSnoozeSmart = actions.snoozeSmart
            lastOnSnoozeDuration = actions.snoozeDuration
            lastOnDismiss = actions.dismiss
        }
        func hide() { hideCount += 1 }
    }

    private final class TestClock {
        var current: Date
        init(_ date: Date) { current = date }
        func now() -> Date { current }
    }

    // `MeetingHUDController.refresh()` internally computes "today" via
    // `Calendar.autoupdatingCurrent` (matching `MenuBarStateController`'s
    // own convention — not injectable), so test dates must be built
    // against that same calendar/day, not a fixed UTC one, or the
    // stub provider's day-range filtering silently disagrees with the
    // controller's own notion of "today" depending on the machine's
    // local time zone.
    private var calendar: Calendar { .autoupdatingCurrent }

    private var today: Date { calendar.startOfDay(for: .now) }

    private func date(_ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(bySettingHour: hour, minute: minute, second: 0, of: today)!
    }

    private func section(_ events: [AgendaEventModel]) -> AgendaDaySection {
        AgendaDaySection(date: today, events: events)
    }

    private func event(
        _ id: String, start: Date, end: Date,
        status: EventStatus = .confirmed, notes: String? = nil,
        reminderKey: ReminderOccurrenceKey? = nil
    ) -> AgendaEventModel {
        AgendaEventModel(
            id: id, startTime: "x", endTime: "x", startDate: start, endDate: end,
            title: id, status: status, videoService: .zoom, tint: .orange,
            notes: notes, videoURL: "https://zoom.us/j/1",
            reminderOccurrenceKey: reminderKey
        )
    }

    /// Builds a controller wired to injectable fakes/stubs — no real
    /// `UserDefaults`/`EventKit`/window involved.
    private func makeController(
        sections: [AgendaDaySection], clock: TestClock, presenter: FakePresenter,
        configuration: MeetingHUDConfiguration = .default, soundPlays: @escaping () -> Void = {},
        reminderSuppression: ReminderSuppressionStore? = nil, provider: StubCalendarDataProvider? = nil
    ) -> MeetingHUDController {
        MeetingHUDController(
            dataProvider: provider ?? StubCalendarDataProvider(sections: sections),
            eventStore: EKEventStore(),
            presenterForStyle: { _ in presenter },
            now: clock.now,
            openURL: { _ in },
            playSound: soundPlays,
            configuration: { configuration }, reminderSuppression: reminderSuppression
        )
    }

    private func reminderKey(for start: Date) -> ReminderOccurrenceKey {
        ReminderOccurrenceKey.eventKit(
            calendarIdentifier: "work", isRecurring: true,
            seriesIdentifier: "daily", calendarItemIdentifier: "item",
            eventIdentifier: "event", startDate: start, occurrenceDate: start
        )!
    }

    func testMutingActiveOccurrenceHidesItAndRestoreUsesNormalRules() async {
        let clock = TestClock(date(9, 56))
        let suite = "MeetingHUDControllerTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let suppression = ReminderSuppressionStore(defaults: defaults, now: clock.now)
        let presenter = FakePresenter()
        var sounds = 0
        let meeting = event("Standup", start: date(10), end: date(10, 30),
                            reminderKey: reminderKey(for: date(10)))
        let controller = makeController(
            sections: [section([meeting])], clock: clock, presenter: presenter,
            soundPlays: { sounds += 1 }, reminderSuppression: suppression
        )
        suppression.onMutation = { [weak controller] key, muted in
            controller?.reminderSuppressionChanged(for: key, muted: muted)
        }

        controller.refresh()
        try? await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertEqual(presenter.shownOccurrences.count, 1)
        XCTAssertEqual(sounds, 1)

        suppression.setMuted(true, for: meeting)
        XCTAssertEqual(presenter.hideCount, 1)
        controller.refresh()
        try? await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertEqual(presenter.shownOccurrences.count, 1)
        XCTAssertEqual(sounds, 1)

        suppression.setMuted(false, for: meeting)
        try? await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertEqual(presenter.shownOccurrences.count, 2)
    }

    func testMuteCancelsPendingSnoozeAndDoesNotReappearAtWake() async {
        let clock = TestClock(date(9, 56))
        let suite = "MeetingHUDControllerTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let suppression = ReminderSuppressionStore(defaults: defaults, now: clock.now)
        let presenter = FakePresenter()
        let meeting = event("Standup", start: date(10), end: date(10, 30),
                            reminderKey: reminderKey(for: date(10)))
        let controller = makeController(
            sections: [section([meeting])], clock: clock, presenter: presenter,
            reminderSuppression: suppression
        )
        suppression.onMutation = { [weak controller] key, muted in
            controller?.reminderSuppressionChanged(for: key, muted: muted)
        }

        controller.refresh()
        try? await Task.sleep(nanoseconds: 300_000_000)
        presenter.lastOnSnoozeDuration?(60)
        suppression.setMuted(true, for: meeting)
        clock.current = date(9, 58)
        controller.refresh()
        try? await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertEqual(presenter.shownOccurrences.count, 1)
    }

    func testMutedCandidateDoesNotBlockAnotherEligibleMeeting() async {
        let clock = TestClock(date(9, 56))
        let suite = "MeetingHUDControllerTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let suppression = ReminderSuppressionStore(defaults: defaults, now: clock.now)
        let presenter = FakePresenter()
        let first = event("First", start: date(10), end: date(10, 30),
                          reminderKey: reminderKey(for: date(10)))
        let secondKey = ReminderOccurrenceKey.eventKit(
            calendarIdentifier: "work", isRecurring: false,
            seriesIdentifier: nil, calendarItemIdentifier: "second",
            eventIdentifier: "second", startDate: date(10), occurrenceDate: nil
        )!
        let second = event("Second", start: date(10), end: date(10, 30), reminderKey: secondKey)
        suppression.setMuted(true, for: first)
        let controller = makeController(
            sections: [section([first, second])], clock: clock, presenter: presenter,
            reminderSuppression: suppression
        )

        controller.refresh()
        try? await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertEqual(presenter.shownOccurrences.map(\.id), ["Second"])
    }

    func testShowsOnlyInsideLeadWindow() async {
        let clock = TestClock(date(9, 30))
        let presenter = FakePresenter()
        let meeting = event("Standup", start: date(10), end: date(10, 30))
        let controller = makeController(sections: [section([meeting])], clock: clock, presenter: presenter)

        controller.refresh()
        try? await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertTrue(presenter.shownOccurrences.isEmpty, "still 30 minutes out — outside the 5-minute default lead window")

        clock.current = date(9, 56)
        controller.refresh()
        try? await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertEqual(presenter.shownOccurrences.map(\.id), ["Standup"])
    }

    func testLosingCalendarAccessHidesTheHUD() async {
        let clock = TestClock(date(9, 56))
        let presenter = FakePresenter()
        let provider = StubCalendarDataProvider(sections: [section([event("Standup", start: date(10), end: date(10, 30))])])
        let controller = makeController(sections: [], clock: clock, presenter: presenter, provider: provider)
        controller.refresh()
        try? await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertEqual(presenter.shownOccurrences.map(\.id), ["Standup"])

        provider.isAuthorized = false
        controller.refresh()
        try? await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertEqual(presenter.hideCount, 1)
        XCTAssertEqual(presenter.shownOccurrences.count, 1, "not shown again without access")
    }

    func testSameOccurrenceShowingAgainDoesNotResound() async {
        let clock = TestClock(date(9, 56))
        let presenter = FakePresenter()
        var soundCount = 0
        let meeting = event("Standup", start: date(10), end: date(10, 30))
        let controller = makeController(sections: [section([meeting])], clock: clock, presenter: presenter, soundPlays: { soundCount += 1 })

        controller.refresh()
        try? await Task.sleep(nanoseconds: 300_000_000)
        controller.refresh()
        try? await Task.sleep(nanoseconds: 300_000_000)

        XCTAssertEqual(soundCount, 1)
    }

    func testChangedContentSameIDUpdatesPresenterWithoutResounding() async {
        let clock = TestClock(date(9, 56))
        let presenter = FakePresenter()
        var soundCount = 0
        let original = event("Standup", start: date(10), end: date(10, 30))
        let provider = StubCalendarDataProvider(sections: [section([original])])
        let controller = MeetingHUDController(
            dataProvider: provider, eventStore: EKEventStore(),
            presenterForStyle: { _ in presenter }, now: clock.now, openURL: { _ in },
            playSound: { soundCount += 1 }, configuration: { .default }
        )

        controller.refresh()
        try? await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertEqual(presenter.shownOccurrences.count, 1)
        XCTAssertEqual(presenter.shownOccurrences.last?.end, date(10, 30))

        // Same event id (same start time), edited end time — the id
        // (`eventIdentifier-startTime`) stays the same, so without the
        // full-value comparison this would be silently ignored.
        let edited = event("Standup", start: date(10), end: date(11))
        provider.sections = [section([edited])]
        controller.refresh()
        try? await Task.sleep(nanoseconds: 300_000_000)

        XCTAssertEqual(presenter.shownOccurrences.count, 2, "content change (same id) should still call show() again")
        XCTAssertEqual(presenter.shownOccurrences.last?.end, date(11))
        XCTAssertEqual(soundCount, 1, "same occurrence id — the content-only update should not re-sound")
    }

    func testChangedDetailMetadataSameIDUpdatesPresenter() async {
        let clock = TestClock(date(9, 56))
        let presenter = FakePresenter()
        let original = event(
            "Standup", start: date(10), end: date(10, 30), notes: "Original notes"
        )
        let provider = StubCalendarDataProvider(sections: [section([original])])
        let controller = MeetingHUDController(
            dataProvider: provider, eventStore: EKEventStore(),
            presenterForStyle: { _ in presenter }, now: clock.now,
            openURL: { _ in }, playSound: {}, configuration: { .default }
        )

        controller.refresh()
        try? await Task.sleep(nanoseconds: 300_000_000)

        let edited = event(
            "Standup", start: date(10), end: date(10, 30), notes: "Updated notes"
        )
        provider.sections = [section([edited])]
        controller.refresh()
        try? await Task.sleep(nanoseconds: 300_000_000)

        XCTAssertEqual(presenter.shownOccurrences.count, 2)
        XCTAssertEqual(presenter.shownOccurrences.last?.event.notes, "Updated notes")
    }

    func testOverflowSnoozeDurationHidesAndReappearsAtExactDeadline() async {
        let clock = TestClock(date(9, 56))
        let presenter = FakePresenter()
        let meeting = event("Standup", start: date(10), end: date(10, 30))
        let controller = makeController(sections: [section([meeting])], clock: clock, presenter: presenter)

        controller.refresh()
        try? await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertEqual(presenter.shownOccurrences.count, 1)

        presenter.lastOnSnoozeDuration?(60)
        XCTAssertEqual(presenter.hideCount, 1)

        // Past the snooze deadline (60s) but nowhere near the next
        // minute-aligned tick — a plain minute timer alone would still
        // be ~13 minutes from firing here, so this specifically exercises
        // the exact-deadline logic (`refresh()` recognizing the snooze
        // has expired), not the real background `Timer`'s own firing.
        clock.current = date(9, 57)
        controller.refresh()
        try? await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertEqual(presenter.shownOccurrences.count, 2, "past the snooze deadline — should reappear")
    }

    func testSmartSnoozeBeforeStartWakesExactlyAtMeetingStart() async {
        let clock = TestClock(date(9, 56))
        let presenter = FakePresenter()
        let meeting = event("Standup", start: date(10), end: date(10, 30))
        let controller = makeController(sections: [section([meeting])], clock: clock, presenter: presenter)

        controller.refresh()
        try? await Task.sleep(nanoseconds: 300_000_000)
        presenter.lastOnSnoozeSmart?()
        XCTAssertEqual(presenter.hideCount, 1)

        // One minute before the actual meeting start — a "5 minutes from
        // now" snooze would already have expired by here, but "until
        // meeting start" must not have.
        clock.current = date(9, 59)
        controller.refresh()
        try? await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertEqual(presenter.shownOccurrences.count, 1, "must stay hidden until the exact start time, not merely 'soon'")

        clock.current = date(10)
        controller.refresh()
        try? await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertEqual(presenter.shownOccurrences.count, 2, "reappears exactly at meeting start")
    }

    func testSmartReminderAfterStartUsesOneMinuteDefault() async {
        // "now" already past the meeting's start.
        let clock = TestClock(date(10, 2))
        let presenter = FakePresenter()
        let meeting = event("Standup", start: date(10), end: date(10, 30))
        let controller = makeController(sections: [section([meeting])], clock: clock, presenter: presenter)

        controller.refresh()
        try? await Task.sleep(nanoseconds: 300_000_000)
        presenter.lastOnSnoozeSmart?()
        XCTAssertEqual(presenter.hideCount, 1)

        clock.current = date(10, 2).addingTimeInterval(30)
        controller.refresh()
        try? await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertTrue(presenter.shownOccurrences.count < 2, "the one-minute reminder has not elapsed yet")

        clock.current = date(10, 3)
        controller.refresh()
        try? await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertEqual(presenter.shownOccurrences.count, 2, "one minute after reminding — reappears")
    }

    func testDismissNeverReappearsForThatOccurrence() async {
        let clock = TestClock(date(9, 56))
        let presenter = FakePresenter()
        let meeting = event("Standup", start: date(10), end: date(10, 30))
        let controller = makeController(sections: [section([meeting])], clock: clock, presenter: presenter)

        controller.refresh()
        try? await Task.sleep(nanoseconds: 300_000_000)
        presenter.lastOnDismiss?()
        XCTAssertEqual(presenter.hideCount, 1)

        controller.refresh()
        try? await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertEqual(presenter.shownOccurrences.count, 1, "dismissed — should not show again")
    }

    /// Regression test for a real production bug: with a
    /// `presenterForStyle` factory that returns a *fresh* instance per
    /// call (exactly what the real default, `{ _ in MeetingHUDWindowController() }`,
    /// does), `dismiss()`/`join()`/`hideIfShown()` must still land their
    /// `.hide()` on the *same* presenter instance `apply()`'s `.show()`
    /// used — not a brand-new, never-shown one whose `hide()` is a no-op.
    /// A naive `presenterForStyle(style).hide()` at each call site fails
    /// this; only caching the presenter per style fixes it.
    func testDismissHidesTheSamePresenterInstanceThatWasShown() async {
        let clock = TestClock(date(9, 56))
        var createdPresenters: [FakePresenter] = []
        let meeting = event("Standup", start: date(10), end: date(10, 30))
        let controller = MeetingHUDController(
            dataProvider: StubCalendarDataProvider(sections: [section([meeting])]), eventStore: EKEventStore(),
            presenterForStyle: { _ in
                let presenter = FakePresenter()
                createdPresenters.append(presenter)
                return presenter
            },
            now: clock.now, openURL: { _ in }, playSound: {}, configuration: { .default }
        )

        controller.refresh()
        try? await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertEqual(createdPresenters.count, 1, "one presenter created for show()")
        createdPresenters[0].lastOnDismiss?()

        XCTAssertEqual(createdPresenters.count, 1, "dismiss() must not create a second, throwaway presenter")
        XCTAssertEqual(createdPresenters[0].hideCount, 1, "hide() must land on the instance that actually shown the HUD")
    }

    func testJoinPermanentlySuppressesTheOccurrence() async {
        let clock = TestClock(date(9, 56))
        let presenter = FakePresenter()
        let meeting = event("Standup", start: date(10), end: date(10, 30))
        let controller = makeController(sections: [section([meeting])], clock: clock, presenter: presenter)

        controller.refresh()
        try? await Task.sleep(nanoseconds: 300_000_000)
        presenter.lastOnJoin?()
        XCTAssertEqual(presenter.hideCount, 1)

        // The meeting is still ongoing — a plain "hide" (like snooze)
        // would let it resurface on the next scan; Join must not.
        clock.current = date(10, 5)
        controller.refresh()
        try? await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertEqual(presenter.shownOccurrences.count, 1, "joined — must never resurface for this occurrence again")
    }

    func testCancellationHidesTheHUD() async {
        let clock = TestClock(date(9, 56))
        let presenter = FakePresenter()
        let meeting = event("Standup", start: date(10), end: date(10, 30))
        let provider = StubCalendarDataProvider(sections: [section([meeting])])
        let controller = MeetingHUDController(
            dataProvider: provider, eventStore: EKEventStore(),
            presenterForStyle: { _ in presenter }, now: clock.now, openURL: { _ in }, playSound: {}, configuration: { .default }
        )
        controller.refresh()
        try? await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertEqual(presenter.shownOccurrences.count, 1)

        // Same controller — the organizer cancels the event between two
        // refreshes, so `currentlyShown` correctly has something to hide.
        let cancelled = event("Standup", start: date(10), end: date(10, 30), status: .cancelled)
        provider.sections = [section([cancelled])]
        controller.refresh()
        try? await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertEqual(presenter.hideCount, 1)
    }

    func testBackToBackMeetingsHandOffOnce() async {
        let clock = TestClock(date(10, 30))
        let presenter = FakePresenter()
        let first = event("First", start: date(10), end: date(11))
        let second = event("Second", start: date(10, 30), end: date(11, 30))
        let controller = makeController(sections: [section([first, second])], clock: clock, presenter: presenter)

        controller.refresh()
        try? await Task.sleep(nanoseconds: 300_000_000)

        XCTAssertEqual(presenter.shownOccurrences.map(\.id), ["Second"], "only the current slot's occurrence shown, never both")
    }

    func testDisablingSettingImmediatelyHidesActiveHUD() async {
        let clock = TestClock(date(9, 56))
        let presenter = FakePresenter()
        let meeting = event("Standup", start: date(10), end: date(10, 30))
        var configuration = MeetingHUDConfiguration.default
        let stubProvider = StubCalendarDataProvider(sections: [section([meeting])])
        var currentConfiguration = configuration
        let controller = MeetingHUDController(
            dataProvider: stubProvider, eventStore: EKEventStore(),
            presenterForStyle: { _ in presenter }, now: clock.now, openURL: { _ in }, playSound: {},
            configuration: { currentConfiguration }
        )

        controller.refresh()
        try? await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertEqual(presenter.shownOccurrences.count, 1)

        configuration.isEnabled = false
        currentConfiguration = configuration
        controller.refresh()
        try? await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertEqual(presenter.hideCount, 1)
    }

    func testPreviewDoesNotTouchProductionDismissedOrSnoozedState() async {
        let clock = TestClock(date(9, 56))
        let presenter = FakePresenter()
        let meeting = event("Standup", start: date(10), end: date(10, 30))
        let controller = makeController(sections: [section([meeting])], clock: clock, presenter: presenter)

        controller.showPreview()
        XCTAssertEqual(presenter.shownOccurrences.map(\.id), ["preview"])

        // The real occurrence still shows normally afterward — preview
        // didn't mark anything as dismissed/snoozed/currently-shown.
        controller.refresh()
        try? await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertTrue(presenter.shownOccurrences.contains(where: { $0.id == "Standup" }))
    }

    func testChangingStyleHidesOldPresenterAndDoesNotReplaySound() async {
        let clock = TestClock(date(9, 56))
        let compact = FakePresenter()
        let fullScreen = FakePresenter()
        let meeting = event("Standup", start: date(10), end: date(10, 30))
        var settings = MeetingHUDConfiguration.default
        var soundCount = 0
        let controller = MeetingHUDController(
            dataProvider: StubCalendarDataProvider(sections: [section([meeting])]),
            eventStore: EKEventStore(),
            presenterForStyle: { $0 == .compact ? compact : fullScreen },
            now: clock.now, openURL: { _ in }, playSound: { soundCount += 1 },
            configuration: { settings }
        )

        controller.refresh()
        try? await Task.sleep(nanoseconds: 300_000_000)
        settings.style = .fullScreen
        controller.refresh()
        try? await Task.sleep(nanoseconds: 300_000_000)

        XCTAssertEqual(compact.hideCount, 1)
        XCTAssertEqual(fullScreen.shownOccurrences.map(\.id), ["Standup"])
        XCTAssertEqual(soundCount, 1)

        settings.isEnabled = false
        controller.refresh()
        XCTAssertEqual(fullScreen.hideCount, 1, "disable must hide the presenter that actually owns the window")
    }

    func testChangingDisplayReconfiguresSameOccurrence() async {
        let clock = TestClock(date(9, 56))
        let presenter = FakePresenter()
        let meeting = event("Standup", start: date(10), end: date(10, 30))
        var settings = MeetingHUDConfiguration.default
        let controller = MeetingHUDController(
            dataProvider: StubCalendarDataProvider(sections: [section([meeting])]),
            eventStore: EKEventStore(), presenterForStyle: { _ in presenter },
            now: clock.now, openURL: { _ in }, playSound: {}, configuration: { settings }
        )

        controller.refresh()
        try? await Task.sleep(nanoseconds: 300_000_000)
        settings.display = .all
        controller.refresh()
        try? await Task.sleep(nanoseconds: 300_000_000)

        XCTAssertEqual(presenter.shownDisplays, [.active, .all])
    }
}
