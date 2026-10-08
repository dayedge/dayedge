import SwiftUI

/// Month's header, weekday row and grid — its own view so the selected
/// date and visible month are read here, not by the root: scrolling the
/// agenda moves the selection day by day, and that should redraw the grid,
/// not the whole window.
package struct MonthGridSection: View {
    package let viewModel: CalendarViewModel
    package let workdayStore: WorkdayStore
    package let showsWeekNumbers: Bool
    package let taskColor: (Date) -> Color?
    package let onToday: () -> Void
    package let onPrevious: () -> Void
    package let onNext: () -> Void
    package let onSelect: (Date) -> Void
    /// Every selection change (the root keeps the hidden Day view in step).
    package let onSelectedDateChange: (Date) -> Void

    package var body: some View {
        MonthHeaderView(
            monthTitle: viewModel.monthTitle,
            yearTitle: viewModel.yearTitle,
            workdaySummary: workdayStore.headerSummary,
            onToday: onToday,
            onPrevious: onPrevious,
            onNext: onNext
        )

        WeekdayRowView(symbols: viewModel.weekdaySymbols)

        MonthGridView(
            days: viewModel.days,
            selectedDate: viewModel.selectedDate,
            onSelect: onSelect,
            eventsProvider: { date in viewModel.events(onDate: date) },
            isMarkedHoliday: { workdayStore.isMarkedHoliday($0) },
            taskColor: taskColor,
            weekNumbers: showsWeekNumbers ? viewModel.weekNumbers : []
        )
        .padding(.bottom, 10)
        .onChange(of: viewModel.visibleMonth) { _, month in
            workdayStore.update(visibleMonth: month)
        }
        .onChange(of: viewModel.selectedDate) { _, date in onSelectedDateChange(date) }
        .task { workdayStore.update(visibleMonth: viewModel.visibleMonth) }
    }

    package init(
        viewModel: CalendarViewModel,
        workdayStore: WorkdayStore,
        showsWeekNumbers: Bool,
        taskColor: @escaping (Date) -> Color?,
        onToday: @escaping () -> Void,
        onPrevious: @escaping () -> Void,
        onNext: @escaping () -> Void,
        onSelect: @escaping (Date) -> Void,
        onSelectedDateChange: @escaping (Date) -> Void
    ) {
        self.viewModel = viewModel
        self.workdayStore = workdayStore
        self.showsWeekNumbers = showsWeekNumbers
        self.taskColor = taskColor
        self.onToday = onToday
        self.onPrevious = onPrevious
        self.onNext = onNext
        self.onSelect = onSelect
        self.onSelectedDateChange = onSelectedDateChange
    }
}
