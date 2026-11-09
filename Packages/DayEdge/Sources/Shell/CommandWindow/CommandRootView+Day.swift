import SwiftUI
import Domain
import UI
import Agenda

extension CommandRootView {
    /// Day: the mini-month and the day's weather beside the timeline. One
    /// selected date — the grid, the arrows and the timeline all move it.
    var dayWorkspace: some View {
        let isActive = isColumnShown(.day)
        return HStack(spacing: 0) {
            CommandDaySidebar(models: models, taskIndex: calendarTaskIndex, showsWeekNumbers: showsWeekNumbers,
                              isActive: isActive)
                .takesOfferedSize(width: AppTheme.CommandWindow.sidebarWidth)

            WorkspaceRule(.structural, axis: .vertical)

            // Its own heading: the sidebar's month and chevrons give the rest.
            PanelDayColumn(models: models, taskIndex: calendarTaskIndex, isActive: isActive,
                           verticalNavigationRequest: verticalNavigationRequest,
                           taskCompletionRequest: taskCompletionRequest, showsWeatherBar: false) { [models] facts in
                DayPaneHeading(facts: facts, shownMonth: models.viewModel.visibleMonth,
                               onToday: { models.agendaNavigation.goToToday() })
            }
                .takesOfferedSize()
        }
    }
}

/// Day's sidebar: its own view, so the day it reads (which moves as the
/// selection does) redraws only the sidebar, never the whole window.
private struct CommandDaySidebar: View {

    let models: RootModels
    let taskIndex: ScheduledTaskIndex
    let showsWeekNumbers: Bool
    let isActive: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PanelMonthGrid(models: models, taskIndex: taskIndex, showsWeekNumbers: showsWeekNumbers,
                           drivesDaySnapshot: false)
            WorkspaceRule(.section)
                .padding(.horizontal, AppTheme.horizontalPadding)
            DayWeatherPanel(date: models.daySnapshot.inputs.date,
                            width: AppTheme.CommandWindow.sidebarWidth - 2 * AppTheme.horizontalPadding,
                            isActive: isActive)
                .padding(.horizontal, AppTheme.horizontalPadding)
                .padding(.top, 16)
            Spacer(minLength: 0)
        }
    }
}
