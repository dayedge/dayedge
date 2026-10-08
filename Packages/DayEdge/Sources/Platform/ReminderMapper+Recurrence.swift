import EventKit
import Foundation
import Domain

extension ReminderMapper {
    // MARK: Recurrence

    package static func recurrence(from rules: [EKRecurrenceRule]?, due: Date?, calendar: Calendar) -> TaskRecurrence {
        guard let rule = rules?.first else { return .never }
        return standardRecurrence(for: rule, due: due, calendar: calendar) ?? .custom(summary(of: rule))
    }

    private static let weekdayNumbers: Set<Int> = [2, 3, 4, 5, 6] // Mon–Fri, Calendar's Sunday = 1

    /// The exact rule, for computing later occurrences. EventKit's weekday
    /// numbering matches `Calendar`'s (Sunday = 1).
    package static func rule(from rule: EKRecurrenceRule) -> TaskRecurrenceRule {
        let frequency: TaskRecurrenceRule.Frequency?
        switch rule.frequency {
        case .daily: frequency = .daily
        case .weekly: frequency = .weekly
        case .monthly: frequency = .monthly
        case .yearly: frequency = .yearly
        @unknown default: frequency = nil
        }
        var result = TaskRecurrenceRule(
            frequency: frequency ?? .daily,
            interval: rule.interval,
            weekdays: (rule.daysOfTheWeek ?? []).map { .init(weekday: $0.dayOfTheWeek.rawValue, ordinal: $0.weekNumber) },
            daysOfMonth: (rule.daysOfTheMonth ?? []).map(\.intValue),
            months: (rule.monthsOfTheYear ?? []).map(\.intValue),
            setPositions: (rule.setPositions ?? []).map(\.intValue),
            endDate: rule.recurrenceEnd?.endDate,
            occurrenceCount: rule.recurrenceEnd.flatMap { $0.occurrenceCount > 0 ? $0.occurrenceCount : nil }
        )
        result.hasUnsupportedParts = frequency == nil || !rule.weeksOfTheYear.isNilOrEmpty || !rule.daysOfTheYear.isNilOrEmpty
        return result
    }

    /// How Reminders.app stores "Monthly" on the 29th–31st: the last of the
    /// 28th…due day, so short months still get an occurrence.
    private static func isRemindersMonthEnd(_ rule: EKRecurrenceRule, dueDay: Int?) -> Bool {
        guard let dueDay, dueDay >= 28, (rule.setPositions ?? []).map(\.intValue) == [-1] else { return false }
        let days = (rule.daysOfTheMonth ?? []).map(\.intValue).sorted()
        return days == Array(28...dueDay)
    }

    // swiftlint:disable cyclomatic_complexity - one branch per EventKit frequency and its day/month parts
    /// nil when the rule says more than the app's Repeat menu can (an end,
    /// specific days, set positions…), so it is shown, not flattened.
    private static func standardRecurrence(for rule: EKRecurrenceRule, due: Date?, calendar: Calendar) -> TaskRecurrence? {
        let parts = due.map { calendar.dateComponents([.weekday, .day, .month], from: $0) }
        if rule.frequency == .monthly, rule.interval == 1, rule.recurrenceEnd == nil,
           rule.daysOfTheWeek.isNilOrEmpty, rule.monthsOfTheYear.isNilOrEmpty,
           isRemindersMonthEnd(rule, dueDay: parts?.day) {
            return .monthly
        }
        guard rule.recurrenceEnd == nil,
              rule.weeksOfTheYear.isNilOrEmpty, rule.daysOfTheYear.isNilOrEmpty, rule.setPositions.isNilOrEmpty
        else { return nil }
        let days = rule.daysOfTheWeek ?? []
        let dayOfMonth = rule.daysOfTheMonth ?? []
        let months = rule.monthsOfTheYear ?? []

        switch (rule.frequency, rule.interval) {
        case (.daily, 1):
            return days.isEmpty && dayOfMonth.isEmpty && months.isEmpty ? .daily : nil
        case (.weekly, 1):
            guard dayOfMonth.isEmpty, months.isEmpty else { return nil }
            if days.isEmpty { return .weekly }
            let numbers = Set(days.map(\.dayOfTheWeek.rawValue))
            if numbers == weekdayNumbers, days.allSatisfy({ $0.weekNumber == 0 }) { return .weekdays }
            if days.count == 1, days[0].weekNumber == 0, days[0].dayOfTheWeek.rawValue == parts?.weekday { return .weekly }
            return nil
        case (.weekly, 2):
            return days.isEmpty && dayOfMonth.isEmpty && months.isEmpty ? .biweekly : nil
        case (.monthly, 1):
            guard days.isEmpty, months.isEmpty else { return nil }
            if dayOfMonth.isEmpty { return .monthly }
            return dayOfMonth.count == 1 && dayOfMonth[0].intValue == parts?.day ? .monthly : nil
        case (.yearly, 1):
            guard days.isEmpty, dayOfMonth.isEmpty else { return nil }
            if months.isEmpty { return .yearly }
            return months.count == 1 && months[0].intValue == parts?.month ? .yearly : nil
        default:
            return nil
        }
    }
    // swiftlint:enable cyclomatic_complexity

