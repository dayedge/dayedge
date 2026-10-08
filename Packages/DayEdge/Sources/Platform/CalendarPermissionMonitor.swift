import AppKit
import EventKit
import Observation
import Domain

/// Calendar access as the system reports it now — the only thing that
/// decides whether DayEdge shows events (a cache is not a permission).
/// Started at launch whatever the index or the access request does, it
/// re-checks on activation, wake, EventKit changes, opening the panel and
/// every few seconds (macOS announces nothing when access is revoked; the
/// check costs under a microsecond), and reports each change once.
/// Calendar only — Reminders has its own permission and its own state.
@MainActor
@Observable
package final class CalendarPermissionMonitor {
    package private(set) var status: SourceAccessStatus

    package var isGranted: Bool { status == .granted }

    /// Called once per change, after `status` is updated.
    @ObservationIgnored package var onChange: ((SourceAccessStatus) -> Void)?

    @ObservationIgnored private let read: () -> SourceAccessStatus
    @ObservationIgnored private let interval: Duration
    @ObservationIgnored private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    @ObservationIgnored private var poll: Task<Void, Never>?

    package init(read: @escaping () -> SourceAccessStatus = { EventKitAccess.status(for: .event) },
                 interval: Duration = .seconds(10)) {
        self.read = read
        self.interval = interval
        self.status = read()
    }

    /// Begins watching. `eventStore`'s change notifications trigger a check
    /// too (a grant or revoke often comes with one).
    package func start(eventStore: EKEventStore? = nil) {
        guard poll == nil else { return }
        observe(NSApplication.didBecomeActiveNotification, center: .default)
        observe(NSWorkspace.didWakeNotification, center: NSWorkspace.shared.notificationCenter)
        observe(.EKEventStoreChanged, center: .default, object: eventStore)
        let interval = interval
        poll = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: interval) } catch { return }
                self?.check()
            }
        }
    }

    package func stop() {
        poll?.cancel()
        poll = nil
        for (center, observer) in observers { center.removeObserver(observer) }
        observers = []
    }

    /// Reads the permission now; reports it if it changed.
    package func check() {
        let current = read()
        guard current != status else { return }
        status = current
        onChange?(current)
    }

    private func observe(_ name: Notification.Name, center: NotificationCenter, object: Any? = nil) {
        let observer = center.addObserver(forName: name, object: object, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.check() }
        }
        observers.append((center, observer))
    }
}
