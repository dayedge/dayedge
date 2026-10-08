import Foundation
import Domain

/// Which task or event a change tool means. A reference from earlier
/// results (`T3`, `E2`) is exact; anything else is a title, matched among
/// open tasks or nearby events. Several matches are listed back for the
/// model to ask the user — never guessed.
package enum AssistantTargetResolver {
    package enum Outcome<Target> {
        case found(Target)
        /// Text for the model: nothing found, or which ones match.
        case unresolved(String)
    }

    /// Events are searched this far around today when given by title.
    package static let eventSearchBack = 7
    package static let eventSearchAhead = 60

    // MARK: - Tasks

    package static func task(_ argument: String, includeCompleted: Bool = false,
                             context: AssistantToolContext) async -> Outcome<(task: TaskItem, list: CalendarSource?)> {
        let snapshot = await context.data.taskSnapshot()
        func found(_ task: TaskItem) -> Outcome<(task: TaskItem, list: CalendarSource?)> {
            .found((task, snapshot.lists.first { $0.id == task.listID }))
        }
        let text = argument.trimmingCharacters(in: .whitespacesAndNewlines)
        if let handle = handle(text, prefix: "T") {
            guard case .task(let reference)? = context.references.reference(for: handle) else {
                return .unresolved("There's no task \(handle) in this conversation. Use a task's reference from a result, or its title.")
            }
            guard let task = snapshot.tasks.first(where: { $0.id == reference.id }) else {
                return .unresolved("“\(reference.snapshot.title)” can't be found any more.")
            }
            return found(task)
        }
        let candidates = snapshot.tasks.filter { includeCompleted || !$0.isCompleted }
        let matches = titleMatches(text, in: candidates, title: \.title)
        switch matches.count {
        case 0: return .unresolved("No \(includeCompleted ? "" : "open ")task called “\(text)”. Check the title with list_tasks.")
        case 1: return found(matches[0])
        default:
            let lines = matches.prefix(8).map { context.taskLine($0, day: nil, list: snapshot.listName(for: $0)) }
            return .unresolved("Several tasks match “\(text)”:\n" + lines.joined(separator: "\n") + "\nAsk the user which one, then use its reference.")
        }
    }

    // MARK: - Events

    package static func event(_ argument: String, when: String?, context: AssistantToolContext) async throws -> Outcome<AgendaEventModel> {
        try Task.checkCancellation()
        let text = argument.trimmingCharacters(in: .whitespacesAndNewlines)
        let calendar = context.calendar
        if let handle = handle(text, prefix: "E") {
            guard case .event(let reference)? = context.references.reference(for: handle) else {
                return .unresolved("There's no event \(handle) in this conversation. Use an event's reference from a result, or its title.")
            }
            guard let event = try await AssistantEventLookup.event(id: reference.id, on: reference.day, context: context) else {
                return .unresolved("“\(reference.snapshot.title)” can't be found any more.")
            }
            return .found(event)
        }
        let range: DateInterval
        if let when, !when.isEmpty {
            range = try await AssistantWhen.resolve(when, context: context)
        } else {
            let today = calendar.startOfDay(for: context.now())
            range = DateInterval(
                start: calendar.date(byAdding: .day, value: -eventSearchBack, to: today) ?? today,
                end: calendar.date(byAdding: .day, value: eventSearchAhead, to: today) ?? today
            )
        }
        let matches = try await eventMatches(text, in: range, context: context)
        switch matches.count {
        case 0: return .unresolved("No event called “\(text)” \(AssistantFormat.period(range, calendar: calendar)). Check with find_events.")
        case 1: return .found(matches.items[0].event)
        default:
            let lines = matches.items.map { context.eventLine($0.event, day: $0.day, showsDay: true) }
            return .unresolved("Several events match “\(text)”:\n" + lines.joined(separator: "\n") + "\nAsk the user which one, then use its reference.")
        }
    }

    private static func eventMatches(_ text: String, in range: DateInterval,
                                     context: AssistantToolContext) async throws -> AssistantCandidates<EventDetailsTool.Occurrence> {
        let wanted = normalized(text)
        // One bounded group per tier; the best tier with any match wins.
        var tiers = Array(repeating: AssistantCandidates<EventDetailsTool.Occurrence>(), count: 3)
        var seen = Set<String>()
        if !wanted.isEmpty {
            try await AssistantEventLookup.scan(in: range, context: context) { section in
                for event in section.events where seen.insert(event.id).inserted {
                    if let tier = tier(of: normalized(event.title), for: wanted) {
                        tiers[tier].append(EventDetailsTool.Occurrence(event: event, day: section.date))
                    }
                }
            }
        }
        try Task.checkCancellation()
        return tiers.first { $0.count > 0 } ?? tiers[0]
    }

    // MARK: -

    /// "T3", "[[T3]]", "t3".
    package static func handle(_ text: String, prefix: Character) -> String? {
        let bare = text.trimmingCharacters(in: CharacterSet(charactersIn: "[] ")).uppercased()
        guard bare.first == prefix, bare.count > 1, bare.dropFirst().allSatisfy(\.isNumber) else { return nil }
        return bare
    }

    /// Exact titles first (ignoring case and accents), else titles that
    /// contain the text, else titles the text contains ("Dentist checkup"
    /// for "Dentist" — small models pass the new title too). The card
    /// always shows which one, so a loose match is never silent.
    package static func titleMatches<Item>(_ text: String, in items: [Item], title: KeyPath<Item, String>) -> [Item] {
        let wanted = normalized(text)
        guard !wanted.isEmpty else { return [] }
        let tiered = items.compactMap { item in tier(of: normalized(item[keyPath: title]), for: wanted).map { ($0, item) } }
        guard let best = tiered.map(\.0).min() else { return [] }
        return tiered.filter { $0.0 == best }.map(\.1)
    }

    /// 0: the same title; 1: a title containing the text; 2: a title the
    /// text contains (three letters or more). nil: no match.
    private static func tier(of candidate: String, for wanted: String) -> Int? {
        if candidate == wanted { return 0 }
        if candidate.contains(wanted) { return 1 }
        if candidate.count >= 3, wanted.contains(candidate) { return 2 }
        return nil
    }

    private static func normalized(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "“”\"'")))
    }
}
