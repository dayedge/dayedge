import SwiftUI
import Domain
import UI

/// The Command Window's month: the popover's header and weekday row over a
/// grid that fills the column, each day listing its events as chips (time,
/// title, the calendar's colour; all-day ones filled). Selecting a day is
/// the shared selection — the agenda beside it follows.
package struct MonthEventGridView: View {
    @Environment(\.themePalette) private var theme

    package let viewModel: CalendarViewModel
    package let workdayStore: WorkdayStore
    package let events: (Date) -> [AgendaEventModel]
    package let onToday: () -> Void
    package let onPrevious: () -> Void
    package let onNext: () -> Void
    package let onSelect: (Date) -> Void

    package var body: some View {
        VStack(spacing: 0) {
            MonthHeaderView(
                monthTitle: viewModel.monthTitle,
                yearTitle: viewModel.yearTitle,
                workdaySummary: workdayStore.headerSummary,
                onToday: onToday,
                onPrevious: onPrevious,
                onNext: onNext
            )
            WeekdayRowView(symbols: viewModel.weekdaySymbols)
            grid
                .padding(.horizontal, AppTheme.horizontalPadding)
                .padding(.bottom, 10)
        }
        .onChange(of: viewModel.visibleMonth) { _, month in workdayStore.update(visibleMonth: month) }
        .task { workdayStore.update(visibleMonth: viewModel.visibleMonth) }
    }

    private func isSelected(_ date: Date) -> Bool {
        Calendar.autoupdatingCurrent.isDate(date, inSameDayAs: viewModel.selectedDate)
    }

    private var grid: some View {
        let days = viewModel.days
        let rows = max((days.count + 6) / 7, 1)
        // Read here, in the body, so holidays arriving redraw the grid.
        let holidays = days.map { workdayStore.holiday(on: $0.date) }
        return GeometryReader { proxy in
            let rowHeight = proxy.size.height / CGFloat(rows)
            let columnWidth = proxy.size.width / 7
            // Cells by slot, as in `MonthGridView`: a month change updates
            // the same 42 cells instead of replacing them.
            cells(days: days, holidays: holidays, rows: rows, size: CGSize(width: columnWidth, height: rowHeight))
        }
    }

    /// Every cell at its exact size: flexible cells made each layout pass
    /// measure all 42 cells' text again to share out the width (measured).
    private func cells(days: [DayCellModel], holidays: [(isMarked: Bool, name: String?)], rows: Int,
                       size: CGSize) -> some View {
            VStack(spacing: 0) {
                ForEach(0..<rows, id: \.self) { row in
                    HStack(spacing: 0) {
                        ForEach(0..<7, id: \.self) { column in
                            let slot = row * 7 + column
                            Group {
                                if days.indices.contains(slot) {
                                    MonthEventCellView(day: days[slot],
                                                       isSelected: isSelected(days[slot].date),
                                                       isMarkedHoliday: holidays[slot].isMarked,
                                                       holidayName: holidays[slot].name,
                                                       events: events(days[slot].date),
                                                       height: size.height,
                                                       onSelect: onSelect)
                                        .equatable()
                                } else {
                                    Color.clear
                                }
                            }
                            .frame(width: size.width, height: size.height)
                            .overlay(alignment: .leading) {
                                if column > 0 { WorkspaceRule(.gridHairline, axis: .vertical) }
                            }
                        }
                    }
                    .overlay(alignment: .top) { WorkspaceRule(.gridHairline) }
                }
            }
    }

    package init(viewModel: CalendarViewModel, workdayStore: WorkdayStore,
                 events: @escaping (Date) -> [AgendaEventModel],
                 onToday: @escaping () -> Void, onPrevious: @escaping () -> Void, onNext: @escaping () -> Void,
                 onSelect: @escaping (Date) -> Void) {
        self.viewModel = viewModel
        self.workdayStore = workdayStore
        self.events = events
        self.onToday = onToday
        self.onPrevious = onPrevious
        self.onNext = onNext
        self.onSelect = onSelect
    }
}

/// One day of `MonthEventGridView`: its number, then as many chips as fit.
/// Equatable without its action, so a selection change redraws only the
/// two cells it moves between.
///
/// Three independent states: the month shown (its surface, a shade apart
/// from its neighbours'), the selection (the whole cell, faintly in the
/// today accent) and today (the compact calendar's badge on the number).
struct MonthEventCellView: View, Equatable {
    @Environment(\.themePalette) private var theme
    @Environment(\.timeFormat) private var timeFormat

