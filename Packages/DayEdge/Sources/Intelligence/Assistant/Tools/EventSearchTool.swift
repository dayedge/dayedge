import Foundation
import Domain

/// `find_events`: the search field's search, for the model — the same
/// words and operators (`subject`, `from` incl. "me", `with`, `type`,
/// `day`, `before`, `after`, `between`) over the whole index, events and
/// tasks. Arguments become an operator query resolved exactly as typed
/// ones are; `when` (a period) narrows further. The nearest matches are
/// listed (upcoming soonest, then the most recent past) with the total.
/// `order: newest` lists what was added most recently instead (within
/// `when`, default the next 30 days), one line per repeating series.
package enum EventSearchTool {
    package static let maxListed = 25
    /// Events read for `order: newest` (it sorts by when they were added).
    package static let newestCandidates = 300
    package static let newestDefaultWhen = "next 30 days"

    package enum Order: String, CaseIterable {
        case date, newest
    }

    package static func make(_ context: AssistantToolContext) -> AssistantTool {
        .answering(
            name: "find_events",
            description: context.brief(
                "Search the user's events and tasks like the app's search field: words anywhere (title, place, notes, people), "
                    + "or narrowed by title, organizer, attendee, type and dates. Any time unless dates are given.",
                "Search events and tasks: by words, title, organizer, attendee, type, dates."),
            parameters: context.parameters([
                .init(name: "text", kind: .string, description: "Words to find anywhere, e.g. 'dentist' or a person's name.",
                      isRequired: false),
                .init(name: "subject", kind: .string, description: "Words that must be in the title.", isRequired: false),
                .init(name: "from", kind: .string, description: "Who organized it (name or email); 'me' for the user's own.",
                      isRequired: false),
                .init(name: "with", kind: .string,
                      description: "Someone taking part (name or email) — for 'meetings with Anna'. Always set when a person is named.",
                      isRequired: false),
                .init(name: "type", kind: .string, description: "event or task; both if left out.", isRequired: false,
                      enumValues: ["event", "task"]),
                .init(name: "when", kind: .string, description: "A period: \(AssistantWhen.accepted). Any time if left out.",
                      isRequired: false)
            ], optional: [
                .init(name: "day", kind: .string, description: "One day: 'today', 'friday', '2026-10-15'.", isRequired: false),
                .init(name: "after", kind: .string, description: "On or after this day.", isRequired: false),
                .init(name: "before", kind: .string, description: "Before this day.", isRequired: false),
                .init(name: "between", kind: .string, description: "Two days, both included: '2026-09-01..2026-09-30'.",
                      isRequired: false),
                .init(name: "order", kind: .string, description: "date (default) or newest: most recently added first.",
                      isRequired: false, enumValues: Order.allCases.map(\.rawValue))
            ])
        ) { arguments in
            let order = arguments.optionalString("order").flatMap(Order.init) ?? .date
            let query = operatorQuery(arguments)
            var parts = await SearchQueryResolver.resolve(query, referenceDate: context.now(), calendar: context.calendar)
            if let when = arguments.optionalString("when") ?? (order == .newest ? newestDefaultWhen : nil) {
                let period = try await AssistantWhen.resolve(when, context: context)
                parts.interval = parts.interval.map { $0.intersection(with: period) ?? DateInterval(start: .distantPast, duration: 0) }
                    ?? period
                parts.hasExplicitDate = true
                parts.label = [parts.label, AssistantFormat.period(period, calendar: context.calendar)].compactMap { $0 }
                    .joined(separator: " · ")
            }
            return await answer(parts, order: order, context: context)
        }
    }

    /// The arguments as the search field would read them.
    package static func operatorQuery(_ arguments: AssistantToolArguments) -> String {
        let operators: [(String, SearchOperator)] = [("subject", .subject), ("from", .from), ("with", .with), ("type", .type),
                                                     ("day", .day), ("after", .after), ("before", .before), ("between", .between)]
        let terms = operators.compactMap { name, op -> String? in
            guard let value = arguments.optionalString(name)?.replacingOccurrences(of: "\"", with: "")
                .trimmingCharacters(in: .whitespaces), !value.isEmpty else { return nil }
            return op.key + SearchQuerySyntax.quoted(value)
        }
        return ([arguments.optionalString("text") ?? ""] + terms).joined(separator: " ").trimmingCharacters(in: .whitespaces)
    }

    package static func answer(_ parts: SearchQueryParts, order: Order = .date, context: AssistantToolContext) async -> String {
        guard parts.isSearchable || order == .newest else {
            return "Say what to look for: words, a title, a person or dates."
        }
        let now = context.now()
        let calendar = context.calendar
        let events = parts.includesEvents
            ? await context.data.searchEvents(parts, limit: order == .newest ? newestCandidates : maxListed, now: now, calendar: calendar)
            : AssistantEventSearch(total: 0, items: [])
        let snapshot = parts.includesTasks && order == .date ? await context.data.taskSnapshot() : nil
        let tasks = (snapshot?.tasks ?? []).filter { SearchSession.matches($0, parts) }

        var lines: [String]
        if order == .newest {
            // Newest first; a repeating series once.
            var seen = Set<String>()
            lines = events.items
                .filter { seen.insert(seriesKey($0.event)).inserted }
                .sorted { ($0.event.createdAt ?? .distantPast) > ($1.event.createdAt ?? .distantPast) }
                .prefix(maxListed)
                .map { item in
                    let line = context.eventLine(item.event, day: item.day, showsDay: true)
                    return item.event.createdAt.map { line + " · added \(AssistantFormat.date($0, calendar: calendar))" } ?? line
                }
        } else {
            let shownTasks = AssistantEventSearch.nearest(tasks, start: { $0.dueDate ?? .distantFuture }, limit: maxListed,
                                                          now: now, calendar: calendar)
            lines = events.items.map { context.eventLine($0.event, day: $0.day, showsDay: true) }
                + shownTasks.map { context.taskLine($0, day: $0.dueDate, list: snapshot?.listName(for: $0)) }
        }

        let total = events.total + tasks.count
        let what = describe(parts)
        guard !lines.isEmpty else { return "Nothing matches \(what)." }
        let hasWords = !parts.text.isEmpty || parts.subject != nil
        let heading = order == .newest
            ? "Events \(hasWords ? "matching" : "in") \(what), most recently added first:"
            : total > lines.count
                ? "\(total) match \(what); the \(lines.count) nearest to today:"
                : "\(total) \(total == 1 ? "match" : "matches") \(what):"
        return context.listing([heading] + lines)
    }

    /// "“dentist” · from anna · next week".
    private static func describe(_ parts: SearchQueryParts) -> String {
        let words = [parts.text, parts.subject.map { "title “\($0)”" }].compactMap { $0 }.filter { !$0.isEmpty }
        let text = words.first.map { $0.hasPrefix("title") ? $0 : "“\($0)”" }
        let rest = words.dropFirst().map { $0 }
        return ([text].compactMap { $0 } + rest + [parts.label].compactMap { $0 }).joined(separator: " · ")
    }

    /// One key per repeating series (same title and creation), per event otherwise.
    private static func seriesKey(_ event: AgendaEventModel) -> String {
        guard event.isRecurring else { return event.id }
        return "\(event.title)|\(event.createdAt?.timeIntervalSinceReferenceDate ?? 0)"
    }
}
