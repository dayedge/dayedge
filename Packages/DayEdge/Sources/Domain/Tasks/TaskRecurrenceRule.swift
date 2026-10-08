import Foundation

/// A reminder's repeat rule as the source stores it — the subset of RFC 5545
/// that EventKit exposes — so later occurrences can be computed exactly,
/// including rules the Repeat menu can't express ("the last of the 28th–30th"
/// is how Reminders stores "Monthly" on the 30th; "every 2nd Tuesday";
/// "every 3 months"). `TaskRecurrence` stays the menu-facing summary.
package struct TaskRecurrenceRule: Hashable, Sendable {
    package enum Frequency: Hashable, Sendable { case daily, weekly, monthly, yearly }

    package struct Weekday: Hashable, Sendable {
        /// `Calendar` numbering: 1 = Sunday … 7 = Saturday.
        package let weekday: Int
        /// 0 = every such weekday; 2 = the second; -1 = the last (monthly /
        /// yearly rules only).
        package var ordinal: Int = 0

        package init(weekday: Int, ordinal: Int = 0) {
            self.weekday = weekday
            self.ordinal = ordinal
        }
    }

    package var frequency: Frequency
    package var interval: Int = 1
    package var weekdays: [Weekday] = []
    /// 1…31, or negative from the month's end (-1 = last day).
    package var daysOfMonth: [Int] = []
    package var months: [Int] = []
    /// Picks from each period's candidate days: 1 = first, -1 = last.
    package var setPositions: [Int] = []
    package var endDate: Date?
    package var occurrenceCount: Int?
    /// Parts the app doesn't evaluate (weeks/days of the year): such a rule
    /// is shown but never projected, rather than guessed.
    package var hasUnsupportedParts = false

    /// The rule a Repeat-menu value stands for; nil for `.never` and `.custom`.
    package init?(standard recurrence: TaskRecurrence) {
        switch recurrence {
        case .never, .custom: return nil
        case .daily: self.init(frequency: .daily)
        case .weekdays: self.init(frequency: .weekly, weekdays: (2...6).map { Weekday(weekday: $0) })
        case .weekly: self.init(frequency: .weekly)
        case .biweekly: self.init(frequency: .weekly, interval: 2)
        case .monthly: self.init(frequency: .monthly)
        case .yearly: self.init(frequency: .yearly)
        }
    }

    package init(frequency: Frequency, interval: Int = 1, weekdays: [Weekday] = [], daysOfMonth: [Int] = [],
                 months: [Int] = [], setPositions: [Int] = [], endDate: Date? = nil, occurrenceCount: Int? = nil) {
        self.frequency = frequency
        self.interval = max(interval, 1)
        self.weekdays = weekdays
        self.daysOfMonth = daysOfMonth
        self.months = months
        self.setPositions = setPositions
        self.endDate = endDate
        self.occurrenceCount = occurrenceCount
    }

    // MARK: - Evaluation

    /// Whether the series that starts on `start` (the first occurrence's
    /// day) has an occurrence on `day`. Pure date arithmetic per call; a
    /// count-limited rule walks from the start, bounded by that count.
    package func occurs(on day: Date, startingAt start: Date, calendar: Calendar) -> Bool {
        guard !hasUnsupportedParts else { return false }
        let day = calendar.startOfDay(for: day)
        let start = calendar.startOfDay(for: start)
        guard day >= start else { return false }
        if day == start { return true }
        if let endDate, day > calendar.startOfDay(for: endDate) { return false }
        guard matches(day, start: start, calendar: calendar) else { return false }
        guard let occurrenceCount else { return true }

        // The start counts as the first occurrence.
        var seen = 1
        var current = start
        while seen < occurrenceCount, let next = calendar.date(byAdding: .day, value: 1, to: current), next <= day {
            current = next
            if matches(current, start: start, calendar: calendar) {
                seen += 1
                if current == day { return true }
            }
        }
        return false
    }

    /// The days in `range` the series falls on, given its current occurrence
    /// `anchor` (EventKit keeps only a repeating reminder's next due date).
    ///
    /// - From `anchor` on: the full rule, end date and count included.
    /// - Before it: the pattern alone, never before `notBefore` (when the
    ///   task was created). These are the dates the rule scheduled — whether
    ///   each was completed isn't recorded by the source.
    package func occurrences(in range: DateInterval, anchoredAt anchor: Date, notBefore: Date?, calendar: Calendar) -> [Date] {
        guard !hasUnsupportedParts else { return [] }
        let anchorDay = calendar.startOfDay(for: anchor)
        let earliest = notBefore.map { calendar.startOfDay(for: $0) }
        var days: [Date] = []
        var day = calendar.startOfDay(for: range.start)
        while day < range.end {
            if day >= anchorDay {
                if occurs(on: day, startingAt: anchorDay, calendar: calendar) { days.append(day) }
            } else if earliest.map({ day >= $0 }) ?? true, matches(day, start: anchorDay, calendar: calendar) {
                days.append(day)
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return days
    }

    /// The pattern alone, ignoring end and count.
    private func matches(_ day: Date, start: Date, calendar: Calendar) -> Bool { // swiftlint:disable:this cyclomatic_complexity - per frequency
        let d = calendar.dateComponents([.year, .month, .day, .weekday], from: day)
        let s = calendar.dateComponents([.year, .month, .day, .weekday], from: start)
        guard let year = d.year, let month = d.month, let dom = d.day, let weekday = d.weekday,
              let startYear = s.year, let startMonth = s.month, let startDom = s.day, let startWeekday = s.weekday
        else { return false }

        switch frequency {
        case .daily:
            let days = calendar.dateComponents([.day], from: start, to: day).day ?? 0
            guard days % interval == 0 else { return false }
            if !months.isEmpty, !months.contains(month) { return false }
            if !weekdays.isEmpty, !weekdays.contains(where: { $0.weekday == weekday }) { return false }
            if !daysOfMonth.isEmpty, !resolvedDays(daysOfMonth, year: year, month: month, calendar: calendar).contains(dom) { return false }
            return true

        case .weekly:
            guard weeksBetween(start, day, calendar: calendar) % interval == 0 else { return false }
            if !months.isEmpty, !months.contains(month) { return false }
            let allowed = weekdays.isEmpty ? [startWeekday] : weekdays.map(\.weekday)
            return allowed.contains(weekday)

        case .monthly:
            let monthsApart = (year - startYear) * 12 + (month - startMonth)
            guard monthsApart % interval == 0 else { return false }
            if !months.isEmpty, !months.contains(month) { return false }
            let candidates = selectPositions(monthCandidates(year: year, month: month, fallbackDay: startDom, calendar: calendar))
            return candidates.contains(dom)

        case .yearly:
            guard (year - startYear) % interval == 0 else { return false }
            let yearMonths = months.isEmpty ? [startMonth] : months
            guard yearMonths.contains(month) else { return false }
            if setPositions.isEmpty {
                return monthCandidates(year: year, month: month, fallbackDay: startDom, calendar: calendar).contains(dom)
            }
            // Positions pick across the whole year's candidates.
            let all = yearMonths.sorted().flatMap { m in
                monthCandidates(year: year, month: m, fallbackDay: startDom, calendar: calendar).map { (m, $0) }
            }
            return selectPositions(all).contains { $0.0 == month && $0.1 == dom }
        }
    }

    /// Candidate days of one month: by weekday rules, by days of the month,
    /// or — with neither — the start's own day (skipped where it doesn't
    /// exist, e.g. the 31st in a 30-day month).
    private func monthCandidates(year: Int, month: Int, fallbackDay: Int, calendar: Calendar) -> [Int] {
        guard let first = calendar.date(from: DateComponents(year: year, month: month, day: 1)),
              let length = calendar.range(of: .day, in: .month, for: first)?.count else { return [] }
        var days: [Int]
        if !weekdays.isEmpty {
            let firstWeekday = calendar.component(.weekday, from: first)
            var set = Set<Int>()
            for rule in weekdays {
                let offset = (rule.weekday - firstWeekday + 7) % 7
                let all = Array(stride(from: 1 + offset, through: length, by: 7))
                if rule.ordinal == 0 {
                    set.formUnion(all)
                } else if rule.ordinal > 0, rule.ordinal <= all.count {
                    set.insert(all[rule.ordinal - 1])
                } else if rule.ordinal < 0, -rule.ordinal <= all.count {
                    set.insert(all[all.count + rule.ordinal])
                }
            }
            days = set.sorted()
            if !daysOfMonth.isEmpty {
                let allowed = Set(resolvedDays(daysOfMonth, year: year, month: month, calendar: calendar))
                days = days.filter(allowed.contains)
            }
        } else if !daysOfMonth.isEmpty {
            days = resolvedDays(daysOfMonth, year: year, month: month, calendar: calendar)
        } else {
            days = fallbackDay <= length ? [fallbackDay] : []
        }
        return days
    }

    /// Days of the month that exist, negatives counted from the end.
    private func resolvedDays(_ values: [Int], year: Int, month: Int, calendar: Calendar) -> [Int] {
        guard let first = calendar.date(from: DateComponents(year: year, month: month, day: 1)),
              let length = calendar.range(of: .day, in: .month, for: first)?.count else { return [] }
        return Set(values.compactMap { value -> Int? in
            let resolved = value > 0 ? value : length + value + 1
            return (1...length).contains(resolved) ? resolved : nil
        }).sorted()
    }

    private func selectPositions<T>(_ candidates: [T]) -> [T] {
        guard !setPositions.isEmpty else { return candidates }
        return setPositions.compactMap { position -> T? in
            if position > 0, position <= candidates.count { return candidates[position - 1] }
            if position < 0, -position <= candidates.count { return candidates[candidates.count + position] }
            return nil
        }
    }

    /// Whole weeks between the weeks (Monday-based, RFC 5545's default)
    /// containing `a` and `b`.
    private func weeksBetween(_ a: Date, _ b: Date, calendar: Calendar) -> Int {
        var mondayCalendar = calendar
        mondayCalendar.firstWeekday = 2
        guard let weekA = mondayCalendar.dateInterval(of: .weekOfYear, for: a)?.start,
              let weekB = mondayCalendar.dateInterval(of: .weekOfYear, for: b)?.start else { return 0 }
        let days = mondayCalendar.dateComponents([.day], from: weekA, to: weekB).day ?? 0
        return Int((Double(days) / 7).rounded())
    }
}

// MARK: - Presentation

extension TaskRecurrenceRule {
    /// The Repeat-menu value this rule is, or `.custom` with its summary.
    package var menuValue: TaskRecurrence {
        TaskRecurrence.standard.first { TaskRecurrenceRule(standard: $0) == self } ?? .custom(summary)
    }

    /// "Every day", "Every weekday", "Every Friday", "Every 2 weeks",
    /// "Every month on the 1st", "Every year".
    package var summary: String { RecurrencePresentation.summary(self) }

    /// Fixed-English text for model tool results; not a UI label.
    package var assistantSummary: String {
        let unit: (String, String)
        switch frequency {
        case .daily: unit = ("day", "days")
        case .weekly: unit = ("week", "weeks")
        case .monthly: unit = ("month", "months")
        case .yearly: unit = ("year", "years")
        }
        let weekdayNumbers = weekdays.map(\.weekday)
        if frequency == .weekly, interval == 1, Set(weekdayNumbers) == Set(2...6), weekdays.count == 5 { return "Every weekday" }
        if frequency == .weekly, interval == 1, !weekdays.isEmpty {
            return "Every " + weekdayNumbers.map(Self.weekdayName).joined(separator: ", ")
        }
        var text = interval == 1 ? "Every \(unit.0)" : "Every \(interval) \(unit.1)"
        if !weekdays.isEmpty { text += " on " + weekdayNumbers.map(Self.weekdayName).joined(separator: ", ") }
        if frequency == .monthly, daysOfMonth.count == 1, weekdays.isEmpty {
            text += daysOfMonth[0] == -1 ? " on the last day" : " on the \(Self.ordinal(daysOfMonth[0]))"
        }
        return text
    }

    private static func weekdayName(_ number: Int) -> String {
        DatePresentationFormatter(displayLocale: Locale(identifier: "en")).weekdayName(number, .full)
    }

    private static func ordinal(_ day: Int) -> String {
        let suffix: String
        switch (day % 10, day % 100) {
        case (_, 11...13): suffix = "th"
        case (1, _): suffix = "st"
        case (2, _): suffix = "nd"
        case (3, _): suffix = "rd"
        default: suffix = "th"
        }
        return "\(day)\(suffix)"
    }
}
