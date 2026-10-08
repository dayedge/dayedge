import SwiftUI
import Domain
import UI

extension DayAgendaView {
    /// `anchored` records the grid-relative target so it survives the task
    /// area above resizing (see `untimedTaskArea`).
    func setScrollTarget(_ y: CGFloat, animated: Bool = false, anchored: CGFloat? = nil) {
        gridAnchoredY = anchored
        if animated {
            withAnimation(.smooth(duration: 0.25)) { scrollPosition.scrollTo(y: y) }
        } else {
            scrollPosition.scrollTo(y: y)
        }
    }

    func minutesSinceMidnight(at date: Date = Date()) -> Int {
        let calendar = Calendar.autoupdatingCurrent
        let components = calendar.dateComponents([.hour, .minute], from: date)
        return (components.hour ?? 0) * 60 + (components.minute ?? 0)
    }

    var matchingPositioningRequest: AgendaScrollTarget? {
        guard let positioningRequest,
              Calendar.autoupdatingCurrent.isDate(positioningRequest.date, inSameDayAs: date) else { return nil }
        return positioningRequest
    }

    // swiftlint:disable:next cyclomatic_complexity - one branch per positioning target: task, event, now
    func applyPositioningIfReady(_ request: AgendaScrollTarget? = nil) {
        guard scrollMetrics.viewportHeight > 0,
              let request = request ?? matchingPositioningRequest,
              appliedPositioningID != request.requestID else { return }

        // Grid-relative; nil = the very top of the document.
        let targetY: CGFloat?
        if let taskID = request.taskID, taskCoordinator != nil {
            // Arrives selected; untimed tasks live at the top of the document.
            guard tasks.allUntimed.contains(where: { $0.id == taskID }) || taskMarkers.contains(where: { $0.task.id == taskID }) else { return }
            select(.task(sectionID: section.id, taskID: taskID), scroll: false)
            targetY = taskMarkers.first { $0.task.id == taskID }.map { max($0.y - scrollMetrics.viewportHeight / 3, 0) }
        } else if let eventID = request.eventID {
            guard let event = events.first(where: { $0.id == eventID }) else { return }
            if event.isAllDay {
                targetY = nil
            } else {
                guard let startMinute = event.startMinutesSinceMidnight else { return }
                let eventY = CGFloat(startMinute) / 60 * AppTheme.Metrics.timelineHourHeight
                targetY = max(eventY - scrollMetrics.viewportHeight / 3, 0)
            }
        } else {
            switch request.nowTarget {
            case .gap, .ongoing, .endOfDay:
                guard let instant = activeNowPresentation?.minute else { return }
                let minuteY = CGFloat(minutesSinceMidnight(at: instant)) / 60 * AppTheme.Metrics.timelineHourHeight
                targetY = max(minuteY - scrollMetrics.viewportHeight / 3, 0)
            case .day:
                targetY = nil
            case nil:
                appliedPositioningID = request.requestID
                onPositioned()
                return
            }
        }

        appliedPositioningID = request.requestID
        if let targetY {
            setScrollTarget(gridTopOffset + targetY, animated: request.animated && isActive, anchored: targetY)
        } else {
            setScrollTarget(0, animated: request.animated && isActive)
        }
        onPositioned()
    }
}
