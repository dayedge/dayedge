import Foundation

/// Event or task? What a parsed draft can become, the one to select first.
/// Pure: read from the draft alone, so the palette and tests agree.
///
/// 1. Said outright ("t:e", "t:t", a leading "+") — only that.
/// 2. Hard signals: a time range, a duration, a span of days or "all day"
///    → event; a priority → task. Both at once → both, task first.
/// 3. Soft signals pick the order: a place or calendar tag → event first;
///    a list tag or "todo …" / "remind me to …" → task first.
/// 4. Otherwise a day with a time → both, event first; a day alone → both,
///    task first.
/// 5. No day → task only (or nothing — the task's confidence decides).
package struct QuickAddKindDecision: Equatable, Sendable {
    /// What to offer, the selected one first. Never empty.
    package let kinds: [QuickAddKind]

    package var selected: QuickAddKind { kinds[0] }

    package init(_ kinds: [QuickAddKind]) {
        self.kinds = kinds
    }

    package static func decide(_ draft: QuickAddDraft) -> QuickAddKindDecision {
        if let forced = draft.forcedKind { return .init([forced]) }

        let eventHard = draft.endTime != nil || draft.duration != nil || draft.endDay != nil || draft.isAllDay
        let taskHard = draft.priority != .none
        switch (eventHard, taskHard) {
        case (true, true): return .init([.task, .event])
        case (true, false): return .init([.event])
        case (false, true): return .init([.task])
        case (false, false): break
        }

        guard draft.day != nil else { return .init([.task]) }
        let eventSoft = draft.location != nil || draft.calendarID != nil
        let taskSoft = draft.listID != nil || draft.saysTask
        let eventFirst = eventSoft == taskSoft ? draft.startTime != nil : eventSoft
        return .init(eventFirst ? [.event, .task] : [.task, .event])
    }
}
