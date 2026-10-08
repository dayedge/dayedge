import Foundation

/// Dragging an event in the Day timeline: an edge resizes it, the middle
/// moves it (same length). Snapped to the clock's 15-minute marks, never
/// shorter than one step and never off the day.
package enum TimelineResize {
    package enum Edge: Equatable, Sendable { case top, bottom, body }

    package static let step = 15

    /// Minutes since the day's start, after dragging `edge` by `deltaMinutes`.
    package static func resized(start: Int, end: Int, edge: Edge, deltaMinutes: Double,
                                step: Int = step, dayLength: Int = 24 * 60) -> (start: Int, end: Int) {
        switch edge {
        case .top:
            let moved = snap(Double(start) + deltaMinutes, step: step)
            return (min(max(moved, 0), end - step), end)
        case .bottom:
            let moved = snap(Double(end) + deltaMinutes, step: step)
            return (start, max(min(moved, dayLength), start + step))
        case .body:
            let length = end - start
            let moved = min(max(snap(Double(start) + deltaMinutes, step: step), 0), dayLength - length)
            return (moved, moved + length)
        }
    }

    package static func snap(_ minutes: Double, step: Int) -> Int {
        Int((minutes / Double(step)).rounded()) * step
    }
}
