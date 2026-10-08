import Foundation

/// Display wording only. Rule calculation and the assistant's English
/// vocabulary never depend on this formatter.
package enum RecurrencePresentation {
    package static func interval(_ frequency: TaskRecurrenceRule.Frequency, count: Int,
                                 locale: Locale = AppLocalization.displayLocale, bundle: Bundle = .module) -> String {
        switch frequency {
        case .daily: return L10n.tr("recurrence.every.days", "Every \(count) days", bundle: bundle, locale: locale)
        case .weekly: return L10n.tr("recurrence.every.weeks", "Every \(count) weeks", bundle: bundle, locale: locale)
        case .monthly: return L10n.tr("recurrence.every.months", "Every \(count) months", bundle: bundle, locale: locale)
        case .yearly: return L10n.tr("recurrence.every.years", "Every \(count) years", bundle: bundle, locale: locale)
        }
    }

    package static func summary(_ rule: TaskRecurrenceRule, dates: DatePresentationFormatter = .current) -> String {
        let numbers = rule.weekdays.map(\.weekday)
        if rule.frequency == .weekly, rule.interval == 1, Set(numbers) == Set(2...6), numbers.count == 5 {
            return L10n.tr("recurrence.every.weekday", "Every weekday", locale: dates.displayLocale)
        }
        if rule.frequency == .weekly, rule.interval == 1, numbers.count == 1, let number = numbers.first {
            return weeklyWeekday(number, locale: dates.displayLocale)
        }
        let weekdays = numbers.map { dates.weekdayName($0, .full) }
        let list = ListFormatter()
        list.locale = dates.displayLocale
        let names = dates.displayLocale.language.languageCode?.identifier == "en"
            ? weekdays.joined(separator: ", ") : (list.string(from: weekdays) ?? weekdays.joined(separator: ", "))
        if rule.frequency == .weekly, rule.interval == 1, !numbers.isEmpty {
            return L10n.tr("recurrence.every.weekday.list", "Every \(names)", locale: dates.displayLocale)
        }
        if rule.frequency == .monthly, rule.daysOfMonth.count == 1, numbers.isEmpty {
            let day = rule.daysOfMonth[0]
            if day == -1 {
                return L10n.tr("recurrence.monthly.last.day", "Every \(rule.interval) months on the last day", locale: dates.displayLocale)
            }
            let ordinal = ordinal(day, locale: dates.displayLocale)
            return L10n.tr("recurrence.monthly.day", "Every \(rule.interval) months on the \(ordinal)", locale: dates.displayLocale)
        }
        if !numbers.isEmpty {
            let count = rule.interval
            switch rule.frequency {
            case .daily: return L10n.tr("recurrence.days.on", "Every \(count) days on \(names)", locale: dates.displayLocale)
            case .weekly: return L10n.tr("recurrence.weeks.on", "Every \(count) weeks on \(names)", locale: dates.displayLocale)
            case .monthly: return L10n.tr("recurrence.months.on", "Every \(count) months on \(names)", locale: dates.displayLocale)
            case .yearly: return L10n.tr("recurrence.years.on", "Every \(count) years on \(names)", locale: dates.displayLocale)
            }
        }
        return interval(rule.frequency, count: rule.interval, locale: dates.displayLocale)
    }

    /// Full phrases let translations express weekday case correctly.
    package static func weeklyWeekday(_ number: Int, locale: Locale = AppLocalization.displayLocale) -> String {
        switch number {
        case 1: return L10n.tr("recurrence.weekday.sunday", "Every Sunday", locale: locale)
        case 2: return L10n.tr("recurrence.weekday.monday", "Every Monday", locale: locale)
        case 3: return L10n.tr("recurrence.weekday.tuesday", "Every Tuesday", locale: locale)
        case 4: return L10n.tr("recurrence.weekday.wednesday", "Every Wednesday", locale: locale)
        case 5: return L10n.tr("recurrence.weekday.thursday", "Every Thursday", locale: locale)
        case 6: return L10n.tr("recurrence.weekday.friday", "Every Friday", locale: locale)
        case 7: return L10n.tr("recurrence.weekday.saturday", "Every Saturday", locale: locale)
        default: return interval(.weekly, count: 1, locale: locale)
        }
    }

    package static func ordinal(_ number: Int, locale: Locale = AppLocalization.displayLocale) -> String {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .ordinal
        return formatter.string(from: NSNumber(value: number)) ?? number.formatted(.number.locale(locale))
    }
}
