import Foundation
import Observation
import Domain

/// The events Ask shows, read once per day and kept: a row looks
/// its event up on every redraw (and scrolling redraws), so reading the
/// calendar each time made long answers slow. Emptied when the calendar
/// changes — reading `revision` makes the rows redraw then.
@MainActor
@Observable
package final class ChatEventCache {
    package private(set) var revision = 0
    @ObservationIgnored private var days: [Date: [String: AgendaEventModel]] = [:]
    @ObservationIgnored private let load: (Date) -> [AgendaEventModel]
    @ObservationIgnored private var observer: NSObjectProtocol?

    /// `load` reads one day's events (start of day in, the day's events out).
    package init(load: @escaping (Date) -> [AgendaEventModel], notificationCenter: NotificationCenter = .default) {
        self.load = load
        observer = notificationCenter.addObserver(forName: .calendarEventsDidChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.invalidate() }
        }
    }

    /// The occurrence with this id on this day, if it still exists.
    package func event(_ id: String, on day: Date) -> AgendaEventModel? {
        _ = revision
        if let cached = days[day] { return cached[id] }
        let events = Dictionary(load(day).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        days[day] = events
        return events[id]
    }

    package func invalidate() {
        days = [:]
        revision += 1
    }
}
