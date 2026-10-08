import SwiftUI
import UI

/// One search result: a fixed date column (the tile on a day's first row,
/// empty after it — the event/task geometry never shifts), then the very
/// same compact row the agenda uses. The row owns selection and clicks.
package struct SearchResultRow: View {
    @Environment(\.themePalette) private var theme
    @Environment(\.timeFormat) private var timeFormat
    @Environment(\.dateFormatter) private var dateFormatter

    package let item: SearchResultRowItem
    package let taskCoordinator: CalendarTaskCoordinator
    package var isSelected = false
    package var isDetailPresented = false
    package var isTaskDetailPresented: Bool {
        if case .task(let task) = item.result { return taskCoordinator.isPresented(.init(taskID: task.id, day: day)) }
        return false
    }
    /// The palette's collapsed preview leaves the Join pill out.
    package var showsJoin = true
    /// The date column; off where the day is already said (Create Event's
    /// overlap).
    package var showsDateColumn = true
    package var detailPresentationRequest: EventDetailPresentationRequest?
    package var onDetailPresentationChange: (Bool) -> Void = { _ in }
    package var onTap: () -> Void = {}
    package var onDoubleTap: () -> Void = {}

    @State private var isHovering = false

    private var background: Color {
        if isDetailPresented || isTaskDetailPresented { return theme.content.detailSelectionFill }
        if isSelected { return theme.chrome.rowSelection }
        if isHovering { return theme.chrome.rowHover }
        return .clear
    }

    /// Without the Join pill the time and its glyphs need less room.
    private var timeColumnWidth: CGFloat {
        showsJoin ? AppTheme.Search.timeColumnWidth : AppTheme.Search.timeColumnWidthWithoutJoin
    }

    /// The day the row's details and actions are about.
    private var day: Date {
        item.day ?? Calendar.autoupdatingCurrent.startOfDay(for: Date())
    }

    package var body: some View {
        // The row sits centered on its date tile.
        HStack(alignment: .center, spacing: 0) {
            if showsDateColumn {
                ZStack(alignment: .topLeading) {
                    Color.clear
                    if item.showsDateTile, let date = item.day {
                        CalendarDateTile(date: date, isToday: item.isToday, showsYear: item.isOutsideCurrentYear)
                    }
                }
                .frame(width: AppTheme.Search.dateColumnWidth,
                       height: item.showsDateTile ? AppTheme.DateTile.tileHeight : 1, alignment: .topLeading)
            }

            row
        }
        .padding(.leading, 6)
        .padding(.vertical, 2)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(background)
        )
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .onTapGesture(count: 2) { onDoubleTap() }
        .onTapGesture { onTap() }
        // One result, one accessibility object: "Event, Monday 5 October,
        // 10:30 to 10:55, PZU 1f Daily".
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private var accessibilityText: String {
        let date = item.day.map { dateFormatter.format($0, .compact, weekday: .full) } ?? L10n.tr("searchresultrow.no.date", "No date")
        switch item.result {
        case .event(let event):
            let time = event.isAllDay ? L10n.tr(
                "searchresultrow.all.day", "all day"
            ) : [event.startText(timeFormat), event.endText(timeFormat)].compactMap { $0 }.joined(separator: " to ")
            return L10n.tr("searchresultrow.event", "Event, \(String(describing: date)), \(String(describing: time)), \(String(describing: event.title))")
        case .task(let task):
            let time = task.hasDueTime ? task.dueDate.map { timeFormat.time($0) } : nil
            return ([L10n.tr("searchresultrow.task", "Task"), date, time, task.title, task.isCompleted ? "completed" : nil] as [String?])
                .compactMap { $0 }.joined(separator: ", ")
        }
    }

    @ViewBuilder
    private var row: some View {
        switch item.result {
        case .event(let event):
            AgendaEventRowView(
                event: event,
                date: day,
                detailPresentationRequest: detailPresentationRequest,
                onDetailPresentationChange: onDetailPresentationChange,
                density: .compact,
                drawsSelectionBackground: false,
                opensDetailsOnTap: false,
                showsJoin: showsJoin,
                compactTimeColumnWidth: timeColumnWidth,
                compactTitleFades: true
            )
        case .task(let task):
            CalendarTaskRowView(
                task: task,
                day: day,
                coordinator: taskCoordinator,
                isProjected: false,
                density: .compact,
                drawsSelectionBackground: false,
                opensDetailsOnTap: false,
                compactTimeColumnWidth: timeColumnWidth,
                compactTitleFades: true,
                onComplete: { _ = taskCoordinator.actions.setCompleted(!task.isCompleted, taskID: task.id) },
                onSelect: onTap
            )
        }
    }
}
