import SwiftUI
import Domain
import UI

extension AgendaListView {
    var loadingEdgeRow: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text(L10n.tr("agendalistview.rows.loading", "Loading…"))
                .font(AppTheme.TextStyle.eventSubtitle)
                .foregroundStyle(theme.secondaryText)
        }
        .padding(.horizontal, AppTheme.horizontalPadding)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    func sectionContent(_ section: AgendaDaySection) -> some View {
        let tasks = taskCoordinator == nil ? DayTasks.none : taskIndex.tasks(on: section.date)
        if section.events.isEmpty && tasks.isEmpty {
            Text(L10n.tr("agendalistview.rows.no.events", "No events"))
                .font(AppTheme.TextStyle.eventSubtitle)
                .foregroundStyle(theme.secondaryText)
                .padding(.horizontal, AppTheme.horizontalPadding)
                .padding(.bottom, 8)
        } else {
            let allDayEvents = section.events.filter(\.isAllDay)

            if !allDayEvents.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(allDayEvents) { event in
                        allDayEventTag(event, in: section)
                    }
                }
                .padding(.horizontal, AppTheme.horizontalPadding)
                .padding(.bottom, 8)
            }

            ForEach(AgendaSectionProjection.rows(section: section, tasks: tasks, nowPresentation: nowPresentation(for: section))) { row in
                switch row.kind {
                case .event(let event, let isOngoing):
                    eventRow(event, in: section, isOngoing: isOngoing)
                case .now(let presentation):
                    nowMarker(presentation, in: section)
                case .task(let task, let isOverdue):
                    taskRow(task, isOverdue: isOverdue, isProjected: tasks.projectedIDs.contains(task.id), in: section)
                }
            }
        }
    }

    private func nowMarker(_ presentation: AgendaNowPresentation, in section: AgendaDaySection) -> some View {
        AgendaNowMarkerView(date: presentation.minute, statusLabel: presentation.target.statusLabel(format: timeFormat))
            .id(AgendaScrollAnchor.now(sectionID: section.id))
    }

    private func allDayEventTag(_ event: AgendaEventModel, in section: AgendaDaySection) -> some View {
        EquatableRow(key: AgendaRowKey(event: event, date: section.date,
                                       detailPresentationRequest: detailPresentationRequest,
                                       detailActionRequest: detailActionRequest, timeFormat: timeFormat)) {
        AllDayEventTagView(
            event: event,
            date: section.date,
            detailPresentationRequest: detailPresentationRequest,
            detailActionRequest: detailActionRequest,
            onDetailPresentationChange: { isShowing in
                onEventDetailPresentationChange(event.id, isShowing)
            },
            onDetailActionFocusChange: { action in
                onEventDetailActionFocusChange(event.id, action)
            }
        )
        }
        .equatable()
        .id(AgendaScrollAnchor.event(sectionID: section.id, eventID: event.id))
    }

    @ViewBuilder
    private func taskRow(_ task: TaskItem, isOverdue: Bool, isProjected: Bool, in section: AgendaDaySection) -> some View {
        if let taskCoordinator {
            let anchor = AgendaScrollAnchor.task(sectionID: section.id, taskID: task.id)
            let isKeyboardSelected = scroll.keyboardAnchor == anchor
            EquatableRow(key: AgendaRowKey(task: task, date: section.date, isKeyboardSelected: isKeyboardSelected,
                                           isOverdue: isOverdue, isToday: section.isToday, isActive: isActive,
                                           isProjected: isProjected, timeFormat: timeFormat)) {
            CalendarTaskRowView(
                task: task,
                day: section.date,
                coordinator: taskCoordinator,
                isOverdue: isOverdue,
                isToday: section.isToday,
                isKeyboardSelected: isKeyboardSelected,
                isActive: isActive,
                isProjected: isProjected,
                onComplete: { [completion] in completion.handler?(task.id, section.id) }
            )
            }
            .equatable()
            .id(anchor)
            .transition(.opacity)
        }
    }

    private func eventRow(_ event: AgendaEventModel, in section: AgendaDaySection, isOngoing: Bool) -> some View {
        let anchor = AgendaScrollAnchor.event(sectionID: section.id, eventID: event.id)
        let isKeyboardSelected = scroll.keyboardAnchor == anchor
        return EquatableRow(key: AgendaRowKey(event: event, date: section.date, isKeyboardSelected: isKeyboardSelected,
                                              isOngoing: isOngoing, detailPresentationRequest: detailPresentationRequest,
                                              detailActionRequest: detailActionRequest, timeFormat: timeFormat)) {
        AgendaEventRowView(
            event: event,
            date: section.date,
            isKeyboardSelected: isKeyboardSelected,
            isOngoing: isOngoing,
            detailPresentationRequest: detailPresentationRequest,
            detailActionRequest: detailActionRequest,
            onDetailPresentationChange: { isShowing in
                onEventDetailPresentationChange(event.id, isShowing)
            },
            onDetailActionFocusChange: { action in
                onEventDetailActionFocusChange(event.id, action)
            }
        )
        }
        .equatable()
        .id(anchor)
    }
}
