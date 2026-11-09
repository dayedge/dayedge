import Foundation
import Domain

extension SearchPaletteModel {
    /// What New Event / New Task (⌘N, ⇧⌘N) start.
    package enum NewItem {
        case event
        case task
    }

    /// Quick Add opened on an empty event or task: the user said what to
    /// make, so nothing is parsed and no ranking applies. The defaults are
    /// a typed query's without dates or #tags: the default list or calendar,
    /// no due date for a task, the next whole hour for an hour for an event.
    /// The same editor, checks and saving as a typed one.
    package func startCreating(_ item: NewItem) async {
        clear()
        let referenceDate = now()
        let lists = item == .task ? taskLists() : []
        let calendars = item == .event ? await eventCalendars() : []
        let candidate: QuickAddCandidate
        switch item {
        case .task:
            guard !lists.isEmpty else { return }
            candidate = .task(TaskDraft(title: ""))
        case .event:
            guard !calendars.isEmpty else { return }
            let hour = calendar.dateInterval(of: .hour, for: referenceDate)?.end ?? referenceDate
            candidate = .event(EventDraft(title: "", start: hour, end: hour.addingTimeInterval(3600)))
            writableCalendars = calendars
        }
        candidates = [candidate]
        eventCalendarOptions = calendars
        actions = PaletteActions.build(dateIntent: nil, candidates: candidates, lists: lists, calendars: calendars,
                                       isSearchable: false, referenceDate: referenceDate, calendar: calendar,
                                       format: timeFormat(), dates: dates())
        chosen = .action(item == .task ? .createTask : .createEvent)
        refine()
    }

    /// Esc on a Quick Add started empty (nothing typed in the field):
    /// closing it ends it — there's no list to fold back into.
    package var isCreatingWithoutQuery: Bool { isRefining && query.isEmpty }

    /// The palette is open for `query`: something typed, or Quick Add
    /// started empty (⌘N, ⇧⌘N).
    package func isOpen(query: String) -> Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isRefining
    }
}
