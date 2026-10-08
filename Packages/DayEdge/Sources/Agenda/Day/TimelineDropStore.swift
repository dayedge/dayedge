import Observation

/// Where dropped Day-timeline events are drawn until their new times are
/// saved (or the move is cancelled). Kept outside the event's block on
/// purpose: SwiftUI can rebuild the block at any moment — it does when the
/// panel's decision card appears — and a block's own state would be lost,
/// snapping the event back while the card is still asking.
@MainActor
@Observable
package final class TimelineDropStore {
    package static let shared = TimelineDropStore()

    package struct Minutes: Equatable {
        package let start: Int
        package let end: Int
    }

    /// By event id, the dropped minutes since the day's start.
    package private(set) var dropped: [String: Minutes] = [:]

    package func hold(_ minutes: Minutes, for eventID: String) { dropped[eventID] = minutes }
    package func release(_ eventID: String) { dropped[eventID] = nil }
}
