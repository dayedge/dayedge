import Foundation
import Domain

/// Everything an extractor may need, shared by all of them.
package struct QuickAddContext: Sendable {
    package let text: String
    package let tokens: [QuickAddToken]
    package let lists: [QuickAddList]
    package let referenceDate: Date
    package let calendar: Calendar
    /// Calendars a "#name" can name (events); empty for tasks alone.
    package var calendars: [QuickAddList] = []

    /// The text from token `first` through token `last`.
    package func range(_ first: Int, _ last: Int) -> Range<String.Index> {
        tokens[first].range.lowerBound..<tokens[last].range.upperBound
    }

    package func keys(_ start: Int, count: Int) -> [String]? {
        guard start >= 0, start + count <= tokens.count else { return nil }
        return tokens[start..<start + count].map(\.key)
    }
}

/// One independent recognizer. It sees the whole input and returns every
/// piece it recognizes; overlaps between extractors are resolved later.
package protocol QuickAddExtractor: Sendable {
    func extract(_ context: QuickAddContext) async -> [ParsedSpan]
}

// MARK: - #list

package struct ListExtractor: QuickAddExtractor {
    package func extract(_ context: QuickAddContext) async -> [ParsedSpan] {
        context.tokens.compactMap { token in
            guard token.key.first == QuickAddVocabulary.listPrefix else { return nil }
            let name = token.key.dropFirst()
            guard !name.isEmpty else { return nil }
            // A list, a calendar, or both of that name; neither stays text.
            let list = context.lists.first { Self.matches($0.title, name) }
            let calendar = context.calendars.first { Self.matches($0.title, name) }
            guard list != nil || calendar != nil else { return nil }
            return ParsedSpan(range: token.range, fact: .tag(listID: list?.id, calendarID: calendar?.id), source: .explicitSyntax)
        }
    }

    /// Case- and space-insensitive: "#homeimprovement" finds "Home Improvement".
    package static func matches(_ title: String, _ name: Substring) -> Bool {
        let folded = title.lowercased(with: TemporalLanguage.matchingLocale).filter { !$0.isWhitespace }
        return folded == name
    }
}

// MARK: - Priority (! !! !!!, "high priority")

package struct PriorityExtractor: QuickAddExtractor {
    package func extract(_ context: QuickAddContext) async -> [ParsedSpan] {
        var spans: [ParsedSpan] = []
        for token in context.tokens where !token.text.isEmpty && token.text.allSatisfy({ $0 == "!" }) {
            guard let priority = QuickAddVocabulary.bangPriority[min(token.text.count, 3)] else { continue }
            spans.append(ParsedSpan(range: token.range, fact: .priority(priority), source: .explicitSyntax))
        }
        for (phrase, priority) in QuickAddVocabulary.priorityPhrases {
            for start in context.tokens.indices where context.keys(start, count: phrase.count) == phrase {
                spans.append(ParsedSpan(range: context.range(start, start + phrase.count - 1),
                                        fact: .priority(priority), source: .explicitSyntax))
            }
        }
        return spans
    }
}

// MARK: - Recurrence ("every Monday", "every 2 weeks", "monthly")

