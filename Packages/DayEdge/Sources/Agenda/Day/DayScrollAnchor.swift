import Foundation

/// Where the Day view first scrolls: the current time for today, otherwise
/// the user's "Day starts at" hour.
package enum DayScrollAnchor {
    package static func minutes(isToday: Bool, now: Date, startHour: Int, calendar: Calendar = .autoupdatingCurrent) -> Int {
        guard isToday else { return startHour * 60 }
        let parts = calendar.dateComponents([.hour, .minute], from: now)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }
}