    let day: DayCellModel
    let isSelected: Bool
    let isMarkedHoliday: Bool
    /// The public holiday's name (weekend ones too), for its tooltip and
    /// VoiceOver; nil when marking holidays is off.
    let holidayName: String?
    let events: [AgendaEventModel]
    let height: CGFloat
    let onSelect: (Date) -> Void

    private static let numberHeight: CGFloat = 22
    private static let inset: CGFloat = 4

    private var numberColor: Color {
        DayNumberRole(isToday: day.isToday, isCurrentMonth: day.isCurrentMonth,
                      isWeekend: day.isWeekend, isMarkedHoliday: isMarkedHoliday).color(in: theme)
    }

    var body: some View {
        let rows = MonthChipLayout.rowCount(cellHeight: height - 2 * Self.inset, headerHeight: Self.numberHeight)
        let layout = MonthChipLayout(events: events, rows: rows)
        VStack(alignment: .leading, spacing: MonthChipLayout.chipSpacing) {
            holidayLabeled(dayNumber)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .frame(height: Self.numberHeight)
            ForEach(layout.visible) { chip($0) }
            if layout.overflowCount > 0 {
                Text(L10n.tr("agenda.overflow", "+\(layout.overflowCount) more"))
                    .font(AppTheme.TextStyle.eventSubtitle)
                    .foregroundStyle(theme.secondaryText)
                    .frame(height: MonthChipLayout.chipHeight)
                    .padding(.leading, 4)
            }
        }
        .padding(Self.inset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // The day's shape, in the bottom inset (no chip row given up).
        .overlay(alignment: .bottom) {
            DayBusyStripView(segments: DayBusyStrip.segments(events: events, day: day.date,
                                                             hours: AppTheme.CommandWindow.busyStripHours,
                                                             calendar: .autoupdatingCurrent))
                .padding(.horizontal, Self.inset)
                .padding(.bottom, 1)
        }
        .background {
            let workspace = theme.workspace
            Rectangle()
                .fill(day.isCurrentMonth ? workspace.displayedMonthSurface : workspace.adjacentMonthSurface)
                .overlay { if isSelected { Rectangle().fill(workspace.selectedDaySurface) } }
        }
        .contentShape(Rectangle())
        .onTapGesture { onSelect(day.date) }
        .accessibilityElement(children: .combine)
        .accessibilityValue(holidayName ?? "")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.day.date == rhs.day.date && lhs.day.isToday == rhs.day.isToday && lhs.isSelected == rhs.isSelected
            && lhs.day.isCurrentMonth == rhs.day.isCurrentMonth && lhs.isMarkedHoliday == rhs.isMarkedHoliday
            && lhs.holidayName == rhs.holidayName
            && lhs.height == rhs.height && lhs.events == rhs.events
    }

    /// A holiday's name on hover — only holidays carry the tooltip.
    @ViewBuilder
    private func holidayLabeled(_ number: some View) -> some View {
        if let holidayName {
            number.hoverTooltip(holidayName)
        } else {
            number
        }
    }

    /// Today: the compact calendar's circle (a temporal marker, shown
    /// whatever is selected). The selection is the cell's, never a badge.
    private var dayNumber: some View {
        Text("\(day.dayNumber)")
            .font(AppTheme.TextStyle.dayNumber)
            .fontWeight(isSelected ? .bold : nil)
            .foregroundStyle(numberColor)
            .frame(width: Self.numberHeight, height: Self.numberHeight)
            .background {
                // A circle, as in the compact calendar.
                if day.isToday { Circle().fill(theme.todayFill) }
            }
    }

    private func chip(_ event: AgendaEventModel) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 1, style: .continuous)
                .fill(event.color)
                .frame(width: 2.5)
                .padding(.vertical, 2)
            if !event.isAllDay, let start = event.startDate {
                Text(timeFormat.time(start))
                    .foregroundStyle(theme.secondaryText)
                    .monospacedDigit()
            }
            Text(event.title)
                .foregroundStyle(theme.primaryText)
        }
        .font(AppTheme.TextStyle.eventSubtitle)
        .lineLimit(1)
        .padding(.horizontal, 3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: MonthChipLayout.chipHeight)
        .background {
            if event.isAllDay {
                RoundedRectangle(cornerRadius: 4, style: .continuous).fill(event.color.opacity(0.22))
            }
        }
    }
}
