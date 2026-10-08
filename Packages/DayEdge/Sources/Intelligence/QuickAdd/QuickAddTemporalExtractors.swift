import Foundation

/// The app's own date grammar, applied to every short run of words: each
/// window of 1–4 tokens goes through the same `TemporalQueryNormalizer`
/// (aliases, spelling — "frida" → "friday") and `TemporalIntentParser` the
/// search field uses for complete queries, so app-specific meanings ("next
/// week" = its Monday) come for free and stay identical. The longest match
/// at each position wins.
package struct TemporalExtractor: QuickAddExtractor {
    /// "the 3rd of next month" is five words.
    package static let maxWindow = 5
    package let normalizer: TemporalQueryNormalizer

    package init(normalizer: TemporalQueryNormalizer = .init()) {
        self.normalizer = normalizer
    }

    package func extract(_ context: QuickAddContext) async -> [ParsedSpan] {
        var spans: [ParsedSpan] = []
        var start = 0
        while start < context.tokens.count {
            var matched = false
            for length in stride(from: min(Self.maxWindow, context.tokens.count - start), through: 1, by: -1) {
                let window = context.tokens[start..<start + length]
                // The grammar is words — plus numbers for its numeric
                // phrases ("next month 12", "in 3 weeks", "week 42 2027",
                // "+10 days"); anything else is chrono's.
                let isWord = { (key: String) in !key.isEmpty && key.allSatisfy(\.isLetter) }
                let others = window.filter { !isWord($0.key) }
                guard others.count <= 2, others.allSatisfy({ Self.isNumberWord($0.key) }) else { continue }
                let normalized = normalizer.normalize(window.map(\.key).joined(separator: " ")).normalized
                guard let intent = TemporalIntentParser().resolve(normalized, referenceDate: context.referenceDate, calendar: context.calendar),
                      let fact = Self.fact(for: intent, words: normalized) else { continue }
                spans.append(ParsedSpan(range: context.range(start, start + length - 1), fact: .temporal(fact), source: .builtInGrammar))
                start += length
                matched = true
                break
            }
            if !matched { start += 1 }
        }
        return spans
    }

    /// "12", "12th", "3rd", "+10", "-2", "+", "2027" — numbers the grammar's
    /// numeric phrases use (it decides whether they make a date).
    package static func isNumberWord(_ key: String) -> Bool {
        if key == "+" || key == "-" || TemporalIntentParser.spelledNumbers[key] != nil { return true }
        var body = Substring(key)
        if body.first == "+" || body.first == "-" { body = body.dropFirst() }
        let digits = body.prefix { $0.isNumber }
        let suffix = body.dropFirst(digits.count)
        return !digits.isEmpty && (suffix.isEmpty || ["st", "nd", "rd", "th"].contains(String(suffix)))
    }

    /// How specific the match is, read from its own words: a lone weekday
    /// can be narrowed by a week ("next week … Friday"), a week or month is
    /// a period, anything with a weekday or day word is a day.
    package static func fact(for intent: SearchIntent, words normalized: String) -> TemporalFact? {
        let tokens = normalized.split(separator: " ").map(String.init)
        let words = tokens.compactMap { TemporalWord(rawValue: $0) }
        let hasNumber = tokens.contains { isNumberWord($0) }
        switch intent {
        case .jumpToDate(let date) where hasNumber:
            // "week 42" is a week (a weekday can narrow it); "in 3 weeks",
            // "next month 12" are exact days.
            return TemporalFact(day: date, granularity: tokens.first == "week" ? .week : .day)
        case .jumpToDate(let date):
            if words.count == 1, let weekday = words[0].calendarWeekday {
                return TemporalFact(day: date, granularity: .weekday(weekday))
            }
            if words.contains(where: { $0.calendarWeekday != nil }) { return TemporalFact(day: date, granularity: .day) }
            if words.contains(.week) || words.contains(.weekend) { return TemporalFact(day: date, granularity: .week) }
            return TemporalFact(day: date, granularity: .day)
        case .jumpToMonth(let date):
            return TemporalFact(day: date, granularity: words.contains(.year) ? .year : .month)
        case .freeTextSearch:
            return nil
        }
    }
}

/// chrono.js over the whole sentence: every date/time it finds, with where.
/// Only what chrono is certain of is taken as-is; an uncertain day ("next
/// week" → some Wednesday) is kept at low confidence, as a last resort.
package struct ChronoTemporalExtractor: QuickAddExtractor {
    package static let uncertainDayConfidence = 0.5

    package func extract(_ context: QuickAddContext) async -> [ParsedSpan] {
        let found = await ChronoEngine.shared.spans(in: context.text, referenceDate: context.referenceDate)
        return found.compactMap { span in
            guard let range = Self.range(of: span, in: context.text) else { return nil }
            var fact = TemporalFact()
            if let day = context.calendar.date(from: DateComponents(year: span.date.year, month: span.date.month, day: span.date.day)) {
                fact.day = context.calendar.startOfDay(for: day)
            }
            if span.isTimeCertain { fact.start = DateComponents(hour: span.date.hour, minute: span.date.minute) }
            fact.end = span.end
            return ParsedSpan(range: range, fact: .temporal(fact), source: .chrono,
                              confidence: span.isDayCertain ? 1 : Self.uncertainDayConfidence)
        }
    }

    /// chrono counts UTF-16 units; trims the whitespace it sometimes includes.
    package static func range(of span: ChronoSpan, in text: String) -> Range<String.Index>? {
        let utf16 = text.utf16
        guard let lower = utf16.index(utf16.startIndex, offsetBy: span.utf16Offset, limitedBy: utf16.endIndex),
              let upper = utf16.index(lower, offsetBy: span.utf16Length, limitedBy: utf16.endIndex) else { return nil }
        var start = lower, end = upper
        while start < end, text[start].isWhitespace { start = text.index(after: start) }
        while end > start, text[text.index(before: end)].isWhitespace { end = text.index(before: end) }
        return start < end ? start..<end : nil
    }
}
