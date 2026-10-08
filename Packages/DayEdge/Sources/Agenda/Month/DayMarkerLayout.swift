import SwiftUI
import Domain

/// One slot in the marker row under a month-grid day number.
package enum DayMarker: Hashable {
    case event(DotStyle)
    /// More events than free slots — stands in for the rest.
    case moreEvents
    /// At least one open task (due that day, or overdue on today), in its
    /// list's color.
    case task(Color)
}

/// Fits a day's markers into a fixed number of slots, so the row never
/// grows. Reserved markers (the task tick) take their slots first, on the
/// right; event dots fill the rest, the last free slot turning into "+"
/// when they don't all fit.
///
/// Adding a marker: add a `DayMarker` case, take a parameter for it here,
/// and append it to `reserved`. `EventDotsView` draws each case.
package enum DayMarkerLayout {
    package static func markers(
        dots: [DotStyle],
        taskColor: Color?,
        slots: Int = AppConfiguration.maxDotsPerDay
    ) -> [DayMarker] {
        var reserved: [DayMarker] = []
        if let taskColor { reserved.append(.task(taskColor)) }

        let free = max(slots - reserved.count, 0)
        let events: [DayMarker]
        if dots.count > free, free > 0 {
            events = dots.prefix(free - 1).map(DayMarker.event) + [.moreEvents]
        } else {
            events = dots.prefix(free).map(DayMarker.event)
        }
        return events + reserved
    }
}
