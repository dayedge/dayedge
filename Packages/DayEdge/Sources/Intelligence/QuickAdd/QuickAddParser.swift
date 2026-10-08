import Foundation
import Domain

/// Sentence → `QuickAddDraft`, by extraction: every extractor looks at the
/// whole input, the recognized pieces are merged and removed, and the rest
/// is the title. Word order doesn't matter ("10 am next week send invoice"
/// = "send invoice next week at 10 am"). Deterministic and local.
package struct QuickAddParser: Sendable {
    package let explicitExtractors: [any QuickAddExtractor]
    package let temporalExtractors: [any QuickAddExtractor]

    package init(explicitExtractors: [any QuickAddExtractor] = [ListExtractor(), PriorityExtractor(), RecurrenceExtractor(), AlertExtractor(),
                                                        LocationExtractor(), KindExtractor()],
                 temporalExtractors: [any QuickAddExtractor] = [TemporalExtractor(), TimeSpanExtractor(), DaySpanExtractor(),
                                                        ChronoTemporalExtractor()]) {
        self.explicitExtractors = explicitExtractors
        self.temporalExtractors = temporalExtractors
    }

    package func parse(_ input: String, lists: [QuickAddList], calendars: [QuickAddList] = [], referenceDate: Date,
                       calendar: Calendar) async -> QuickAddDraft {
        // 1. Normalize: trim; a leading "+" forces a task.
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasForcePrefix = text.hasPrefix(QuickAddVocabulary.forcePrefix)
        if hasForcePrefix { text = String(text.dropFirst()).trimmingCharacters(in: .whitespaces) }

        var context = QuickAddContext(text: text, tokens: QuickAddToken.tokenize(text), lists: lists,
                                      referenceDate: referenceDate, calendar: calendar)
        context.calendars = calendars

        // 2. Every extractor sees the same whole text.
        var explicit: [ParsedSpan] = []
        for extractor in explicitExtractors { explicit += await extractor.extract(context) }
        // "t:t" forces a task as "+" does.
        let isForced = hasForcePrefix || explicit.contains { $0.fact == .kind(.task) }
        var temporal: [ParsedSpan] = []
        for extractor in temporalExtractors { temporal += await extractor.extract(context) }

        var draft = Self.assemble(text: text, context: context, explicit: explicit, temporal: temporal,
                                  referenceDate: referenceDate, calendar: calendar, isForced: isForced)
        if hasForcePrefix, draft.forcedKind == nil { draft.forcedKind = .task }
        // A one-word repeat that leaves nothing to do is the name ("daily
        // on 11 nov 11am" → "Daily" on 11 Nov at 11:00), when a date or time
        // says when.
        if draft.confidence == 0 {
            let named = explicit.filter { span in
                guard case .recurrence = span.fact else { return true }
                return context.tokens.filter { span.range.contains($0.range.lowerBound) }.count > 1
            }
            if named.count < explicit.count {
                var renamed = Self.assemble(text: text, context: context, explicit: named, temporal: temporal,
                                            referenceDate: referenceDate, calendar: calendar, isForced: isForced)
                if hasForcePrefix, renamed.forcedKind == nil { renamed.forcedKind = .task }
                if renamed.confidence > 0, renamed.startTime != nil || renamed.day != nil { return renamed }
            }
        }
        return draft
    }

    // swiftlint:disable:next cyclomatic_complexity function_parameter_count - the parse pipeline: each stage and its inputs, labelled at the call
    private static func assemble(text: String, context: QuickAddContext, explicit: [ParsedSpan], temporal: [ParsedSpan],
                                 referenceDate: Date, calendar: Calendar, isForced: Bool) -> QuickAddDraft {
        // 3. Overlaps: explicit syntax wins ("every Monday" is a repeat, not
        // a date; "remind 15m before" is an alert). Temporal pieces may
        // overlap each other — they are merged, not chosen between.
        let accepted = Self.nonOverlapping(explicit.sorted { Self.length($0, in: text) > Self.length($1, in: text) })
        // A chrono piece within one of our grammar's matches (the same
        // words or fewer) adds nothing but a misreading: "next month 12"
        // read as the 1st at noon.
        let grammar = temporal.filter { $0.source == .builtInGrammar }
        let temporal = temporal.filter { span in
            !accepted.contains { $0.overlaps(span) }
                && (span.source == .builtInGrammar || !grammar.contains { Self.covers($0, span) })
        }
        let spans = (accepted + temporal).sorted { $0.range.lowerBound < $1.range.lowerBound }

        // 4. Merge.
        var draft = QuickAddDraft(title: "", confidence: 0, spans: spans)
        for span in accepted {
            switch span.fact {
            case .tag(let listID, let calendarID):
                draft.listID = listID ?? draft.listID
                draft.calendarID = calendarID ?? draft.calendarID
            case .location(let place): draft.location = place
            case .kind(let kind): draft.forcedKind = kind
            case .priority(let priority): if priority.rawValue > draft.priority.rawValue { draft.priority = priority }
            case .recurrence(let rule): draft.recurrence = rule
            case .alert(let alert): draft.alert = alert
            case .temporal, .forceTask: break
            }
        }
        Self.mergeTemporal(temporal, into: &draft, calendar: calendar)
        if draft.day == nil, let rule = draft.recurrence {
            draft.day = Self.firstOccurrence(of: rule, from: referenceDate, calendar: calendar)
        }
        // A time with no day: today if it's still ahead, else tomorrow.
        if draft.day == nil, let start = draft.startTime, let hour = start.hour {
            let today = calendar.startOfDay(for: referenceDate)
            let at = calendar.date(bySettingHour: hour, minute: start.minute ?? 0, second: 0, of: today) ?? today
            draft.day = at >= referenceDate ? today : calendar.date(byAdding: .day, value: 1, to: today)
        }

        // 5. Title: what nothing recognized. A task keeps the event-only
        // pieces ("pick up parcel at Post Office") — it has no place field.
        let eventOnly = accepted.filter { span in
            switch span.fact {
            case .location: true
            case .tag(let listID, let calendarID): listID == nil && calendarID != nil
            default: false
            }
        }
        let leftover = Self.leftoverTokens(context.tokens, consumed: spans.filter { !eventOnly.contains($0) }.map(\.range),
                                           kept: eventOnly.map(\.range))
        draft.title = Self.title(from: leftover)
        draft.eventTitle = eventOnly.isEmpty ? draft.title
            : Self.title(from: Self.leftoverTokens(context.tokens, consumed: spans.map(\.range)))
        let keys = context.tokens.map(\.key)
        draft.saysTask = keys.first.map(QuickAddVocabulary.todoWords.contains) == true
            || keys.indices.contains { keys[$0...].starts(with: ["remind", "me", "to"]) }

        // 6. Is this a task at all?
        draft.confidence = Self.confidence(leftover: leftover, draft: draft, hasTemporal: !temporal.isEmpty, isForced: isForced)
        return draft
    }

    // MARK: - Overlaps

    /// `outer` spans all of `inner` (the same words included).
    private static func covers(_ outer: ParsedSpan, _ inner: ParsedSpan) -> Bool {
        outer.range.lowerBound <= inner.range.lowerBound && inner.range.upperBound <= outer.range.upperBound
    }

    private static func length(_ span: ParsedSpan, in text: String) -> Int {
        text.distance(from: span.range.lowerBound, to: span.range.upperBound)
    }

    private static func nonOverlapping(_ spans: [ParsedSpan]) -> [ParsedSpan] {
        var result: [ParsedSpan] = []
        for span in spans where !result.contains(where: { $0.overlaps(span) }) { result.append(span) }
        return result
    }

    // MARK: - Temporal merge

    /// Time: from the first piece that has one (with its range end). Day:
    /// the most specific trusted one — a week narrowed by a weekday
    /// ("next week … Friday"), else a day (the app's grammar first, then a
    /// certain chrono day), else a week / month start, else chrono's
    /// uncertain guess (e.g. the date under a lone "10 am").
    package static func mergeTemporal(_ spans: [ParsedSpan], into draft: inout QuickAddDraft, calendar: Calendar) {
        let facts: [TemporalEntry] = spans.compactMap {
            if case .temporal(let fact) = $0.fact { return TemporalEntry(fact: fact, source: $0.source, confidence: $0.confidence) }
            return nil
        }
        // A time we read ourselves first (our afternoon rule, ranges,
        // durations), then chrono's, and a part of the day ("morning")
        // only when nothing stated a time.
        let timedFacts = facts.filter { $0.fact.start != nil }
        if let timed = (timedFacts.first { $0.source == .builtInGrammar && !$0.fact.isApproximate }
                        ?? timedFacts.first { !$0.fact.isApproximate }
                        ?? timedFacts.first)?.fact {
            draft.startTime = timed.start
            draft.endTime = timed.end
            draft.duration = timed.duration
        }
        draft.isAllDay = facts.contains { $0.fact.isAllDay }
        // A span of days ("fri-sun") sets both ends — it was said outright.
        if let span = facts.first(where: { $0.fact.endDay != nil })?.fact, let start = span.day {
            draft.day = start
            draft.endDay = span.endDay
            if draft.startTime == nil { draft.isAllDay = true }
            return
        }

        let week = facts.first { $0.fact.granularity == .week }?.fact.day
        let weekday = facts.lazy.compactMap { entry -> Int? in
            if case .weekday(let number) = entry.fact.granularity { return number }
            return nil
        }.first
        if let week, let weekday {
            let offset = (weekday - calendar.component(.weekday, from: week) + 7) % 7
            draft.day = calendar.date(byAdding: .day, value: offset, to: week)
            return
        }

        func isDay(_ granularity: TemporalGranularity) -> Bool {
            if case .week = granularity { return false }
            if case .month = granularity { return false }
            if case .year = granularity { return false }
            return true
        }
        let trusted = facts.filter { $0.confidence >= 1 && $0.fact.day != nil }
        let ranked = trusted.filter { $0.source == .builtInGrammar && isDay($0.fact.granularity) }
            + trusted.filter { $0.source != .builtInGrammar && isDay($0.fact.granularity) }
            + trusted.filter { !isDay($0.fact.granularity) }
            + facts.filter { $0.confidence < 1 && $0.fact.day != nil }
        draft.day = ranked.first?.fact.day.map { calendar.startOfDay(for: $0) }
    }

    /// A repeat with no date starts at its first occurrence from today
    /// ("pay rent every month on the 1st" → the next 1st).
    package static func firstOccurrence(of rule: TaskRecurrenceRule, from referenceDate: Date, calendar: Calendar) -> Date? {
        let today = calendar.startOfDay(for: referenceDate)
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: today) else { return today }
        // Only a rule that names its days narrows the start; "daily",
        // "weekly" etc. start today.
        guard !rule.weekdays.isEmpty || !rule.daysOfMonth.isEmpty || !rule.months.isEmpty else { return today }
        var day = today
        for _ in 0..<400 {
            if rule.occurs(on: day, startingAt: yesterday, calendar: calendar) { return day }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return nil
    }

    // MARK: - Title

    /// Tokens nothing recognized, minus glue words that belonged to a
    /// removed piece ("… at [10 am]", "[next week] on [Friday]").
    /// `kept` pieces stay whole: their "at" ("1pm at Starbucks") is theirs.
    package static func leftoverTokens(_ tokens: [QuickAddToken], consumed ranges: [Range<String.Index>],
                                       kept: [Range<String.Index>] = []) -> [QuickAddToken] {
        var isConsumed = tokens.map { token in ranges.contains { $0.overlaps(token.range) } }
        let isKept = tokens.map { token in kept.contains { $0.overlaps(token.range) } }
        var changed = true
        while changed {
            changed = false
            for index in tokens.indices where !isConsumed[index] && !isKept[index]
                && QuickAddVocabulary.connectors.contains(tokens[index].key) {
                let touches = (index > 0 && isConsumed[index - 1]) || (index + 1 < tokens.count && isConsumed[index + 1])
                if touches { isConsumed[index] = true; changed = true }
            }
        }
        return tokens.indices.filter { !isConsumed[$0] }.map { tokens[$0] }
    }

    package static func title(from tokens: [QuickAddToken]) -> String {
        let joined = tokens.map(\.text).joined(separator: " ")
            .trimmingCharacters(in: QuickAddVocabulary.edgePunctuation.union(.whitespaces))
        guard let first = joined.first else { return "" }
        return first.uppercased() + joined.dropFirst()
    }

    // MARK: - Confidence

    package static let meaningfulTitleWeight = 0.4
    package static let temporalWeight = 0.25
    package static let explicitWeight = 0.25
    package static let taskVerbWeight = 0.2

    /// A task needs something to do: at least one real word left over (not
    /// glue, not a date word). Then signals add up: a date, explicit task
    /// syntax, a to-do verb. "next week" alone leaves nothing — it stays
    /// navigation; "Work" alone is a word with no signals — it stays search.
    package static func confidence(leftover: [QuickAddToken], draft: QuickAddDraft, hasTemporal: Bool, isForced: Bool) -> Double {
        let meaningful = leftover.filter { token in
            token.key.contains(where: \.isLetter)
                && !QuickAddVocabulary.connectors.contains(token.key)
                && TemporalWord(rawValue: token.key) == nil
        }
        guard !meaningful.isEmpty else { return 0 }
        if isForced { return 1 }
        var score = meaningfulTitleWeight
        if hasTemporal { score += temporalWeight }
        if draft.listID != nil || draft.priority != .none || draft.recurrence != nil || draft.alert != nil { score += explicitWeight }
        if meaningful.contains(where: { QuickAddVocabulary.taskVerbs.contains($0.key) }) { score += taskVerbWeight }
        return min(score, 1)
    }
}

/// A date or time the parser found, where and how surely.
private struct TemporalEntry {
    let fact: TemporalFact
    let source: ParseSource
    let confidence: Double
}
