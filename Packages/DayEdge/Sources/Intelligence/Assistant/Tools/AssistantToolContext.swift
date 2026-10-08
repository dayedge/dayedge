import Foundation
import Domain

/// Everything the tools share: where data comes from, the calendar and
/// clock, and the date parser — all injectable for tests.
package struct AssistantToolContext: Sendable {
    package let data: any AssistantDataSource
    package var calendar: Calendar = .autoupdatingCurrent
    package var now: @Sendable () -> Date = { Date() }
    package var parseDate: @Sendable (String, Date, Calendar) async -> SearchIntent = Self.liveParseDate
    /// Short handles for the objects this conversation's tools return.
    package var references = ChatReferenceRegistry()
    /// Whether items carry references (`[[E1]]`) for the model to show.
    /// Off for models that don't follow that contract (on-device).
    package var showsReferences = true
    /// Longest answer a tool gives, in lines. On-device models have a small
    /// context window; a capped list says how many were left out.
    package var maxLines = 30
    /// Where a change is approved (the conversation's card). No change tools
    /// without it.
    package var approvals: ChatApprovals?
    /// What performs an approved change.
    package var changes: (any AssistantChangeWriter)?
    /// "Always allow" is offered — remote models only.
    package var offersAlwaysAllow = false

    /// The app's date parsing (`SearchIntentPipeline.live`).
    package static let liveParseDate: @Sendable (String, Date, Calendar) async -> SearchIntent = { text, now, calendar in
        await SearchIntentPipeline.live.resolve(text, referenceDate: now, calendar: calendar)
    }

    package init(data: any AssistantDataSource, calendar: Calendar = .autoupdatingCurrent,
                 now: @escaping @Sendable () -> Date = { Date() },
                 parseDate: @escaping @Sendable (String, Date, Calendar) async -> SearchIntent = Self.liveParseDate,
                 references: ChatReferenceRegistry = ChatReferenceRegistry(), showsReferences: Bool = true, maxLines: Int = 30,
                 approvals: ChatApprovals? = nil, changes: (any AssistantChangeWriter)? = nil, offersAlwaysAllow: Bool = false,
                 isCompact: Bool = false, timeFormat: @escaping @Sendable () -> TimeFormat = { .twentyFourHour }) {
        self.data = data
        self.calendar = calendar
        self.now = now
        self.parseDate = parseDate
        self.references = references
        self.showsReferences = showsReferences
        self.maxLines = maxLines
        self.approvals = approvals
        self.changes = changes
        self.offersAlwaysAllow = offersAlwaysAllow
        self.isCompact = isCompact
        self.timeFormat = timeFormat
    }
    /// The on-device model's 4K context: change tools describe themselves in
    /// a line and take only their essential arguments (measured: the full
    /// set overflows it).
    package var isCompact = false
    /// How times on approval cards and receipts are written — the user's
    /// setting in the app; 24-hour in tests.
    package var timeFormat: @Sendable () -> TimeFormat = { .twentyFourHour }
}

extension AssistantToolContext {
    /// The full description, or the short one for a compact model.
    package func brief(_ full: String, _ short: String) -> String { isCompact ? short : full }

    /// Essential parameters always; the rest only for capable models.
    package func parameters(_ essential: [AssistantTool.Parameter], optional: [AssistantTool.Parameter] = []) -> [AssistantTool.Parameter] {
        isCompact ? essential : essential + optional
    }
}

extension AssistantToolContext {
    /// "[[E1]] event 09:00–09:30 Standup · Work" — the handle first, so a
    /// model that copies the line still produces a reference.
    package func eventLine(_ event: AgendaEventModel, day: Date, showsDay: Bool = false) -> String {
        let start = calendar.startOfDay(for: day)
        let when = showsDay ? "\(AssistantFormat.shortDay(start, calendar: calendar)) " : ""
        return marker(for: .event(ChatEventReference(
            id: event.id, day: start,
            snapshot: ChatObjectSnapshot(title: event.title, detail: AssistantFormat.timeRange(event))
        ))) + "event \(when)\(AssistantFormat.event(event))"
    }

    /// "[[T1]] task Send invoice · due 10:00 · Work". `day` is the day this
    /// occurrence belongs to; nil for a task listed without one.
    package func taskLine(_ task: TaskItem, day: Date?, list: String?, showsDay: Bool = true) -> String {
        let now = now()
        let owner = calendar.startOfDay(for: day ?? task.dueDate ?? now)
        return marker(for: .task(ChatTaskReference(
            id: task.id, day: owner,
            snapshot: ChatObjectSnapshot(title: task.title, detail: task.dueDate.map { "due \(AssistantFormat.shortDay($0, calendar: calendar))" })
        ))) + "task \(AssistantFormat.task(task, list: list, now: now, calendar: calendar, showsDay: showsDay))"
    }

    /// "[[D1]] Thursday 24 December 2026 · Christmas Eve (public holiday)" —
    /// a day the model can show as a native date. Without references, just
    /// the text.
    package func dayLine(_ day: Date, holidays: AssistantHolidays, text: String) -> String {
        guard showsReferences else { return text }
        let start = calendar.startOfDay(for: day)
        let holiday = holidays.name(for: start, calendar: calendar)
        let handle = references.handle(for: .day(ChatDayReference(
            day: start, label: holiday, isHoliday: holiday != nil, isWeekend: holidays.isWeekend(start, calendar: calendar)
        )))
        return ChatReferenceRegistry.token(handle) + " " + text
    }

    /// A tool's answer listing items: capped, and — when references are on —
    /// closed with how to show them.
    package func listing(_ lines: [String]) -> String {
        var listing = AssistantListing(maxLines: maxLines)
        for line in lines { listing.append(line) }
        return self.listing(listing)
    }

    /// "[[E1]] " with references on, "- " without.
    private func marker(for reference: ChatObjectReference) -> String {
        guard showsReferences else { return "- " }
        return ChatReferenceRegistry.token(references.handle(for: reference)) + " "
    }
}
