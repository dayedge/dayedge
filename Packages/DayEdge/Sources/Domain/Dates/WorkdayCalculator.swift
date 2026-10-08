import Foundation

/// A public holiday as metadata (never an event). `dateKey` is a civil
/// "yyyy-MM-dd" string, so it is immune to time-zone shifts.
package struct PublicHoliday: Codable, Hashable, Sendable {
    package let dateKey: String
    package let name: String

    package init(dateKey: String, name: String) {
        self.dateKey = dateKey
        self.name = name
    }
}

package struct MonthHoliday: Equatable {
    package let date: Date
    package let name: String
}

package struct MonthWorkdaySummary: Equatable {
    package let workingDays: Int
    package let weekendDays: Int
    /// Public holidays that fall on a configured work day (start of day).
    package let publicHolidayDates: Set<Date>
    /// Every holiday in the month (weekend ones included), in date order,
    /// for the hover details. Weekend holidays never reduce `workingDays`.
    package var holidayDetails: [MonthHoliday] = []

    package var publicHolidayCount: Int { publicHolidayDates.count }

    /// "workday(s)" label; the number is styled separately in the header.
    package var workdayLabel: String { L10n.tr("workdays.label", "\(workingDays) workdays") }

    /// Only the exceptional part, e.g. "1 holiday"; nil when no weekday holiday.
    package var holidaySuffix: String? {
        publicHolidayCount > 0 ? L10n.tr("workdays.holidays", "\(publicHolidayCount) holidays") : nil
    }

    /// Tooltip breakdown; the holiday line is omitted when there are none.
    package var breakdownLines: [String] {
        var lines = [
            L10n.tr("workdays.working", "\(workingDays) working days"),
            L10n.tr("workdays.weekends", "\(weekendDays) weekend days")
        ]
        if publicHolidayCount > 0 {
            lines.append(L10n.tr("workdays.public.holidays", "\(publicHolidayCount) public holidays"))
        }
        return lines
    }
}

/// Standard business-calendar math: work days = configured work week
/// minus public holidays. Never inferred from events, PTO, or OOO.
package enum WorkdayCalculator {
    package static func dateKey(for date: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    package static func summary(
        forMonth month: Date,
        weekendWeekdays: Set<Int>,
        holidays: [PublicHoliday],
        calendar: Calendar
    ) -> MonthWorkdaySummary {
        guard let interval = calendar.dateInterval(of: .month, for: month) else {
            return MonthWorkdaySummary(workingDays: 0, weekendDays: 0, publicHolidayDates: [])
        }
        let holidayNames = Dictionary(holidays.map { ($0.dateKey, $0.name) }, uniquingKeysWith: { first, _ in first })
        var details: [MonthHoliday] = []
        var working = 0, weekend = 0
        var holidayDates = Set<Date>()
        var day = interval.start
        while day < interval.end {
            if let name = holidayNames[dateKey(for: day, calendar: calendar)] {
                details.append(MonthHoliday(date: day, name: name))
            }
            if weekendWeekdays.contains(calendar.component(.weekday, from: day)) {
                // A holiday on a weekend is just a weekend day.
                weekend += 1
            } else if holidayNames[dateKey(for: day, calendar: calendar)] != nil {
                holidayDates.insert(day)
            } else {
                working += 1
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return MonthWorkdaySummary(workingDays: working, weekendDays: weekend, publicHolidayDates: holidayDates, holidayDetails: details)
    }
}
