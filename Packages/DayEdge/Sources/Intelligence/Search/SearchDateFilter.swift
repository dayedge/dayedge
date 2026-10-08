import Foundation
import Domain

/// A date phrase inside plain search words: "refinement last March" →
/// "refinement" in March; "standup tomorrow" → "standup" tomorrow.
package enum SearchDateFilter {
    /// Chrono finds the date phrase; only one it's sure of (a day, or a
    /// month) becomes the range.
    package static func parse(_ query: String, referenceDate: Date, calendar: Calendar) async -> SearchQueryParts {
        let spans = await ChronoEngine.shared.spans(in: query, referenceDate: referenceDate)
        return split(query, spans: spans, referenceDate: referenceDate, calendar: calendar)
    }

    package static func split(_ query: String, spans: [ChronoSpan], referenceDate: Date, calendar: Calendar,
                              dates: DatePresentationFormatter = .current) -> SearchQueryParts {
        let utf16 = Array(query.utf16)
        for span in spans where span.isDayCertain || span.isMonthCertain {
            var start = span.utf16Offset
            let end = span.utf16Offset + span.utf16Length
            guard start >= 0, end <= utf16.count, isBoundary(utf16, start), isBoundary(utf16, end) else { continue }
            var span = span
            if !span.isDayCertain {
                // Chrono reads "last March" as just "March", the next one.
                // A month means this year's, or the one "last" / "next" says.
                let (modifier, modifierStart) = precedingWord(utf16, before: start)
                span = monthSpan(span, modifier: modifier, referenceDate: referenceDate, calendar: calendar)
                if modifier != nil { start = modifierStart }
            }
            guard let interval = interval(for: span, calendar: calendar) else { continue }
            let rest = String(utf16CodeUnits: Array(utf16[..<start]) + [32] + Array(utf16[end...]), count: utf16.count - (end - start) + 1)
            let text = rest.components(separatedBy: .whitespaces).filter { !$0.isEmpty }.joined(separator: " ")
            return SearchQueryParts(text: text, interval: interval, label: label(for: span, interval: interval, calendar: calendar, dates: dates))
        }
        return .plain(query)
    }

    private static let modifiers: Set<String> = ["last", "past", "previous", "this", "next", "coming"]

    /// A modifier word right before `index` ("last "), and where it starts.
    private static func precedingWord(_ utf16: [UInt16], before index: Int) -> (String?, Int) {
        var end = index
        while end > 0, utf16[end - 1] == 32 { end -= 1 }
        var start = end
        while start > 0, let scalar = Unicode.Scalar(utf16[start - 1]), CharacterSet.letters.contains(scalar) { start -= 1 }
        let word = String(utf16CodeUnits: Array(utf16[start..<end]), count: end - start).lowercased()
        return modifiers.contains(word) ? (word, start) : (nil, index)
    }

    private static func monthSpan(_ span: ChronoSpan, modifier: String?, referenceDate: Date, calendar: Calendar) -> ChronoSpan {
        // A year said outright ("March 2025") stands.
        guard let month = span.date.month, !span.isYearCertain else { return span }
        let current = calendar.dateComponents([.year, .month], from: referenceDate)
        guard let year = current.year, let thisMonth = current.month else { return span }
        var date = span.date
        switch modifier {
        case "last", "past", "previous": date.year = month < thisMonth ? year : year - 1
        case "next", "coming": date.year = month > thisMonth ? year : year + 1
        default: date.year = year
        }
        return ChronoSpan(utf16Offset: span.utf16Offset, utf16Length: span.utf16Length, date: date, isDayCertain: false,
                          isTimeCertain: false, isMonthCertain: true, end: nil)
    }

    private static func interval(for span: ChronoSpan, calendar: Calendar) -> DateInterval? {
        var components = span.date
        components.hour = nil
        components.minute = nil
        if span.isDayCertain {
            guard let day = calendar.date(from: DateComponents(year: components.year, month: components.month, day: components.day)) else { return nil }
            return calendar.dateInterval(of: .day, for: day)
        }
        guard let month = calendar.date(from: DateComponents(year: components.year, month: components.month, day: 1)) else { return nil }
        return calendar.dateInterval(of: .month, for: month)
    }

    private static func label(for span: ChronoSpan, interval: DateInterval, calendar: Calendar, dates: DatePresentationFormatter) -> String {
        let dates = dates.with(calendar)
        return span.isDayCertain
            ? dates.format(interval.start, .compact, weekday: .abbreviated, year: .outsideCurrentYear)
            : dates.monthYear(interval.start)
    }

    /// The date phrase must be whole words ("may" inside "Mayday" isn't one).
    private static func isBoundary(_ utf16: [UInt16], _ index: Int) -> Bool {
        guard index > 0, index < utf16.count else { return true }
        let isWord: (UInt16) -> Bool = { unit in
            guard let scalar = Unicode.Scalar(unit) else { return true }
            return CharacterSet.alphanumerics.contains(scalar)
        }
        return !(isWord(utf16[index - 1]) && isWord(utf16[index]))
    }
}
