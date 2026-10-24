import Foundation

/// When an event happens, as the editors edit it: a start and an end, each a
/// whole moment, or a span of whole days.
///
/// The end is exclusive, as EventKit stores it: 17:00 to midnight ends at
/// 00:00 the next day, and an all-day event on 18–20 Oct ends at the midnight
/// that starts 21 Oct. Every change keeps the end after the start, so an
/// editor never holds a time it could not save.
package struct EventTiming: Equatable, Sendable {
    private var startMoment: Date
    private var endMoment: Date
    private var allDay: Bool
    private let calendar: Calendar

    /// An end not after the start becomes an hour after it (a day, all day).
    package init(start: Date, end: Date, isAllDay: Bool, calendar: Calendar) {
        self.calendar = calendar
        allDay = isAllDay
        startMoment = isAllDay ? calendar.startOfDay(for: start) : start
        endMoment = isAllDay ? calendar.startOfDay(for: end) : end
        if endMoment <= startMoment {
            endMoment = isAllDay ? adding(days: 1, to: startMoment) : startMoment.addingTimeInterval(Self.defaultLength)
        }
    }

    // Each value below can be bound to a control (`$timing.firstDay`); setting one applies the rules it describes.

    // MARK: Start

    /// When it starts. A new start moves the end with it, so the length stays.
    package var start: Date {
        get { startMoment }
        set {
            if allDay {
                let days = calendar.dateComponents([.day], from: startMoment, to: endMoment).day ?? 1
                startMoment = calendar.startOfDay(for: newValue)
                endMoment = adding(days: days, to: startMoment)
            } else {
                endMoment = newValue.addingTimeInterval(endMoment.timeIntervalSince(startMoment))
                startMoment = newValue
            }
        }
    }

    /// The day it starts. Another day keeps the clock time and the length.
    package var firstDay: Date {
        get { calendar.startOfDay(for: startMoment) }
        set { start = on(newValue, timeOf: startMoment) }
    }

    // MARK: End

    /// When it ends (exclusive). One at or before the start is that clock time on the day after the start's: 23:00 to
    /// "01:00" ends at 01:00 the next day. All day, it sets the last day.
    package var end: Date {
        get { endMoment }
        set {
            guard !allDay else {
                lastDay = newValue
                return
            }
            endMoment = newValue > startMoment ? newValue : on(adding(days: 1, to: firstDay), timeOf: newValue)
        }
    }

    /// The day shown beside Ends: the day of the end, or, all day, the last day it covers (the day before its exclusive
    /// end). Another day keeps the end's clock time; a day before the start's is the start's day, and all day the span
    /// then covers that one day.
    package var lastDay: Date {
        get { allDay ? adding(days: -1, to: endMoment) : calendar.startOfDay(for: endMoment) }
        set {
            let last = max(calendar.startOfDay(for: newValue), firstDay)
            if allDay {
                endMoment = adding(days: 1, to: last)
            } else {
                end = on(last, timeOf: endMoment)
            }
        }
    }

    // MARK: All day

    /// All day covers the days the timed event touched (one that ends at midnight does not touch the next). Back to
    /// timed, it is 09:00 on the first day to 10:00 on the last.
    package var isAllDay: Bool {
        get { allDay }
        set {
            guard newValue != allDay else { return }
            let first = firstDay
            if newValue {
                let last = max(calendar.startOfDay(for: endMoment.addingTimeInterval(-1)), first)
                startMoment = first
                endMoment = adding(days: 1, to: last)
            } else {
                let last = lastDay
                startMoment = on(first, hour: Self.defaultHour)
                endMoment = on(last, hour: Self.defaultHour + 1)
            }
            allDay = newValue
        }
    }

    // MARK: Calendar arithmetic

    private static let defaultHour = 9
    private static let defaultLength: TimeInterval = 60 * 60

    private func adding(days: Int, to date: Date) -> Date {
        calendar.date(byAdding: .day, value: days, to: date) ?? date
    }

    /// `day` at the clock time of `moment`.
    private func on(_ day: Date, timeOf moment: Date) -> Date {
        let time = calendar.dateComponents([.hour, .minute], from: moment)
        return on(day, hour: time.hour ?? 0, minute: time.minute ?? 0)
    }

    private func on(_ day: Date, hour: Int, minute: Int = 0) -> Date {
        calendar.date(bySettingHour: hour, minute: minute, second: 0, of: calendar.startOfDay(for: day)) ?? day
    }
}