package struct RecurrenceExtractor: QuickAddExtractor {
    package typealias Rule = TaskRecurrenceRule

    package func extract(_ context: QuickAddContext) async -> [ParsedSpan] {
        var everySpans: [ParsedSpan] = []
        var wordSpans: [ParsedSpan] = []
        var index = 0
        while index < context.tokens.count {
            let key = context.tokens[index].key
            if let frequency = QuickAddVocabulary.recurrenceWords[key] {
                wordSpans.append(ParsedSpan(range: context.tokens[index].range,
                                            fact: .recurrence(Rule(frequency: frequency)), source: .explicitSyntax))
            } else if key == QuickAddVocabulary.every, let (rule, last) = parseEvery(after: index, context) {
                everySpans.append(ParsedSpan(range: context.range(index, last), fact: .recurrence(rule), source: .explicitSyntax))
                index = last
            }
            index += 1
        }
        // One rule per task: an "every …" rule wins; of two rule words the
        // last one is the rule and the earlier one a word of the title
        // ("daily standup weekly", "send weekly report daily").
        return everySpans.isEmpty ? Array(wordSpans.suffix(1)) : Array(everySpans.prefix(1))
    }

    // swiftlint:disable cyclomatic_complexity - one branch per explicit token kind
    /// After "every": day | weekday(s) | <weekday>[ and <weekday>…] |
    /// [N | other] <unit> [on the <ordinal>]. Returns the rule and the last
    /// token it used.
    private func parseEvery(after start: Int, _ context: QuickAddContext) -> (Rule, Int)? {
        let tokens = context.tokens
        var i = start + 1
        guard i < tokens.count else { return nil }

        if QuickAddVocabulary.weekdayWords.contains(tokens[i].key) {
            return (Rule(frequency: .weekly, weekdays: (2...6).map { .init(weekday: $0) }), i)
        }
        if QuickAddVocabulary.weekday(tokens[i].key) != nil {
            var days: [Rule.Weekday] = []
            var last = i
            while i < tokens.count {
                if let day = QuickAddVocabulary.weekday(tokens[i].key) {
                    days.append(.init(weekday: day)); last = i; i += 1
                } else if tokens[i].key == "and", i + 1 < tokens.count, QuickAddVocabulary.weekday(tokens[i + 1].key) != nil {
                    i += 1
                } else { break }
            }
            return (Rule(frequency: .weekly, weekdays: days), last)
        }

        // "every second Friday", "every other tue": every N weeks on that day.
        if let n = QuickAddVocabulary.everyNth[tokens[i].key], i + 1 < tokens.count,
           let day = QuickAddVocabulary.weekday(tokens[i + 1].key) {
            return (Rule(frequency: .weekly, interval: n, weekdays: [.init(weekday: day)]), i + 1)
        }

        var interval = 1
        if tokens[i].key == QuickAddVocabulary.other {
            interval = 2; i += 1
        } else if let (value, suffix) = QuickAddVocabulary.number(tokens[i].key), suffix.isEmpty, value > 0 {
            interval = value; i += 1
        }
        guard i < tokens.count, let frequency = QuickAddVocabulary.frequencyUnits[tokens[i].key] else { return nil }
        var rule = Rule(frequency: frequency, interval: interval)
        var last = i

        // "every month on the 1st" / "on the last"
        if frequency == .monthly, let words = context.keys(i + 1, count: 2), words == QuickAddVocabulary.onThe,
           i + 3 < tokens.count, let day = QuickAddVocabulary.ordinal(tokens[i + 3].key) {
            rule.daysOfMonth = [day]
            last = i + 3
            // "on the last day", "on the 1st day"
            if last + 1 < tokens.count, tokens[last + 1].key == "day" { last += 1 }
        }
        return (rule, last)
    }
    // swiftlint:enable cyclomatic_complexity
}

// MARK: - Alerts ("remind 15m before", "alert at due time")

package struct AlertExtractor: QuickAddExtractor {
    package func extract(_ context: QuickAddContext) async -> [ParsedSpan] {
        var spans: [ParsedSpan] = []
        let tokens = context.tokens
        for start in tokens.indices where QuickAddVocabulary.alertVerbs.contains(tokens[start].key) {
            var i = start + 1
            if i < tokens.count, QuickAddVocabulary.alertFiller.contains(tokens[i].key) { i += 1 }

            if context.keys(i, count: QuickAddVocabulary.atDueTime.count) == QuickAddVocabulary.atDueTime {
                let last = i + QuickAddVocabulary.atDueTime.count - 1
                spans.append(ParsedSpan(range: context.range(start, last), fact: .alert(.relative(minutesBefore: 0)), source: .explicitSyntax))
                continue
            }
            // N unit before | Nunit before
            guard i < tokens.count, let (value, suffix) = QuickAddVocabulary.number(tokens[i].key) else { continue }
            var unitKey = suffix
            if unitKey.isEmpty {
                i += 1
                guard i < tokens.count else { continue }
                unitKey = tokens[i].key
            }
            guard let minutesPerUnit = QuickAddVocabulary.durationUnits[unitKey],
                  i + 1 < tokens.count, tokens[i + 1].key == QuickAddVocabulary.before else { continue }
            spans.append(ParsedSpan(range: context.range(start, i + 1),
                                    fact: .alert(.relative(minutesBefore: value * minutesPerUnit)), source: .explicitSyntax))
        }
        return spans
    }
}

// MARK: - Kind (t:e, t:t)

/// "t:e", "t:event", "type:event" — and "t:t", "t:task", "type:task":
/// what the sentence should become, said outright (as search's `type:`).
package struct KindExtractor: QuickAddExtractor {
    package func extract(_ context: QuickAddContext) async -> [ParsedSpan] {
        context.tokens.compactMap { token in
            guard let colon = token.key.firstIndex(of: ":"), ["t", "type"].contains(String(token.key[..<colon])) else { return nil }
            let kind: QuickAddKind
            switch token.key[token.key.index(after: colon)...] {
            case "e", "event", "events": kind = .event
            case "t", "task", "tasks": kind = .task
            default: return nil
            }
            return ParsedSpan(range: token.range, fact: .kind(kind), source: .explicitSyntax)
        }
    }
}

