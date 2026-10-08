import Foundation

/// One choice in the Repeat editor: a title and the exact rule it sets
/// (nil = Never). Titles read from the item's own date — "Every Friday",
/// "Every month on the 2nd" — the way Calendar offers them.
package struct RepeatOption: Identifiable, Hashable {
    package let id: String
    package let title: String
    package let rule: TaskRecurrenceRule?
}

/// The Repeat editor's choices for an item starting on `anchor`, shared by
/// events and tasks (EventKit's rules are the same for both).
package enum RepeatPresets {
    package static func options(anchor: Date, calendar: Calendar, dates: DatePresentationFormatter = .current) -> [RepeatOption] {
        let weekday = calendar.component(.weekday, from: anchor)
        let day = calendar.component(.day, from: anchor)
        return [
            RepeatOption(id: "never", title: L10n.tr("repeatpresets.never", "Never"), rule: nil),
            RepeatOption(id: "daily", title: L10n.tr("repeatpresets.every.day", "Every Day"), rule: TaskRecurrenceRule(frequency: .daily)),
            RepeatOption(id: "weekdays", title: L10n.tr("repeatpresets.every.weekday", "Every Weekday"),
                         rule: TaskRecurrenceRule(frequency: .weekly, weekdays: (2...6).map { .init(weekday: $0) })),
            // No explicit weekday: EventKit repeats on the start's own day.
            RepeatOption(id: "weekly", title: RecurrencePresentation.weeklyWeekday(weekday),
                         rule: TaskRecurrenceRule(frequency: .weekly)),
            RepeatOption(id: "biweekly", title: L10n.tr("repeatpresets.every.2.weeks", "Every 2 Weeks"), rule: TaskRecurrenceRule(frequency: .weekly, interval: 2)),
            RepeatOption(id: "monthly", title: L10n.tr(
                "repeatpresets.every.month.on.the", "Every month on the \(String(describing: ordinal(day)))"
            ), rule: TaskRecurrenceRule(frequency: .monthly)),
            RepeatOption(id: "yearly", title: L10n.tr(
                "repeatpresets.every.year.on", "Every year on \(String(describing: dates.with(calendar).format(anchor, .short, relativeTo: anchor)))"
            ),
                         rule: TaskRecurrenceRule(frequency: .yearly))
        ]
    }

    /// The preset `rule` is, if any. A weekly rule naming only the start's
    /// own weekday is the same as one naming none.
    package static func option(matching rule: TaskRecurrenceRule?, in options: [RepeatOption], anchor: Date, calendar: Calendar) -> RepeatOption? {
        guard let rule else { return options.first { $0.rule == nil } }
        let normalized = normalize(rule, anchor: anchor, calendar: calendar)
        return options.first { $0.rule.map { normalize($0, anchor: anchor, calendar: calendar) } == normalized }
    }

    private static func normalize(_ rule: TaskRecurrenceRule, anchor: Date, calendar: Calendar) -> TaskRecurrenceRule {
        var rule = rule
        let weekday = calendar.component(.weekday, from: anchor)
        if rule.frequency == .weekly, rule.weekdays == [.init(weekday: weekday)] { rule.weekdays = [] }
        if rule.frequency == .monthly, rule.daysOfMonth == [calendar.component(.day, from: anchor)] { rule.daysOfMonth = [] }
        return rule
    }

    package static func weekdayName(_ weekday: Int, calendar: Calendar) -> String {
        DatePresentationFormatter.current.with(calendar).weekdayName(max(1, min(7, weekday)), .full)
    }

    package static func ordinal(_ day: Int) -> String {
        RecurrencePresentation.ordinal(day)
    }
}

/// The Custom… page's draft: every n days/weeks/months/years, on chosen
/// weekdays (weekly), ending never, on a date, or after a count.
package struct CustomRepeatDraft: Equatable {
    package enum Ending: Equatable {
        case never
        case onDate(Date)
        case afterCount(Int)
    }

    package var frequency: TaskRecurrenceRule.Frequency = .weekly
    package var interval = 1
    /// `Calendar` weekday numbers (1 = Sunday); weekly only.
    package var weekdays: Set<Int> = []
    package var ending: Ending = .never

    /// Starts from the current rule, or a weekly one on the item's weekday.
    package init(rule: TaskRecurrenceRule?, anchor: Date, calendar: Calendar) {
        let weekday = calendar.component(.weekday, from: anchor)
        guard let rule else {
            weekdays = [weekday]
            return
        }
        frequency = rule.frequency
        interval = rule.interval
        weekdays = Set(rule.weekdays.filter { $0.ordinal == 0 }.map(\.weekday))
        if frequency == .weekly, weekdays.isEmpty { weekdays = [weekday] }
        if let date = rule.endDate {
            ending = .onDate(date)
        } else if let count = rule.occurrenceCount {
            ending = .afterCount(count)
        }
    }

    package var rule: TaskRecurrenceRule {
        var rule = TaskRecurrenceRule(frequency: frequency, interval: interval)
        if frequency == .weekly { rule.weekdays = weekdays.sorted().map { .init(weekday: $0) } }
        switch ending {
        case .never: break
        case .onDate(let date): rule.endDate = date
        case .afterCount(let count): rule.occurrenceCount = max(count, 1)
        }
        return rule
    }
}
