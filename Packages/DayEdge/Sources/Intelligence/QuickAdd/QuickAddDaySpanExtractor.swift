import Foundation

/// Spans of days and "all day" — what multi-day events need:
/// - weekdays: "fri-sun", "friday to sunday", "mon thru wed";
/// - day numbers with a month: "3-5 oct", "3–5 October", "oct 3-5";
/// - "from 3 oct to 5 oct", "3 oct - 5 oct", "from oct 3 to oct 5";
/// - weekends: "this weekend", "the weekend", "over the weekend",
///   "next weekend" (Saturday–Sunday);
/// - "all day".
/// The start is the draft's day; the end is `endDay`. Tasks use the start.
package struct DaySpanExtractor: QuickAddExtractor {
    package func extract(_ context: QuickAddContext) async -> [ParsedSpan] {
        let keys = context.tokens.map(\.key)
        var spans: [ParsedSpan] = []
        var index = 0
        while index < keys.count {
            if let (length, fact) = Self.match(keys, at: index, referenceDate: context.referenceDate, calendar: context.calendar) {
                spans.append(ParsedSpan(range: context.range(index, index + length - 1), fact: .temporal(fact),
                                        source: .builtInGrammar))
                index += length
            } else {
                index += 1
            }
        }
        return spans
    }

    package static func match(_ keys: [String], at index: Int, referenceDate: Date, calendar: Calendar) -> (Int, TemporalFact)? {
        let today = calendar.startOfDay(for: referenceDate)
        func key(_ offset: Int) -> String? { index + offset < keys.count ? keys[index + offset] : nil }

        // "all day"
        if keys[index] == "all", key(1) == "day" {
            var fact = TemporalFact()
            fact.isAllDay = true
            return (2, fact)
        }
        // Weekends: "this/next/the weekend", "over the weekend".
        var position = 0
        if key(0) == "over" { position += 1 }
        if let word = key(position), ["this", "next", "the"].contains(word), key(position + 1) == "weekend" {
            let next = word == "next"
            guard let weekend = weekend(next: next, from: referenceDate, calendar: calendar) else { return nil }
            // The interval ends at the midnight after Sunday.
            return (position + 2, span(weekend.start, weekend.end.addingTimeInterval(-1), calendar: calendar))
        }
        // "from <day> to <day>" / "<day> to <day>"
        let from = key(0) == "from" ? 1 : 0
        if let (first, used1) = day(keys, index + from, today: today, calendar: calendar) {
            let separator = index + from + used1
            if separator < keys.count, TimeSpanExtractor.rangeWords.contains(keys[separator]),
               let (second, used2) = day(keys, separator + 1, today: today, calendar: calendar, after: first) {
                return (from + used1 + 1 + used2, span(first.date, second.date, calendar: calendar))
            }
        }
        // Glued: "fri-sun", "3-5" + month, month + "3-5".
        if let result = gluedRange(keys, index, today: today, calendar: calendar) {
            return result
        }
        return nil
    }

    // MARK: - Pieces

    package struct Day {
        package var date: Date
        /// Only a weekday was given (the end follows the start's week).
        package var weekday: Int?
    }

    /// A weekday ("fri"), or a day number with a month ("3 oct", "oct 3",
    /// "3rd october"), and how many tokens it used. A weekday after
    /// `after` is the first such day from it on.
    package static func day(_ keys: [String], _ index: Int, today: Date, calendar: Calendar, after: Day? = nil) -> (Day, Int)? {
        guard index < keys.count else { return nil }
        if let weekday = QuickAddVocabulary.weekday(keys[index]) {
            let start = after?.date ?? today
            let date = (0...6).lazy.compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
                .first { calendar.component(.weekday, from: $0) == weekday }
            return date.map { (Day(date: $0, weekday: weekday), 1) }
        }
        if let number = dayNumber(keys[index]), index + 1 < keys.count, let month = QuickAddVocabulary.month(keys[index + 1]) {
            return dated(number, month, today: today, calendar: calendar, after: after?.date).map { (Day(date: $0), 2) }
        }
        if let month = QuickAddVocabulary.month(keys[index]), index + 1 < keys.count, let number = dayNumber(keys[index + 1]) {
            return dated(number, month, today: today, calendar: calendar, after: after?.date).map { (Day(date: $0), 2) }
        }
        return nil
    }

    /// "fri-sun"; "3-5 oct"; "oct 3-5".
    package static func gluedRange(_ keys: [String], _ index: Int, today: Date, calendar: Calendar) -> (Int, TemporalFact)? {
        func split(_ key: String) -> (String, String)? {
            for separator in ["–", "—", "-"] {
                let parts = key.components(separatedBy: separator)
                if parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty { return (parts[0], parts[1]) }
            }
            return nil
        }
        guard let (a, b) = split(keys[index]) else {
            // "oct 3-5"
            if let month = QuickAddVocabulary.month(keys[index]), index + 1 < keys.count,
               let (a, b) = split(keys[index + 1]), let first = dayNumber(a), let last = dayNumber(b), first < last,
               let start = dated(first, month, today: today, calendar: calendar),
               let end = dated(last, month, today: today, calendar: calendar, after: start) {
                return (2, span(start, end, calendar: calendar))
            }
            return nil
        }
        if QuickAddVocabulary.weekday(a) != nil, QuickAddVocabulary.weekday(b) != nil,
           let (start, _) = day([a], 0, today: today, calendar: calendar),
           let (end, _) = day([b], 0, today: today, calendar: calendar, after: start) {
            return (1, span(start.date, end.date, calendar: calendar))
        }
        // "3-5 oct"
        if let first = dayNumber(a), let last = dayNumber(b), first < last, index + 1 < keys.count,
           let month = QuickAddVocabulary.month(keys[index + 1]),
           let start = dated(first, month, today: today, calendar: calendar),
           let end = dated(last, month, today: today, calendar: calendar, after: start) {
            return (2, span(start, end, calendar: calendar))
        }
        return nil
    }

    package static func dayNumber(_ key: String) -> Int? {
        let digits = key.prefix { $0.isNumber }
        let suffix = key.dropFirst(digits.count)
        guard let value = Int(digits), (1...31).contains(value),
              suffix.isEmpty || ["st", "nd", "rd", "th"].contains(String(suffix)) else { return nil }
        return value
    }

    /// That day of that month — this year, or next if it's already past
    /// (or before `after`). Nil for a day the month doesn't have.
    package static func dated(_ day: Int, _ month: Int, today: Date, calendar: Calendar, after: Date? = nil) -> Date? {
        let year = calendar.component(.year, from: today)
        for candidate in [year, year + 1] {
            guard let date = calendar.date(from: DateComponents(year: candidate, month: month, day: day)),
                  calendar.component(.day, from: date) == day else { return nil }
            if date >= (after ?? today) { return calendar.startOfDay(for: date) }
        }
        return nil
    }

    package static func weekend(next: Bool, from referenceDate: Date, calendar: Calendar) -> DateInterval? {
        let current = calendar.isDateInWeekend(referenceDate) ? calendar.dateIntervalOfWeekend(containing: referenceDate) : nil
        guard let upcoming = current ?? calendar.nextWeekend(startingAfter: referenceDate) else { return nil }
        return next ? calendar.nextWeekend(startingAfter: upcoming.end) : upcoming
    }

    package static func span(_ start: Date, _ end: Date, calendar: Calendar) -> TemporalFact {
        var fact = TemporalFact(day: calendar.startOfDay(for: start))
        fact.endDay = calendar.startOfDay(for: end)
        return fact
    }
}
