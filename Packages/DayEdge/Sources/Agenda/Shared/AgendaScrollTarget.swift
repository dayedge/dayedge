import Foundation

/// Identifies a scrollable position within `AgendaListView` — either a
/// day's own pinned header, a specific event within a day, or the
/// synthetic NOW marker row. `AgendaSectionProjection`/`AgendaScrollCoordinator`
/// resolve to and operate on these; the view attaches them via `.id(_:)`.
package enum AgendaScrollAnchor: Hashable, Sendable {
    case day(Date)
    case event(sectionID: Date, eventID: String)
    case now(sectionID: Date)
    case task(sectionID: Date, taskID: String)

    package var sectionID: Date {
        switch self {
        case .day(let date): date
        case .event(let sectionID, _): sectionID
        case .now(let sectionID): sectionID
        case .task(let sectionID, _): sectionID
        }
    }

    /// An event or task row — something keyboard selection can land on.
    package var isItem: Bool {
        switch self {
        case .event, .task: true
        case .day, .now: false
        }
    }
}

/// A request to scroll an agenda to a specific day — and, optionally, a
/// specific event within it. Used both for the visible tap-to-scroll
/// gesture and to background-prepare a currently-hidden agenda's scroll
/// position ahead of a mode switch (see `RootView`'s
/// `requestedMonthAgendaDate`/`preparedMonthAgendaDate`).
package struct AgendaScrollTarget: Equatable {
    /// Makes repeated requests independently cancellable/observable even
    /// when they point at the same calendar day.
    package let requestID: UUID
    package let date: Date
    package var eventID: String?
    /// A task on that day (occurrence navigation, "Show in Calendar"): it is
    /// scrolled to and selected.
    package var taskID: String?
    package var nowTarget: AgendaNowTarget?
    package var animated: Bool

    package init(
        requestID: UUID = UUID(),
        date: Date,
        eventID: String? = nil,
        taskID: String? = nil,
        nowTarget: AgendaNowTarget? = nil,
        animated: Bool = true
    ) {
        self.requestID = requestID
        self.date = date
        self.eventID = eventID
        self.taskID = taskID
        self.nowTarget = nowTarget
        self.animated = animated
    }
}
