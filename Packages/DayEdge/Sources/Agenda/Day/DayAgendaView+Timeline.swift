import SwiftUI
import Domain
import UI

extension DayAgendaView {
    @ViewBuilder
    var timelineContent: some View {
        ZStack(alignment: .topLeading) {
            HourGridBackgroundView()

            GeometryReader { proxy in
                let labelColumnWidth = AppTheme.Metrics.timelineEventLeadingEdge
                let availableWidth = proxy.size.width - labelColumnWidth - AppTheme.Metrics.timelineHorizontalInset
                let minuteHeight = AppTheme.Metrics.timelineHourHeight / 60
                let lane = laneLayout

                ForEach(lane.events) { positioned in
                    let columnWidth = availableWidth / CGFloat(positioned.columnCount)
                    let width = max(columnWidth - 3, 20)
                    let x = labelColumnWidth + columnWidth * CGFloat(positioned.columnIndex)
                    let y = CGFloat(positioned.startMinutes) * minuteHeight
                    let height = max(CGFloat(positioned.endMinutes - positioned.startMinutes) * minuteHeight, 16)

                    DayTimelineEventView(
                        event: positioned.event,
                        date: date,
                        height: height,
                        isOngoing: isOngoing(positioned.event),
                        isKeyboardSelected: keyboardAnchor == .event(sectionID: section.id, eventID: positioned.event.id),
                        detailPresentationRequest: detailPresentationRequest,
                        onDetailPresentationChange: { onEventDetailPresentationChange(positioned.event.id, $0) }
                    )
                        .frame(width: width, alignment: .topLeading)
                        .offset(x: x, y: y)
                }

                // Timed tasks: cards in the same lane, the ring on their due
                // minute — and a short tick across the gutter at that
                // minute, saying "due here" even when a stack pushes a card
                // down.
                if let taskCoordinator {
                    ForEach(taskMarkers) { marker in
                        Rectangle()
                            .fill(theme.tasks.timelineDueTick)
                            .frame(width: labelColumnWidth - AppTheme.Metrics.timelineLabelTrailingEdge, height: 1)
                            .offset(x: AppTheme.Metrics.timelineLabelTrailingEdge, y: marker.anchorY - 0.5)
                            .allowsHitTesting(false)
                            .transition(.opacity)
                    }
                    ForEach(taskMarkers) { marker in
                        let column = lane.tasks[marker.task.id] ?? .init(columnIndex: 0, columnCount: 1)
                        let columnWidth = availableWidth / CGFloat(column.columnCount)
                        let x = labelColumnWidth + columnWidth * CGFloat(column.columnIndex)
                        // Alone in its row it stays narrower than an event;
                        // sharing, it takes its column like one.
                        let maxWidth = column.columnCount == 1
                            ? availableWidth * AppTheme.Tasks.timelineCardMaxWidthFraction
                            : max(columnWidth - 3, 20)

                        TimedTaskMarkerView(
                            task: marker.task,
                            day: date,
                            coordinator: taskCoordinator,
                            isKeyboardSelected: keyboardAnchor == .task(sectionID: section.id, taskID: marker.task.id),
                            isActive: isActive,
                            isProjected: tasks.projectedIDs.contains(marker.task.id),
                            minWidth: min(AppTheme.Tasks.timelineCardMinWidth, maxWidth),
                            onComplete: { complete(marker.task.id) },
                            onSelect: { select(.task(sectionID: section.id, taskID: marker.task.id), scroll: false) }
                        )
                        .frame(maxWidth: maxWidth, alignment: .leading)
                        .offset(x: x, y: marker.y)
                        .transition(.opacity)
                    }
                }
            }

            if isToday {
                // Drawn after the event layer so its surface-colored
                // knockout remains legible over every calendar color.
                // Ticks only while on screen: hidden, the minute tick
                // redrew the timeline for nobody. Shown again, it starts
                // from the current minute.
                if isActive {
                    TimelineView(.periodic(from: .now, by: 60)) { context in
                        NowIndicatorView(
                            minutesSinceMidnight: minutesSinceMidnight(at: context.date),
                            statusLabel: activeNowPresentation?.target.statusLabel(format: timeFormat)
                        )
                    }
                    .allowsHitTesting(false)
                } else {
                    NowIndicatorView(
                        minutesSinceMidnight: minutesSinceMidnight(),
                        statusLabel: activeNowPresentation?.target.statusLabel(format: timeFormat)
                    )
                    .allowsHitTesting(false)
                }
            }
        }
        .padding(.top, AppTheme.Metrics.dayTimelineTopGap)
        .padding(.bottom, 24)
    }

    /// Untimed tasks: above the grid, in the scrolling document (not the
    /// pinned bar), after the all-day events. Absent when there are none.
    @ViewBuilder
    var untimedTaskArea: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let taskCoordinator, !tasks.allUntimed.isEmpty {
                ForEach(tasks.overdue) { untimedRow($0, overdue: true, coordinator: taskCoordinator) }
                ForEach(tasks.untimed) { untimedRow($0, overdue: false, coordinator: taskCoordinator) }
                Rectangle()
                    .fill(theme.chrome.gridRule)
                    .frame(height: 1)
                    .padding(.horizontal, AppTheme.Metrics.timelineHorizontalInset)
                    .padding(.top, 6)
            }
        }
        .padding(.top, tasks.allUntimed.isEmpty || taskCoordinator == nil ? 0 : 6)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
            gridTopOffset = height
            // Keep whatever the grid was positioned on in place — only on
            // screen; a hidden Day view never scrolls itself.
            if isActive, let gridAnchoredY { setScrollTarget(gridTopOffset + gridAnchoredY, anchored: gridAnchoredY) }
        }
    }

    private func untimedRow(_ task: TaskItem, overdue: Bool, coordinator: CalendarTaskCoordinator) -> some View {
        let anchor = AgendaScrollAnchor.task(sectionID: section.id, taskID: task.id)
        return CalendarTaskRowView(
            task: task,
            day: date,
            coordinator: coordinator,
            isOverdue: overdue,
            isToday: isToday,
            isKeyboardSelected: keyboardAnchor == anchor,
            isActive: isActive,
            isProjected: tasks.projectedIDs.contains(task.id),
            onComplete: { complete(task.id) },
            onSelect: { select(anchor, scroll: false) }
        )
        .id(anchor)
        .transition(.opacity)
    }
}
