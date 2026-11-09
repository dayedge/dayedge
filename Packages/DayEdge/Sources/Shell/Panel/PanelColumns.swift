import SwiftUI
import Domain
import UI
import Agenda
import Intelligence

/// The month grid as both windows wire it to the shared models: the
/// popover's Month, the Command Window's Day sidebar.
struct PanelMonthGrid: View {
    @Environment(\.themePalette) private var theme

    let models: RootModels
    let taskIndex: ScheduledTaskIndex
    let showsWeekNumbers: Bool
    /// The popover's grid keeps its hidden Day in step (`DaySnapshot`);
    /// a second grid over the same date mustn't do it twice.
    var drivesDaySnapshot = true

    var body: some View {
        let agendaNavigation = models.agendaNavigation
        MonthGridSection(
            viewModel: models.viewModel,
            workdayStore: models.workdayStore,
            showsWeekNumbers: showsWeekNumbers,
            taskColor: taskColor(),
            onToday: { agendaNavigation.goToToday() },
            onPrevious: { agendaNavigation.moveToAdjacentMonth(.left) },
            onNext: { agendaNavigation.moveToAdjacentMonth(.right) },
            onSelect: { Self.select($0, in: agendaNavigation) },
            onSelectedDateChange: { date in
                if drivesDaySnapshot { models.daySnapshot.selectedDateDidChange(to: date) }
            }
        )
    }

    /// A day picked in a month grid: today is "today" (its now line), any
    /// other day is selected with its agenda brought to it.
    static func select(_ date: Date, in agendaNavigation: AgendaNavigationCoordinator) {
        if Calendar.autoupdatingCurrent.isDateInToday(date) {
            agendaNavigation.goToToday()
        } else {
            agendaNavigation.selectDate(date, preparingMonthAgenda: true)
        }
    }

    /// The month grid's task tick: the list color of the task each day's
    /// agenda lists first. Same open-task rule as the menu bar's ring.
    private func taskColor() -> (Date) -> Color? {
        let index = taskIndex
        let store = models.taskStore
        let fallback = theme.secondaryText
        return { date in
            index.tasks(on: date).first.map { store.list(for: $0)?.color ?? fallback }
        }
    }
}

/// The Day timeline as both windows wire it: the selected day from
/// `DaySnapshot`, its tasks, keys and details — under the header each
/// window composes for itself.
struct PanelDayColumn<Header: View>: View {
    let models: RootModels
    let taskIndex: ScheduledTaskIndex
    /// On screen in its window — keys, scrolling and weather only then.
    let isActive: Bool
    let verticalNavigationRequest: VerticalNavigationRequest?
    let taskCompletionRequest: TaskCompletionRequest?
    var showsWeatherBar = true
    @ViewBuilder let header: (DayHeaderFacts) -> Header

    var body: some View {
        let agendaNavigation = models.agendaNavigation
        let eventDetail = models.eventDetail
        let calendarTasks = models.calendarTasks
        let inputs = models.daySnapshot.inputs
        let dayDate = inputs.date
        DayAgendaView(
            date: dayDate,
            isToday: Calendar.autoupdatingCurrent.isDateInToday(dayDate),
            events: inputs.events,
            keyboardNavigationRequest: verticalNavigationRequest,
            positioningRequest: inputs.positioningRequest,
            nowPresentation: inputs.nowPresentation,
            isActive: isActive,
            showsWeatherBar: showsWeatherBar,
            onPositioned: { agendaNavigation.dayPositioned() },
            // Only while Day is on screen: scrolling Month moves the selected
            // date constantly, and the hidden Day view must not re-lay out
            // (or re-scroll) its task area on every one of those changes.
            tasks: isActive ? taskIndex.tasks(on: dayDate) : .none,
            taskCoordinator: calendarTasks,
            taskCompletionRequest: taskCompletionRequest,
            detailPresentationRequest: isActive ? eventDetail.detailPresentationRequest : nil,
            onKeyboardSelection: { selection in
                eventDetail.selectKeyboardEvent(selection?.event)
                calendarTasks.select(selection?.task)
            },
            onEventDetailPresentationChange: { eventID, isShowing in
                eventDetail.presentationChanged(eventID: eventID, isShowing: isShowing)
            },
            header: header
        )
        .task(id: isActive ? dayDate : nil) {
            guard agendaNavigation.displayedViewMode == .day else { return }
            await models.agendaStore.ensureLoaded(covering: dayDate)
        }
    }
}

/// Month's agenda as both windows wire it: one continuous list that
/// follows the selected date and moves it as it scrolls.
struct PanelMonthAgenda: View {
    let models: RootModels
    let taskIndex: ScheduledTaskIndex
    /// On screen in its window — keys, scrolling and the reveal only then.
    let isActive: Bool
    let verticalNavigationRequest: VerticalNavigationRequest?
    let taskCompletionRequest: TaskCompletionRequest?

    var body: some View {
        let agendaNavigation = models.agendaNavigation
        let eventDetail = models.eventDetail
        let calendarTasks = models.calendarTasks
        AgendaListView(
            store: models.agendaStore,
            scrollTarget: agendaNavigation.requestedMonthAgendaDate,
            nowPresentation: agendaNavigation.agendaNowPresentation,
            keyboardNavigationRequest: verticalNavigationRequest,
            // Only the visible calendar view answers Return.
            detailPresentationRequest: agendaNavigation.displayedViewMode == .month ? eventDetail.detailPresentationRequest : nil,
            detailActionRequest: eventDetail.detailActionRequest,
            taskIndex: taskIndex,
            taskCoordinator: calendarTasks,
            taskCompletionRequest: taskCompletionRequest,
            onCurrentSectionChange: followAgenda,
            onKeyboardSelection: { selection in
                // Moving the grid clears the keyboard selection, so it goes first.
                if let selection { followAgenda(to: selection.date) }
                eventDetail.selectKeyboardEvent(selection?.event)
                calendarTasks.select(selection?.task)
            },
            onEventDetailPresentationChange: { eventID, isShowing in
                eventDetail.presentationChanged(eventID: eventID, isShowing: isShowing)
            },
            onEventDetailActionFocusChange: { eventID, action in
                eventDetail.actionFocusChanged(eventID: eventID, action: action)
            },
            isActive: isActive,
            onScrollPrepared: { target in
                agendaNavigation.scrollPrepared(target: target)
            },
            onLeave: { agendaNavigation.rememberMonthPosition($0) }
        )
        .equatable()
    }

    /// The agenda is already at this date because the user scrolled (or
    /// moved the keyboard selection) there. Update only the grid selection;
    /// feeding it back as a new target would fight native momentum.
    private func followAgenda(to date: Date) {
        guard !Calendar.autoupdatingCurrent.isDate(date, inSameDayAs: models.viewModel.selectedDate) else { return }
        models.agendaNavigation.selectDate(date, preparingMonthAgenda: false)
    }
}
