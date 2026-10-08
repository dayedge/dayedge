import Foundation

/// The fixed grid coverage is tracked on: calendar months in UTC. Fixed so
/// a time-zone change never reshuffles which month owns which row.
public enum MonthGrid {
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    /// The start of the UTC month containing `date`.
    public static func month(containing date: Date) -> Date {
        calendar.dateInterval(of: .month, for: date)?.start ?? date
    }

    public static func month(_ month: Date, adding count: Int) -> Date {
        calendar.date(byAdding: .month, value: count, to: month) ?? month
    }

    public static func interval(of month: Date) -> DateInterval {
        DateInterval(start: month, end: self.month(month, adding: 1))
    }

    /// Whole months between two month starts (b − a).
    public static func distance(from a: Date, to b: Date) -> Int {
        calendar.dateComponents([.month], from: a, to: b).month ?? 0
    }

    /// Every month overlapping `interval` (an empty interval still names
    /// its own month).
    public static func months(overlapping interval: DateInterval) -> [Date] {
        var result: [Date] = []
        var cursor = month(containing: interval.start)
        let last = interval.duration > 0 ? month(containing: interval.end.addingTimeInterval(-0.001)) : cursor
        while cursor <= last {
            result.append(cursor)
            cursor = month(cursor, adding: 1)
        }
        return result
    }
}
