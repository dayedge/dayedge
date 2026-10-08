import Foundation

/// The portion of `event` that occupies `day`, clipped to that day's
/// boundaries. Prefers the event's real, absolute `startDate`/`endDate`
/// when present — clipping those directly is what makes a span of any
/// length (not just an overnight one) count as occupying every day it
/// passes through, not only a day adjacent to its literal start. Falls
/// back to reconstructing from the "HH:mm" display fields (treating an end
/// earlier than its start as an overnight event ending the following day)
/// for data with no real dates, e.g. mock/legacy fixtures.
package func agendaInterval(
    for event: AgendaEventModel,
    on day: Date,
    calendar: Calendar = .autoupdatingCurrent
) -> DateInterval? {
    let dayStart = calendar.startOfDay(for: day)

    if let start = event.startDate, let end = event.endDate {
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart),
              start < dayEnd, end > dayStart else { return nil }
        let clippedStart = max(start, dayStart)
        let clippedEnd = min(end, dayEnd)
        guard clippedEnd > clippedStart else { return nil }
        return DateInterval(start: clippedStart, end: clippedEnd)
    }

    guard let startMinutes = event.startMinutesSinceMidnight,
          let endMinutes = event.endMinutesSinceMidnight else { return nil }
    let endDay = endMinutes <= startMinutes
        ? calendar.date(byAdding: .day, value: 1, to: dayStart)
        : dayStart
    guard let endDay,
          let start = wallClockDate(minutes: startMinutes, on: dayStart, calendar: calendar),
          let end = wallClockDate(minutes: endMinutes, on: endDay, calendar: calendar),
          end > start else { return nil }
    return DateInterval(start: start, end: end)
}

private func wallClockDate(minutes: Int, on day: Date, calendar: Calendar) -> Date? {
    var components = calendar.dateComponents([.era, .year, .month, .day], from: day)
    components.hour = minutes / 60
    components.minute = minutes % 60
    components.second = 0
    return calendar.date(from: components)
}
