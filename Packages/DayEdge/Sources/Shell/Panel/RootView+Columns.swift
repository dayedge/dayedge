import SwiftUI
import Domain
import UI
import Agenda
import Tasks
import Intelligence

extension RootView {
    /// A calendar column is on screen: its mode, and no Search view over it.
    /// Month and Day only with Calendar access (the access card instead).
    private func isColumnShown(_ mode: ViewMode) -> Bool {
        guard !searchPalette.isResultsViewShown, agendaNavigation.displayedViewMode == mode else { return false }
        return mode == .tasks || models.calendarAccess.isGranted
    }

    /// Calendar access came back and Month or Day is filling again.
    private var isRefillShown: Bool {
        indexActivity?.isRefilling == true && isColumnShown(agendaNavigation.displayedViewMode)
            && agendaNavigation.displayedViewMode != .tasks
    }

    /// Month or Day is the view, but Calendar isn't allowed.
    private var isAccessCardShown: Bool {
        !searchPalette.isResultsViewShown && !models.calendarAccess.isGranted
            && [.month, .day].contains(agendaNavigation.displayedViewMode)
    }

    /// The calendar mode: Month, Day and Tasks under the search field.
    var calendarBody: some View {
        VStack(spacing: 0) {
            // Reserves the collapsed search header's own space — the
            // real `SearchBarView` below is drawn as a sibling overlay,
            // not in this layout flow, so its expanded suggestion body
            // can draw over this content without pushing it down or
            // resizing the popup. Includes `verticalOffset` so the
            // calendar content shifts down by the same amount Search
            // itself did, keeping the gap between them exactly what it
            // was before that shift.
            Color.clear.frame(height: PanelToolbarMetrics.height + PanelToolbarMetrics.topInset)

            ZStack {
                // Both stay permanently mounted — switching visibility
                // rather than mounting/unmounting is what avoids a
                // fresh scroll-to-selection animation replaying on
                // every round trip. See `displayedViewMode`'s doc
                // comment.
                monthColumn.panelColumn(isShown: isColumnShown(.month))

                dayColumn.panelColumn(isShown: isColumnShown(.day))

                TasksView(
                    store: taskStore,
                    query: router.searchQuery,
                    isActive: agendaNavigation.selectedViewMode == .tasks,
                    navigationRequest: verticalNavigationRequest
                )
                .panelColumn(isShown: isColumnShown(.tasks))

                if isAccessCardShown {
                    PermissionStateView(subject: .calendar, status: models.calendarAccess.status) {
                        models.refresh.requestCalendarAccess()
                    }
                        .zIndex(1)
                }

                // The detailed Search view: the agenda's list for the query,
                // in place of the calendar (the field and switcher stay).
                if searchPalette.isResultsViewShown {
                    SearchResultsView(session: searchPalette.results, palette: searchPalette,
                                      taskCoordinator: models.searchTasks)
                        .zIndex(2)
                        .transition(.opacity)
                }
            }
            .floatingFooterBar(usesNativeEffect: !searchPalette.isResultsViewShown && agendaNavigation.displayedViewMode == .tasks) {
                // A decision owns the bottom while it's up: no footer under
                // it. Nor under Ask, which has its own (this view stays
                // mounted beneath it, and its pill showed through).
                VStack(spacing: 0) {
                    if isRefillShown { CalendarUpdatingNotice() }
                    footerBar
                }
                .opacity(decisions.current == nil && !isAskShown ? 1 : 0)
                .allowsHitTesting(decisions.current == nil && !isAskShown)
            }
        }
    }

    /// Scheduled reminders for the agenda and day view; empty when turned
    /// off in Settings, which leaves those views exactly as without tasks.
    var calendarTaskIndex: ScheduledTaskIndex {
        showsTasksInCalendar ? taskStore.repository.scheduledIndex() : .empty
    }

    /// The month grid's task tick: the list color of the task each day's
    /// agenda lists first. Same open-task rule as the menu bar's ring.
    private func monthTaskColor() -> (Date) -> Color? {
        let index = calendarTaskIndex
        let store = taskStore
        let fallback = theme.secondaryText
        return { date in
            index.tasks(on: date).first.map { store.list(for: $0)?.color ?? fallback }
        }
    }

