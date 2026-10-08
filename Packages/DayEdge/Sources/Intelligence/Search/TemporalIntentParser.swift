import Foundation

/// Resolves only complete, small calendar-navigation expressions. Unknown
/// words and embedded dates are left for Chrono or eventual event search.
package struct TemporalIntentParser {
    // swiftlint:disable:next cyclomatic_complexity - the date grammar: one branch per phrase shape
    package func resolve(_ normalized: String, referenceDate: Date, calendar: Calendar) -> SearchIntent? {
        let tokens = normalized.split(separator: " ").map(String.init)
        if let dayOfMonth = resolveDayOfMonth(tokens, referenceDate: referenceDate, calendar: calendar) {
            return dayOfMonth
        }
        if let offset = resolveOffset(tokens, referenceDate: referenceDate, calendar: calendar) {
            return offset
        }
        if let week = resolveWeekNumber(tokens, referenceDate: referenceDate, calendar: calendar) {
            return week
        }
        var words = tokens.compactMap(TemporalWord.init(rawValue:))
        guard words.count == tokens.count else { return nil }
        if words.first == .the { words.removeFirst() }
        guard !words.isEmpty else { return nil }

        if words.count == 1 {
            let today = calendar.startOfDay(for: referenceDate)
            switch words[0] {
            case .today, .tonight: return .jumpToDate(today)
            case .tomorrow: return calendar.date(byAdding: .day, value: 1, to: today).map(SearchIntent.jumpToDate)
            case .yesterday: return calendar.date(byAdding: .day, value: -1, to: today).map(SearchIntent.jumpToDate)
            default: break
            }
        }

        if let boundary = Boundary(words[0]) {
            var remainder = Array(words.dropFirst())
            if remainder.first == .of { remainder.removeFirst() }
            if remainder.first == .the { remainder.removeFirst() }
            guard let period = parsePeriod(remainder, allowImplicitThis: true), period.unit != .weekend,
                  let interval = periodInterval(period, referenceDate: referenceDate, calendar: calendar) else { return nil }
            let date: Date
            switch boundary {
            case .start: date = interval.start
            case .end:
                guard let lastDay = calendar.date(byAdding: .day, value: -1, to: interval.end) else { return nil }
                date = calendar.startOfDay(for: lastDay)
            }
            return .jumpToDate(date)
        }

        if let weekdayIntent = resolveWeekday(words, referenceDate: referenceDate, calendar: calendar) {
            return weekdayIntent
        }

        guard let period = parsePeriod(words, allowImplicitThis: false) else { return nil }
        if period.unit == .weekend {
            return weekendStart(period.direction, referenceDate: referenceDate, calendar: calendar).map(SearchIntent.jumpToDate)
        }
        guard let interval = periodInterval(period, referenceDate: referenceDate, calendar: calendar) else { return nil }
        return period.unit == .week ? .jumpToDate(interval.start) : .jumpToMonth(interval.start)
    }

    private enum Boundary {
        case start, end

        init?(_ word: TemporalWord) {
            switch word {
            case .start: self = .start
            case .end: self = .end
            default: return nil
            }
        }
    }

    private enum Direction {
        case this, next, previous, last

        init?(_ word: TemporalWord) {
            switch word {
            case .this: self = .this
            case .next: self = .next
            case .previous: self = .previous
            case .last: self = .last
            default: return nil
            }
        }
    }

    private enum Unit {
        case week, month, year, weekend

        init?(_ word: TemporalWord) {
            switch word {
            case .week: self = .week
            case .month: self = .month
            case .year: self = .year
            case .weekend: self = .weekend
            default: return nil
            }
        }
    }
    private struct Period {
        let direction: Direction
        let unit: Unit
    }

    private func parsePeriod(_ words: [TemporalWord], allowImplicitThis: Bool) -> Period? {
        if words.count == 1, allowImplicitThis, let unit = Unit(words[0]) {
            return Period(direction: .this, unit: unit)
        }
        if words == [.weekend] { return Period(direction: .this, unit: .weekend) }
        guard words.count == 2, let direction = Direction(words[0]),
              let unit = Unit(words[1]) else { return nil }
        return Period(direction: direction, unit: unit)
    }

    private func periodInterval(_ period: Period, referenceDate: Date, calendar: Calendar) -> DateInterval? {
        let component: Calendar.Component
        switch period.unit {
        case .week: component = .weekOfYear
        case .month: component = .month
        case .year: component = .year
        case .weekend: return nil
        }
        let offset: Int
        switch period.direction {
        case .this: offset = 0
        case .next: offset = 1
        case .previous, .last: offset = -1
        }
        guard let shifted = calendar.date(byAdding: component, value: offset, to: referenceDate) else { return nil }
        return calendar.dateInterval(of: component, for: shifted)
    }

    private func weekendStart(_ direction: Direction, referenceDate: Date, calendar: Calendar) -> Date? {
        let current = calendar.dateIntervalOfWeekend(containing: referenceDate)
        switch direction {
        case .this:
            return (current ?? calendar.nextWeekend(startingAfter: referenceDate))?.start
        case .next:
            guard let upcoming = current ?? calendar.nextWeekend(startingAfter: referenceDate) else { return nil }
            return calendar.nextWeekend(startingAfter: upcoming.end)?.start
        case .previous, .last:
            return calendar.nextWeekend(startingAfter: current?.start ?? referenceDate, direction: .backward)?.start
        }
    }

    /// "next month 12", "12 next month", "the 3rd of this month": one day
    /// number (1–31, optional st/nd/rd/th) with a month phrase, in either
    /// order. A day the month doesn't have isn't a date ("next month 31"
    /// in a 30-day month).
    private func resolveDayOfMonth(_ tokens: [String], referenceDate: Date, calendar: Calendar) -> SearchIntent? {
        let numbers = tokens.enumerated().compactMap { index, token in Self.dayNumber(token).map { (index, $0) } }
        guard numbers.count == 1, let (position, day) = numbers.first else { return nil }
        var rest = tokens
        rest.remove(at: position)
        let words = rest.compactMap(TemporalWord.init(rawValue:))
        guard words.count == rest.count else { return nil }
        let phrase = words.filter { $0 != .the && $0 != .of }
        guard let period = parsePeriod(phrase, allowImplicitThis: false), period.unit == .month,
              let month = periodInterval(period, referenceDate: referenceDate, calendar: calendar),
              let date = calendar.date(byAdding: .day, value: day - 1, to: month.start),
              date < month.end else { return nil }
        return .jumpToDate(date)
    }

    /// A day counted from today: "in 3 weeks", "3 weeks from now", "10 days
    /// from today", "2 days ago", "today + 3 weeks", "+10 days", "-2 days"
    /// ("a week" counts as 1). Always that exact day — never a month.
    private func resolveOffset(_ tokens: [String], referenceDate: Date, calendar: Calendar) -> SearchIntent? {
        var words = tokens
        // "+10" / "-2" written together.
        if let first = words.first, first.count > 1, first.first == "+" || first.first == "-" {
            words.replaceSubrange(0...0, with: [String(first.first!), String(first.dropFirst())])
        }
        if words.first == "today", words.count > 1, words[1] == "+" || words[1] == "-" { words.removeFirst() }

        let sign: Int
        let countIndex: Int
        switch (words.first, words.last) {
        case ("in"?, _) where words.count == 3: sign = 1; countIndex = 1
        case ("+"?, _) where words.count == 3: sign = 1; countIndex = 1
        case ("-"?, _) where words.count == 3: sign = -1; countIndex = 1
        case (_, "ago"?) where words.count == 3: sign = -1; countIndex = 0
        case (_, "now"?) where words.count == 4 && words[2] == "from",
             (_, "today"?) where words.count == 4 && words[2] == "from":
            sign = 1; countIndex = 0
        default:
            return nil
        }
        let count: Int? = ["a", "an"].contains(words[countIndex]) ? 1 : Self.spelledNumbers[words[countIndex]] ?? Int(words[countIndex])
        guard let count, (1...999).contains(count),
              let unit = Self.offsetUnit(words[countIndex + 1]) else { return nil }
        let today = calendar.startOfDay(for: referenceDate)
        return calendar.date(byAdding: unit, value: sign * count, to: today).map(SearchIntent.jumpToDate)
    }

    /// "in two weeks": counts written as words.
    package static let spelledNumbers: [String: Int] = [
        "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7,
        "eight": 8, "nine": 9, "ten": 10, "eleven": 11, "twelve": 12
    ]

    private static func offsetUnit(_ word: String) -> Calendar.Component? {
        switch word {
        case "day", "days": .day
        case "week", "weeks": .weekOfYear
        case "month", "months": .month
        case "year", "years": .year
        default: nil
        }
    }

    /// "week 42" (this year), "week 42 2027", "week 1": the Monday of that
    /// ISO week, as the grid numbers weeks. A week the year doesn't have
    /// (53 in most years) isn't a date.
    private func resolveWeekNumber(_ tokens: [String], referenceDate: Date, calendar: Calendar) -> SearchIntent? {
        guard (2...3).contains(tokens.count), tokens[0] == "week", let week = Int(tokens[1]), (1...53).contains(week) else { return nil }
        var iso = Calendar(identifier: .iso8601)
        iso.timeZone = calendar.timeZone
        let year: Int
        if tokens.count == 3 {
            guard tokens[2].count == 4, let value = Int(tokens[2]) else { return nil }
            year = value
        } else {
            year = iso.component(.yearForWeekOfYear, from: referenceDate)
        }
        guard let monday = iso.date(from: DateComponents(weekday: 2, weekOfYear: week, yearForWeekOfYear: year)),
              iso.component(.weekOfYear, from: monday) == week else { return nil }
        return .jumpToDate(calendar.startOfDay(for: monday))
    }

    /// "12", "12th", "1st", "2nd", "3rd" → 12, 1, 2, 3; nil otherwise.
    private static func dayNumber(_ token: String) -> Int? {
        var digits = token
        for suffix in ["st", "nd", "rd", "th"] where digits.hasSuffix(suffix) {
            digits.removeLast(suffix.count)
            break
        }
        guard !digits.isEmpty, digits.allSatisfy(\.isNumber), let value = Int(digits), (1...31).contains(value) else { return nil }
        return value
    }

    private func resolveWeekday(_ words: [TemporalWord], referenceDate: Date, calendar: Calendar) -> SearchIntent? {
        let weekday: Int
        let direction: Direction?
        let explicitWeek: Bool
        if words.count == 1, let number = words[0].calendarWeekday {
            weekday = number; direction = nil; explicitWeek = false
        } else if words.count == 2, let modifier = Direction(words[0]),
                  let number = words[1].calendarWeekday {
            weekday = number; direction = modifier; explicitWeek = false
        } else if words.count == 3, let number = words[0].calendarWeekday,
                  let modifier = Direction(words[1]), words[2] == .week {
            weekday = number; direction = modifier; explicitWeek = true
        } else if words.count == 3, let modifier = Direction(words[0]), words[1] == .week,
                  let number = words[2].calendarWeekday {
            // The same, week first: "next week monday".
            weekday = number; direction = modifier; explicitWeek = true
        } else {
            return nil
        }

        let today = calendar.startOfDay(for: referenceDate)
        let date: Date?
        if explicitWeek || direction == .this || direction == .next {
            let period = Period(direction: direction ?? .this, unit: .week)
            date = periodInterval(period, referenceDate: today, calendar: calendar)
                .flatMap { weekdayDate(weekday, weekStart: $0.start, calendar: calendar) }
        } else if direction == .last || direction == .previous {
            date = (1...7).lazy.compactMap { calendar.date(byAdding: .day, value: -$0, to: today) }
                .first { calendar.component(.weekday, from: $0) == weekday }
        } else {
            date = (0...6).lazy.compactMap { calendar.date(byAdding: .day, value: $0, to: today) }
                .first { calendar.component(.weekday, from: $0) == weekday }
        }
        return date.map(SearchIntent.jumpToDate)
    }

    private func weekdayDate(_ weekday: Int, weekStart: Date, calendar: Calendar) -> Date? {
        let startWeekday = calendar.component(.weekday, from: weekStart)
        let days = (weekday - startWeekday + 7) % 7
        return calendar.date(byAdding: .day, value: days, to: weekStart)
    }

}
