import SwiftUI
import Domain
import UI

extension DayAgendaView {
    // MARK: - Keyboard selection

    var selectedAllDayEventID: String? {
        guard case .event(_, let eventID)? = keyboardAnchor,
              events.contains(where: { $0.id == eventID && $0.isAllDay }) else { return nil }
        return eventID
    }

    private var itemOrder: [AgendaScrollAnchor] {
        AgendaSectionProjection.dayItemAnchors(section: section, tasks: taskCoordinator == nil ? .none : tasks)
    }

    /// Where an item sits in the scroll content; nil for all-day events,
    /// which are pinned above it.
    func contentY(of anchor: AgendaScrollAnchor) -> CGFloat? {
        switch anchor {
        case .event(_, let eventID):
            guard let event = events.first(where: { $0.id == eventID }), !event.isAllDay else { return nil }
            return contentY(minutes: event.startMinutesSinceMidnight ?? 0)
        case .task(_, let taskID):
            if let marker = taskMarkers.first(where: { $0.task.id == taskID }) { return gridTopOffset + marker.y }
            return 0 // untimed: in the area above the grid
        case .day, .now:
            return nil
        }
    }

    /// ↑ / ↓ walk the whole day as one sequence. With nothing selected yet,
    /// they start from what is on screen. An empty day still scrolls by an
    /// hour, as before.
    func moveSelection(_ direction: VerticalNavigationDirection, proxy: ScrollViewProxy) {
        let order = itemOrder
        guard !order.isEmpty else {
            let step = AppTheme.Metrics.timelineHourHeight
            setScrollTarget(max(scrollOffset + (direction == .up ? -step : step), 0))
            return
        }
        let target: AgendaScrollAnchor
        if let keyboardAnchor, let index = order.firstIndex(of: keyboardAnchor) {
            target = order[direction == .up ? max(index - 1, 0) : min(index + 1, order.count - 1)]
        } else {
            let top = scrollOffset
            let bottom = scrollOffset + scrollMetrics.viewportHeight
            switch direction {
            case .down: target = order.first { (contentY(of: $0) ?? top) >= top } ?? order[order.count - 1]
            case .up: target = order.last { (contentY(of: $0) ?? top) <= bottom } ?? order[0]
            }
        }
        select(target, scroll: true, proxy: proxy)
    }

    func select(_ anchor: AgendaScrollAnchor, scroll: Bool, proxy: ScrollViewProxy? = nil) {
        keyboardAnchor = anchor
        switch anchor {
        case .event(_, let eventID):
            onKeyboardSelection(events.first { $0.id == eventID }.map { .event(AgendaKeyboardSelection(date: date, event: $0)) })
        case .task(_, let taskID):
            onKeyboardSelection(.task(AgendaTaskSelection(date: date, taskID: taskID)))
        case .day, .now:
            onKeyboardSelection(nil)
        }
        guard scroll else { return }
        switch anchor {
        case .task(_, let taskID) where !taskMarkers.contains(where: { $0.task.id == taskID }):
            withAnimation(Self.positioningAnimation) { proxy?.scrollTo(anchor, anchor: .center) }
            gridAnchoredY = nil
        default:
            guard let y = contentY(of: anchor) else { return }
            let visible = y >= scrollOffset + 20 && y <= scrollOffset + scrollMetrics.viewportHeight - 40
            if !visible { setScrollTarget(max(y - scrollMetrics.viewportHeight / 3, 0), animated: true) }
        }
    }

    func clearSelection() {
        guard keyboardAnchor != nil else { return }
        keyboardAnchor = nil
        onKeyboardSelection(nil)
    }

    /// Completing moves selection to whatever takes the task's place.
    func complete(_ taskID: String) {
        // A later occurrence of a repeating task can't be completed.
        guard let taskCoordinator, !tasks.projectedIDs.contains(taskID) else { return }
        let removed = AgendaScrollAnchor.task(sectionID: section.id, taskID: taskID)
        let successor = keyboardAnchor == removed ? SelectionSuccessor.after(removing: removed, in: itemOrder) : keyboardAnchor
        withAnimation(.smooth(duration: 0.25)) { taskCoordinator.complete(taskID) }
        if keyboardAnchor == removed {
            if let successor { select(successor, scroll: false) } else { clearSelection() }
        }
    }

    func completeSelectedTask(proxy: ScrollViewProxy) {
        guard case .task(_, let taskID)? = keyboardAnchor else { return }
        complete(taskID)
        if let keyboardAnchor { select(keyboardAnchor, scroll: true, proxy: proxy) }
    }

    func isOngoing(_ event: AgendaEventModel) -> Bool {
        activeNowPresentation?.target.ongoingEventIDs.contains(event.id) == true
    }

    package init(
        date: Date,
        isToday: Bool,
        events: [AgendaEventModel],
        onPrevious: @escaping () -> Void,
        onNext: @escaping () -> Void,
        onToday: @escaping () -> Void = {},
        keyboardNavigationRequest: VerticalNavigationRequest? = nil,
        positioningRequest: AgendaScrollTarget? = nil,
        nowPresentation: AgendaNowPresentation? = nil,
        isActive: Bool = true,
        onPositioned: @escaping () -> Void = {},
        tasks: DayTasks = .none,
        taskCoordinator: CalendarTaskCoordinator? = nil,
        taskCompletionRequest: TaskCompletionRequest? = nil,
        detailPresentationRequest: EventDetailPresentationRequest? = nil,
        onKeyboardSelection: @escaping (AgendaSelection?) -> Void = { _ in },
        onEventDetailPresentationChange: @escaping (String, Bool) -> Void = { _, _ in }
    ) {
        self.date = date
        self.isToday = isToday
        self.events = events
        self.onPrevious = onPrevious
        self.onNext = onNext
        self.onToday = onToday
        self.keyboardNavigationRequest = keyboardNavigationRequest
        self.positioningRequest = positioningRequest
        self.nowPresentation = nowPresentation
        self.isActive = isActive
        self.onPositioned = onPositioned
        self.tasks = tasks
        self.taskCoordinator = taskCoordinator
        self.taskCompletionRequest = taskCompletionRequest
        self.detailPresentationRequest = detailPresentationRequest
        self.onKeyboardSelection = onKeyboardSelection
        self.onEventDetailPresentationChange = onEventDetailPresentationChange
    }
}
