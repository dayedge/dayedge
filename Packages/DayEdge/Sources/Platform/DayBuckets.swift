import Foundation

/// The minimum an item needs to be placed on the day(s) it spans.
package protocol EventSpanning {
    /// Stable per-occurrence identity: an item listed twice is placed once.
    var id: AnyHashable { get }
    var startDate: Date { get }
    var endDate: Date { get }
}

/// Which days an item belongs under — multi-day, all-day and overnight
/// events alike.
package enum DayBuckets {
    /// Merges `items` into `existing`, indexed under every day *within
    /// `[windowStart, windowEnd]`* each spans — not only its start day.
    /// Clamped to that window (rather than walking an item's full span
    /// unconditionally) so one pathologically long event — a week-long
    /// all-day vacation entry, say — can't balloon this loop past the
    /// window actually being read. Deduped by `id`, so an item listed twice
    /// isn't doubled up in a day's list.
    package static func index<Item: EventSpanning>(
        _ items: [Item], calendar: Calendar, windowStart: Date, windowEnd: Date, mergingInto existing: [Date: [Item]]
    ) -> [Date: [Item]] {
        var result = existing
        let clampStart = calendar.startOfDay(for: windowStart)
        let clampEnd = calendar.startOfDay(for: windowEnd)
        for item in items {
            let firstDay = max(calendar.startOfDay(for: item.startDate), clampStart)
            // EventKit represents a multi-day *all-day* event's `endDate`
            // as the day after the last day it covers (exclusive) — back
            // it off a tick so that boundary isn't counted as an extra,
            // event-free day.
            let lastDayBound = item.endDate > item.startDate ? item.endDate.addingTimeInterval(-1) : item.startDate
            let lastDay = min(calendar.startOfDay(for: lastDayBound), clampEnd)
            guard firstDay <= lastDay else { continue }
            var day = firstDay
            while day <= lastDay {
                var dayItems = result[day] ?? []
                if !dayItems.contains(where: { $0.id == item.id }) {
                    dayItems.append(item)
                    result[day] = dayItems
                }
                guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
                day = next
            }
        }
        return result
    }
}
