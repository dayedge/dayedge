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
                ) {
                    TasksNavigatorHeader(store: taskStore, query: router.searchQuery)
                }
                .panelColumn(isShown: isColumnShown(.tasks))

                if models.isAccessCardShown {
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

    var calendarTaskIndex: ScheduledTaskIndex {
        models.calendarTaskIndex(showsTasksInCalendar: showsTasksInCalendar)
    }

    private var monthColumn: some View {
        VStack(spacing: 0) {
            PanelMonthGrid(models: models, taskIndex: calendarTaskIndex, showsWeekNumbers: showsWeekNumbers)
            PanelMonthAgenda(models: models, taskIndex: calendarTaskIndex,
                             isActive: isColumnShown(.month) && !isAskShown,
                             verticalNavigationRequest: verticalNavigationRequest,
                             taskCompletionRequest: taskCompletionRequest)
        }
    }

    private var dayColumn: some View {
        let snapshot = models.daySnapshot
        let navigation = agendaNavigation
        return PanelDayColumn(models: models, taskIndex: calendarTaskIndex,
                              isActive: isColumnShown(.day) && !isAskShown,
                              verticalNavigationRequest: verticalNavigationRequest,
                              taskCompletionRequest: taskCompletionRequest) { facts in
            DayHeaderView(facts, onToday: { navigation.goToToday() },
                          onPrevious: { navigation.moveSelectedDay(by: -1) },
                          onNext: { navigation.moveSelectedDay(by: 1) })
        }
            .onChange(of: models.agendaStore.sections) { _, _ in snapshot.agendaDidChange() }
            .onChange(of: agendaNavigation.displayedViewMode) { old, _ in snapshot.viewModeDidChange(from: old) }
    }
}