// MARK: - Location (@Office, at Starbucks, in Room 4)

/// Where an event is:
/// - "@Office", "@\"Office, room 14\"" (quotes for several words);
/// - "at" / "in" followed by a quoted place, or by capitalised words
///   ("at Starbucks", "in Room 4", "at Bank of America").
/// Never a time or a date: "@10", "at 3pm", "in March", "at Friday" and
/// anything lowercase after at/in ("in 3 weeks", "at noon") stay dates.
package struct LocationExtractor: QuickAddExtractor {
    /// Words a number may follow inside a place ("Room 4", "Gate 12").
    package static let numbered: Set<String> = ["room", "building", "floor", "hall", "gate", "level", "office", "suite", "desk", "platform"]
    /// Lowercase words allowed between capitalised ones ("Bank of America").
    package static let joiners: Set<String> = ["of", "the", "and", "&", "de", "la", "van", "von"]

    package func extract(_ context: QuickAddContext) async -> [ParsedSpan] {
        let tokens = context.tokens
        var spans: [ParsedSpan] = []
        var index = 0
        while index < tokens.count {
            if let (last, place) = Self.place(tokens, at: index) {
                spans.append(ParsedSpan(range: context.range(index, last), fact: .location(place), source: .explicitSyntax))
                index = last + 1
            } else {
                index += 1
            }
        }
        return spans
    }

    // swiftlint:disable cyclomatic_complexity - one branch per explicit token kind
    /// A place starting at `index`: the last token it covers and its name.
    package static func place(_ tokens: [QuickAddToken], at index: Int) -> (Int, String)? {
        let text = tokens[index].text
        if text.hasPrefix("@") {
            let rest = String(text.dropFirst())
            if rest.isEmpty {
                // "@ "Office, room 14""
                return index + 1 < tokens.count ? quoted(tokens, from: index + 1, opening: tokens[index + 1].text) : nil
            }
            if rest.hasPrefix("\"") { return quoted(tokens, from: index, opening: rest) }
            let name = rest.trimmingCharacters(in: QuickAddVocabulary.edgePunctuation)
            guard !name.isEmpty, TimeSpanExtractor.parseClock(name.lowercased()) == nil else { return nil }
            return (index, name)
        }
        guard ["at", "in"].contains(tokens[index].key), index + 1 < tokens.count else { return nil }
        let next = tokens[index + 1]
        if next.text.hasPrefix("\"") { return quoted(tokens, from: index + 1, opening: next.text) }
        guard isPlaceWord(next) else { return nil }
        var last = index + 1
        var words = [clean(next.text)]
        var position = index + 2
        while position < tokens.count {
            let token = tokens[position]
            if tokens[position - 1].text.hasSuffix(",") { break }
            if isPlaceWord(token) {
                words.append(clean(token.text)); last = position
            } else if token.key.allSatisfy(\.isNumber), numbered.contains(tokens[position - 1].key) {
                words.append(token.text.trimmingCharacters(in: QuickAddVocabulary.edgePunctuation)); last = position
            } else if joiners.contains(token.key), position + 1 < tokens.count, isPlaceWord(tokens[position + 1]) {
                words.append(token.text)
            } else {
                break
            }
            position += 1
        }
        return (last, words.joined(separator: " "))
    }
    // swiftlint:enable cyclomatic_complexity

    /// Capitalised and not a date or time word ("Friday", "March", "Noon").
    package static func isPlaceWord(_ token: QuickAddToken) -> Bool {
        guard let first = token.text.first, first.isUppercase, first.isLetter else { return false }
        let key = token.key
        return TemporalWord(rawValue: key) == nil && QuickAddVocabulary.weekday(key) == nil
            && QuickAddVocabulary.month(key) == nil && !["noon", "midnight", "tonight", "tomorrow", "today"].contains(key)
    }

    /// The words between quotes, from `from` (whose text starts `opening`).
    package static func quoted(_ tokens: [QuickAddToken], from: Int, opening: String) -> (Int, String)? {
        var parts = [String(opening.drop { $0 == "\"" })]
        var last = from
        if !(opening.count > 1 && opening.hasSuffix("\"")) {
            var position = from + 1
            var closed = false
            while position < tokens.count {
                parts.append(tokens[position].text)
                last = position
                if tokens[position].text.hasSuffix("\"") { closed = true; break }
                position += 1
            }
            guard closed else { return nil }
        }
        let name = parts.joined(separator: " ").trimmingCharacters(in: CharacterSet(charactersIn: "\" "))
        return name.isEmpty ? nil : (last, name)
    }

    private static func clean(_ text: String) -> String {
        text.trimmingCharacters(in: CharacterSet(charactersIn: ",;:.!?()"))
    }
}
