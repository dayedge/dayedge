import Foundation
import Observation
import SwiftUI
import Domain
import UI

/// Owns view-mode selection and date/agenda navigation — split out of
/// `RootView` for the same reason `EventDetailCoordinator` was.
/// Constructed once, in the root view's `init`, holding direct references
/// to `viewModel`/`agendaStore`/`presentationCoordinator` (themselves also
/// constructed once and stored via `@State`, so they're stable across
/// re-renders) rather than being handed copies of their state — a class
/// captured that way stays valid to close over even though `init` itself
/// runs again on every `RootView` re-render. `onWillChangeDate`
/// exists for the same reason: it lets this coordinator notify
/// `EventDetailCoordinator` (constructed first, then captured by this
/// closure) without ever needing to hold a direct reference to that type.
@MainActor
@Observable
package final class AgendaNavigationCoordinator {
    private let viewModel: CalendarViewModel
    private let agendaStore: AgendaSectionStore
    private let presentationCoordinator: any PanelRevealing
    private let onWillChangeDate: () -> Void

    /// The mode the tab control shows as selected — updates immediately on
    /// tap, independent of whether Month has actually finished revealing
    /// (see `displayedViewMode`).
    package private(set) var selectedViewMode: ViewMode = .month
    /// The mode actually on screen. Month and Day are both permanently
    /// mounted — switching between them just toggles which one is
    /// opaque/hit-testable, so neither ever re-mounts (and neither
    /// re-plays its initial scroll-to-selection animation) on a round trip.
    package private(set) var displayedViewMode: ViewMode = .month
    /// The day (and, one day, event) the Month agenda should be scrolled
    /// to. Each navigation source routes explicitly through `selectDate`,
    /// while manual agenda scrolling intentionally updates selection only.
    /// Requests still run while Month is hidden, preparing its position in
    /// the background while Day is showing.
    package private(set) var requestedMonthAgendaDate: AgendaScrollTarget?
    /// The target `AgendaListView` last actually finished scrolling to
    /// (see its `onScrollPrepared`). Revealing Month is deferred until
    /// this catches up with `requestedMonthAgendaDate` — normally
    /// instantaneous, since preparation runs continuously in the
    /// background while Day is showing.
    package private(set) var preparedMonthAgendaDate: AgendaScrollTarget?
    package private(set) var agendaNowPresentation: AgendaNowPresentation?
    /// Timed tasks due on a day. They can end a "Free until" gap; supplied
    /// by the root so this type stays unaware of where tasks come from.
    @ObservationIgnored package var timedTasks: (Date) -> [TaskItem] = { _ in [] }

    private var todayPositioningTask: Task<Void, Never>?
    private var todayPositioningGeneration = UUID()

    package init(viewModel: CalendarViewModel,
                 agendaStore: AgendaSectionStore,
                 presentationCoordinator: any PanelRevealing,
                 onWillChangeDate: @escaping () -> Void) {
        self.viewModel = viewModel
        self.agendaStore = agendaStore
        self.presentationCoordinator = presentationCoordinator
        self.onWillChangeDate = onWillChangeDate
    }

    /// Shared by the switcher's tap handler and `ViewModeShortcutMonitor`'s
    /// ⌘1/⌘2/⌘3 (see `KeyboardCommands`), so both routes to a mode agree
    /// on what "select it" means — in particular, Month is revealed only
    /// once prepared, never unconditionally.
    package func selectViewMode(_ mode: ViewMode) {
        selectedViewMode = mode
        switch mode {
        case .month:
            revealMonthIfPrepared()
        case .day, .tasks, .ask:
            displayedViewMode = mode
        }
    }

    /// Reveals Month only once its agenda has actually finished scrolling
    /// to the current selection — normally already true by the time the
    /// user switches back, since preparation runs continuously in the
    /// background while Day is showing (see `requestedMonthAgendaDate`).
    /// If it isn't (rapid Day navigation immediately followed by
    /// switching tabs), Day just stays on screen a beat longer rather than
    /// flashing Month at a stale position — `AgendaListView`'s
    /// `onScrollPrepared` calls this again once it catches up.
    package func revealMonthIfPrepared() {
        guard preparedMonthAgendaDate == requestedMonthAgendaDate else { return }
        displayedViewMode = .month
    }

    package func scrollPrepared(target: AgendaScrollTarget) {
        preparedMonthAgendaDate = target
        if selectedViewMode == .month {
            revealMonthIfPrepared()
        }
        positioningCompleted(for: target, from: .month)
    }

    package func dayPositioned() {
        guard let target = requestedMonthAgendaDate else { return }
        positioningCompleted(for: target, from: .day)
    }

    /// Tells `presentationCoordinator` that `target`'s positioning has
    /// actually taken effect in `mode`'s column — the signal
    /// `AppDelegate` waits for before revealing the popover window at
    /// all, so a menu-bar click's "jump to today" never happens visibly.
    /// Both columns stay permanently mounted and both react to the same
    /// `requestedMonthAgendaDate`, so both eventually report in — only the
    /// one matching `displayedViewMode` (i.e. what the user will actually
    /// see) is allowed to count, since the other is just background prep.
    private func positioningCompleted(for target: AgendaScrollTarget, from mode: ViewMode) {
        guard let openRequestID = presentationCoordinator.openRequestID,
              target == requestedMonthAgendaDate,
              displayedViewMode == mode || displayedViewMode == .tasks || displayedViewMode == .ask else { return }
        presentationCoordinator.markReady(openRequestID)
    }

    /// Centralizes selection routing so each source explicitly decides
    /// whether Month's agenda needs a programmatic scroll. In particular,
    /// manual agenda scrolling updates the circle without echoing a target
    /// back into the same scroll view.
    package func selectDate(_ date: Date, preparingMonthAgenda: Bool) {
        todayPositioningTask?.cancel()
        onWillChangeDate()
        viewModel.select(date: date)
        if preparingMonthAgenda {
            requestedMonthAgendaDate = AgendaScrollTarget(date: date)
        }
    }

    /// The event menu's recurrence jump uses the same target-based agenda
    /// navigation as a date click, with an event anchor for Month and Day.
    package func navigateToOccurrence(_ occurrence: OccurrenceNavigationTarget) async {
        await agendaStore.ensureLoaded(covering: occurrence.startDate)
        guard !Task.isCancelled else { return }
        todayPositioningTask?.cancel()
        onWillChangeDate()
        viewModel.select(date: occurrence.startDate)
        requestedMonthAgendaDate = AgendaScrollTarget(
            date: occurrence.startDate,
            eventID: occurrence.eventID,
            animated: true
        )
    }

    /// A task's occurrence (occurrence navigation, "Show in Calendar"): the
    /// same target-based navigation as an event occurrence, with a task
    /// anchor, so Month and Day both land on it.
    package func navigateToTask(_ taskID: String, on day: Date) async {
        await agendaStore.ensureLoaded(covering: day)
        guard !Task.isCancelled else { return }
        todayPositioningTask?.cancel()
        onWillChangeDate()
        viewModel.select(date: day)
        requestedMonthAgendaDate = AgendaScrollTarget(date: day, taskID: taskID, animated: true)
    }

    package func moveSelectedDay(by offset: Int) {
        let calendar = Calendar.autoupdatingCurrent
        guard let date = calendar.date(byAdding: .day, value: offset, to: viewModel.selectedDate) else { return }
        selectDate(date, preparingMonthAgenda: true)
    }

    package func goToToday() {
        requestTodayNow(at: .now, animated: true)
    }

    package func requestTodayNow(at now: Date, animated: Bool) {
        todayPositioningTask?.cancel()
        let generation = UUID()
        todayPositioningGeneration = generation
        todayPositioningTask = Task { @MainActor in
            let calendar = Calendar.autoupdatingCurrent
            let today = calendar.startOfDay(for: now)
            await agendaStore.ensureLoaded(covering: today)
            guard !Task.isCancelled, todayPositioningGeneration == generation else { return }

            let events = agendaStore.events(onDate: today)
            let evaluationNow = agendaEvaluationDate(actualNow: now, day: today, events: events, calendar: calendar)
            let target = preferredNowTarget(
                on: today,
                events: events,
                timedTasks: timedTasks(today),
                now: evaluationNow,
                calendar: calendar
            )
            onWillChangeDate()
            viewModel.select(date: today)
            let minute = calendar.dateInterval(of: .minute, for: evaluationNow)?.start ?? evaluationNow
            agendaNowPresentation = AgendaNowPresentation(day: today, minute: minute, target: target)
            requestedMonthAgendaDate = AgendaScrollTarget(
                date: today,
                nowTarget: target,
                animated: animated
            )
        }
    }

    package func refreshNowPresentation(at now: Date) {
        guard let current = agendaNowPresentation else { return }
        let calendar = Calendar.autoupdatingCurrent
        let events = agendaStore.events(onDate: current.day)
        let evaluationNow = agendaEvaluationDate(
            actualNow: now,
            day: current.day,
            events: events,
            calendar: calendar
        )
        let minute = calendar.dateInterval(of: .minute, for: evaluationNow)?.start ?? evaluationNow
        let target = preferredNowTarget(
            on: current.day,
            events: events,
            timedTasks: timedTasks(current.day),
            now: minute,
            calendar: calendar
        )
        let updated = AgendaNowPresentation(day: current.day, minute: minute, target: target)

        if target == current.target {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) { agendaNowPresentation = updated }
        } else {
            // Semantic transitions only: gap → ongoing, a concurrent event
            // joining/leaving the active set, or ongoing → the next gap.
            // Re-layout briefly, but deliberately do not issue a scroll.
            withAnimation(.easeOut(duration: 0.12)) { agendaNowPresentation = updated }
        }
    }

    private func agendaEvaluationDate(
        actualNow: Date,
        day: Date,
        events: [AgendaEventModel],
        calendar: Calendar
    ) -> Date {
        guard AppConfiguration.previewsFirstEventAsOngoing else { return actualNow }
        let timedIntervals = events
            .filter { !$0.isAllDay && $0.status != .cancelled }
            .compactMap { agendaInterval(for: $0, on: day, calendar: calendar) }
        guard let firstInterval = timedIntervals.min(by: { $0.start < $1.start }) else { return actualNow }

        let previewOffset = min(15 * 60, max(firstInterval.duration / 2, 1))
        return firstInterval.start.addingTimeInterval(previewOffset)
    }

    /// Shared by both the header's chevron buttons and left/right arrow-key
    /// navigation, so clicking `<`/`>` lands on the same day (previous
    /// month's day 1, next month's last day, or today when returning to the
    /// current month) and explicitly drives the same agenda request as
    /// keyboard navigation, rather than only moving `visibleMonth` with no
    /// agenda sync.
    package func moveToAdjacentMonth(_ direction: CalendarArrowKey) {
        guard let landingDate = viewModel.moveToAdjacentMonth(direction: direction) else { return }
        requestedMonthAgendaDate = AgendaScrollTarget(date: landingDate)
    }

    /// The search-jump path (`.jumpToDate`/`.jumpToMonth`): reveals Month
    /// unconditionally and immediately, bypassing the normal
    /// `revealMonthIfPrepared()` gate — a deliberate difference from
    /// `selectViewMode(.month)`, not an oversight. Search jumps land on an
    /// arbitrary, possibly-distant date the agenda hasn't prepared yet;
    /// gating on `preparedMonthAgendaDate` here would leave Month simply
    /// not appearing (or showing a stale position) until background prep
    /// catches up, which is a worse experience than showing it right away.
    package func selectMonthImmediately() {
        selectedViewMode = .month
        displayedViewMode = .month
    }

    package func jumpToMonth(_ date: Date) {
        selectMonthImmediately()
        withAnimation(.easeInOut(duration: 0.3)) { viewModel.jumpToMonth(date) }
    }
}

/// The panel's reveal, as navigation sees it: the window opens only once
/// the requested day is positioned (`PopoverPresentationCoordinator`).
@MainActor
package protocol PanelRevealing: AnyObject {
    /// The open waiting to be revealed, if any.
    var openRequestID: UUID? { get }
    func markReady(_ requestID: UUID)
}
