import Foundation
import Domain

package enum VerticalNavigationDirection {
    case up
    case down
}

/// A fresh identity makes repeated presses observable even when the
/// direction has not changed.
package struct VerticalNavigationRequest: Equatable {
    package let id = UUID()
    package let direction: VerticalNavigationDirection

    package init(direction: VerticalNavigationDirection) {
        self.direction = direction
    }
}

package enum CalendarArrowKey {
    case up
    case down
    case left
    case right
}

package struct AgendaKeyboardSelection: Equatable {
    package let date: Date
    package let event: AgendaEventModel

    package init(date: Date, event: AgendaEventModel) {
        self.date = date
        self.event = event
    }

    /// The selected event as it is now, from that day's events — nil once
    /// it's gone or has moved (a key never acts on a stale selection).
    package func current(in events: [AgendaEventModel]) -> AgendaEventModel? {
        events.first { $0.id == event.id && $0.startDate == event.startDate }
    }
}

package struct AgendaTaskSelection: Equatable {
    package let date: Date
    package let taskID: String

    package init(date: Date, taskID: String) {
        self.date = date
        self.taskID = taskID
    }
}

/// What keyboard selection in a calendar view is on: an event or a task.
package enum AgendaSelection: Equatable {
    case event(AgendaKeyboardSelection)
    case task(AgendaTaskSelection)

    package var event: AgendaKeyboardSelection? {
        if case .event(let selection) = self { return selection }
        return nil
    }

    package var task: AgendaTaskSelection? {
        if case .task(let selection) = self { return selection }
        return nil
    }
}

/// Space in a calendar view: complete the keyboard-selected task.
package struct TaskCompletionRequest: Equatable {
    package let id = UUID()

    package init() {
    }
}

package struct EventDetailPresentationRequest: Equatable {
    package enum Action: Equatable {
        case toggle
        case dismiss
    }

    package let id = UUID()
    package let eventID: String
    package let action: Action

    package init(eventID: String, action: Action) {
        self.eventID = eventID
        self.action = action
    }
}

package enum EventDetailFocusableAction: Equatable, Hashable {
    case copyLink
    case join
    case notes
}

package struct EventDetailFocusedControl: Equatable {
    package let eventID: String
    package let action: EventDetailFocusableAction

    package init(eventID: String, action: EventDetailFocusableAction) {
        self.eventID = eventID
        self.action = action
    }
}

package struct EventDetailActionRequest: Equatable {
    package enum Action: Equatable {
        case copyLink
        case join
        case toggleNotes
    }

    package let id = UUID()
    package let eventID: String
    package let action: Action

    package init(eventID: String, action: Action) {
        self.eventID = eventID
        self.action = action
    }
}
