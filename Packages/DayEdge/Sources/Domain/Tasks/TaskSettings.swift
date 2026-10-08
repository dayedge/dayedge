import Foundation

/// Tasks preferences (Settings › Tasks). Keys live here so the pane and the
/// rest of the app read the same names.
package enum TaskSettings {
    package static let completedWindowKey = "com.dayedge.tasks.completedWindow"
    /// Scheduled reminders in the agenda and day view.
    package static let showsInCalendarKey = "com.dayedge.tasks.showInCalendar"

    package static func showsInCalendar(defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: showsInCalendarKey) as? Bool ?? true
    }

    /// How far back completed reminders are loaded, in days.
    package static let completedWindowOptions = [7, 30, 90]
    package static let defaultCompletedWindow = 30

    package static func completedWindowDays(defaults: UserDefaults = .standard) -> Int {
        let stored = defaults.integer(forKey: completedWindowKey)
        return completedWindowOptions.contains(stored) ? stored : defaultCompletedWindow
    }

    package static func completedSince(now: Date, defaults: UserDefaults = .standard, calendar: Calendar = .autoupdatingCurrent) -> Date {
        let days = completedWindowDays(defaults: defaults)
        let start = calendar.startOfDay(for: now)
        return calendar.date(byAdding: .day, value: -days, to: start) ?? start
    }

    package static func completedWindowTitle(_ days: Int) -> String { L10n.tr("tasksettings.last.days", "Last \(days) days") }
}
