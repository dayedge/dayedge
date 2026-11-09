import SwiftUI
import Domain
import UI
import Agenda

extension CommandRootView {
    /// Month: the grid with each day's events beside the popover's agenda,
    /// which follows the selected date (and moves it as it scrolls).
    var monthWorkspace: some View {
        CommandMonthWorkspace(models: models, taskIndex: calendarTaskIndex,
                              isActive: isColumnShown(.month),
                              verticalNavigationRequest: verticalNavigationRequest,
                              taskCompletionRequest: taskCompletionRequest)
    }
}

/// Its own view: what it reads (the month's days, the chips) redraws only
/// Month, never the whole window.
private struct CommandMonthWorkspace: View {

    let models: RootModels
    let taskIndex: ScheduledTaskIndex
    let isActive: Bool
    let verticalNavigationRequest: VerticalNavigationRequest?
    let taskCompletionRequest: TaskCompletionRequest?

    var body: some View {
        let navigation = models.agendaNavigation
        let viewModel = models.viewModel
        HStack(spacing: 0) {
            MonthEventGridView(
                viewModel: viewModel,
                workdayStore: models.workdayStore,
                events: { models.monthEvents.events(on: $0) },
                onToday: { navigation.goToToday() },
                onPrevious: { navigation.moveToAdjacentMonth(.left) },
                onNext: { navigation.moveToAdjacentMonth(.right) },
                onSelect: { PanelMonthGrid.select($0, in: navigation) }
            )
            .takesOfferedSize()

            WorkspaceRule(.structural, axis: .vertical)

            PanelMonthAgenda(models: models, taskIndex: taskIndex, isActive: isActive,
                             verticalNavigationRequest: verticalNavigationRequest,
                             taskCompletionRequest: taskCompletionRequest)
                .takesOfferedSize(width: AppTheme.CommandWindow.monthAgendaWidth)
        }
        // Per month shown (its neighbours readied behind it), never per
        // selection; calendar changes are the store's own.
        .task(id: isActive ? viewModel.visibleMonth : nil) {
            guard isActive else { return }
            await models.monthEvents.show(month: viewModel.visibleMonth)
        }
    }
}