    /// A human line for a rule we don't model: "Every 3 months", "Every 2
    /// weeks on Mon, Wed, until Dec 1".
    package static func summary(of rule: EKRecurrenceRule) -> String {
        let frequency = self.rule(from: rule).frequency
        let count = rule.interval
        var text = RecurrencePresentation.interval(frequency, count: count)
        if let days = rule.daysOfTheWeek, !days.isEmpty {
            let names = days.map { dayName($0.dayOfTheWeek) }.joined(separator: ", ")
            switch frequency {
            case .daily: text = L10n.tr("recurrence.days.on", "Every \(count) days on \(names)")
            case .weekly: text = L10n.tr("recurrence.weeks.on", "Every \(count) weeks on \(names)")
            case .monthly: text = L10n.tr("recurrence.months.on", "Every \(count) months on \(names)")
            case .yearly: text = L10n.tr("recurrence.years.on", "Every \(count) years on \(names)")
            }
        }
        if let end = rule.recurrenceEnd {
            if let date = end.endDate {
                let dateText = DatePresentationFormatter.current.format(date, .short)
                text = L10n.tr("recurrence.until", "\(text), until \(dateText)")
            } else if end.occurrenceCount > 0 {
                let occurrences = end.occurrenceCount
                text = L10n.tr("recurrence.occurrences", "\(occurrences) times: \(text)")
            }
        }
        return text
    }

    private static func dayName(_ day: EKWeekday) -> String {
        DatePresentationFormatter.current.weekdayName(day.rawValue, .abbreviated)
    }

    /// The rule for a Repeat-menu value; nil for `.never` and for `.custom`,
    /// which is never rewritten.
    package static func rule(for recurrence: TaskRecurrence) -> EKRecurrenceRule? {
        func simple(_ frequency: EKRecurrenceFrequency, interval: Int = 1) -> EKRecurrenceRule {
            EKRecurrenceRule(recurrenceWith: frequency, interval: interval, end: nil)
        }
        switch recurrence {
        case .never, .custom: return nil
        case .daily: return simple(.daily)
        case .weekly: return simple(.weekly)
        case .biweekly: return simple(.weekly, interval: 2)
        case .monthly: return simple(.monthly)
        case .yearly: return simple(.yearly)
        case .weekdays:
            let days = [EKWeekday.monday, .tuesday, .wednesday, .thursday, .friday].map { EKRecurrenceDayOfWeek($0) }
            return EKRecurrenceRule(
                recurrenceWith: .weekly, interval: 1, daysOfTheWeek: days, daysOfTheMonth: nil,
                monthsOfTheYear: nil, weeksOfTheYear: nil, daysOfTheYear: nil, setPositions: nil, end: nil
            )
        }
    }
}