    @ViewBuilder
    private var monthColumn: some View {
        let viewModel = models.viewModel
        let eventDetail = models.eventDetail
        let calendarTasks = models.calendarTasks
        VStack(spacing: 0) {
            MonthGridSection(
                viewModel: viewModel,
                workdayStore: models.workdayStore,
                showsWeekNumbers: showsWeekNumbers,
                taskColor: monthTaskColor(),
                onToday: { agendaNavigation.goToToday() },
                onPrevious: { agendaNavigation.moveToAdjacentMonth(.left) },
                onNext: { agendaNavigation.moveToAdjacentMonth(.right) },
                onSelect: { date in
                    if Calendar.autoupdatingCurrent.isDateInToday(date) {
                        agendaNavigation.goToToday()
                    } else {
                        agendaNavigation.selectDate(date, preparingMonthAgenda: true)
                    }
                },
                onSelectedDateChange: { models.daySnapshot.selectedDateDidChange(to: $0) }
            )

            AgendaListView(
                store: models.agendaStore,
                scrollTarget: agendaNavigation.requestedMonthAgendaDate,
                nowPresentation: agendaNavigation.agendaNowPresentation,
                keyboardNavigationRequest: verticalNavigationRequest,
                // Only the visible calendar view answers Return.
                detailPresentationRequest: agendaNavigation.displayedViewMode == .month ? eventDetail.detailPresentationRequest : nil,
                detailActionRequest: eventDetail.detailActionRequest,
                taskIndex: calendarTaskIndex,
                taskCoordinator: calendarTasks,
                taskCompletionRequest: taskCompletionRequest,
                onCurrentSectionChange: { date in
                    guard !Calendar.autoupdatingCurrent.isDate(
                        date, inSameDayAs: viewModel.selectedDate
                    ) else { return }
                    // The agenda is already at this date because the user
                    // scrolled there. Update only the grid selection; feeding
                    // it back as a new target would fight native momentum.
                    agendaNavigation.selectDate(date, preparingMonthAgenda: false)
                },
                onKeyboardSelection: { selection in
                    eventDetail.selectKeyboardEvent(selection?.event)
                    calendarTasks.select(selection?.task)
                },
                onEventDetailPresentationChange: { eventID, isShowing in
                    eventDetail.presentationChanged(eventID: eventID, isShowing: isShowing)
                },
                onEventDetailActionFocusChange: { eventID, action in
                    eventDetail.actionFocusChanged(eventID: eventID, action: action)
                },
                isActive: isColumnShown(.month) && !isAskShown,
                onScrollPrepared: { target in
                    agendaNavigation.scrollPrepared(target: target)
                }
            )
            .equatable()
        }
    }

    @ViewBuilder
    private var dayColumn: some View {
        let snapshot = models.daySnapshot
        let eventDetail = models.eventDetail
        let calendarTasks = models.calendarTasks
        let inputs = snapshot.inputs
        let dayDate = inputs.date
        let isDayShown = isColumnShown(.day) && !isAskShown
        DayAgendaView(
            date: dayDate,
            isToday: Calendar.autoupdatingCurrent.isDateInToday(dayDate),
            events: inputs.events,
            onPrevious: { agendaNavigation.moveSelectedDay(by: -1) },
            onNext: { agendaNavigation.moveSelectedDay(by: 1) },
            onToday: { agendaNavigation.goToToday() },
            keyboardNavigationRequest: verticalNavigationRequest,
            positioningRequest: inputs.positioningRequest,
            nowPresentation: inputs.nowPresentation,
            isActive: isDayShown,
            onPositioned: { agendaNavigation.dayPositioned() },
            // Only while Day is on screen: scrolling Month moves the selected
            // date constantly, and the hidden Day view must not re-lay out
            // (or re-scroll) its task area on every one of those changes.
            tasks: isDayShown ? calendarTaskIndex.tasks(on: dayDate) : .none,
            taskCoordinator: calendarTasks,
            taskCompletionRequest: taskCompletionRequest,
            detailPresentationRequest: isDayShown ? eventDetail.detailPresentationRequest : nil,
            onKeyboardSelection: { selection in
                eventDetail.selectKeyboardEvent(selection?.event)
                calendarTasks.select(selection?.task)
            },
            onEventDetailPresentationChange: { eventID, isShowing in
                eventDetail.presentationChanged(eventID: eventID, isShowing: isShowing)
            }
        )
        .task(id: isDayShown ? dayDate : nil) {
            guard agendaNavigation.displayedViewMode == .day else { return }
            await models.agendaStore.ensureLoaded(covering: dayDate)
        }
        .onChange(of: models.agendaStore.sections) { _, _ in snapshot.agendaDidChange() }
        .onChange(of: agendaNavigation.displayedViewMode) { old, _ in snapshot.viewModeDidChange(from: old) }
    }
}
