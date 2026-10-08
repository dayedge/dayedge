import AppKit
import CalendarIndex
import CalendarIndexEventKit
import Foundation
import Domain

/// Runs the local calendar index (`Packages/CalendarIndex`) for the app's
/// lifetime: `make` opens the database at launch (reads check Calendar
/// access themselves, so nothing is served without it), `start` begins
/// syncing whenever access is granted, `revoke` stops and erases it when
/// access goes (`CalendarPermissionMonitor` says which). Feeds it wake /
/// activation / time-zone changes, drives the footer indicator and logs
/// each pass.
@MainActor
package final class CalendarIndexRuntime {
    package let service: CalendarIndexService
    private let activity: CalendarIndexActivity
    private var observers: [NSObjectProtocol] = []
    private var activityTask: Task<Void, Never>?

    private var isStarted = false
    private var wasRevoked = false
    /// Starts and revocations, run one after another in the order asked —
    /// a quick revoke → grant must never end stopped.
    private var transition: Task<Void, Never>?

    /// Opens the database. Corrupt or newer files are already replaced on
    /// open; if the usual location still fails (a persistent I/O or
    /// permission problem), a temporary index is used for this launch —
    /// it fills from EventKit the same way, just isn't kept. Nil only if
    /// both fail.
    package static func make(activity: CalendarIndexActivity) -> CalendarIndexRuntime? {
        do {
            let service = try CalendarIndexService.live()
            return CalendarIndexRuntime(service: service, activity: activity)
        } catch {
            // Fall through to a temporary index.
        }
        let temporary = FileManager.default.temporaryDirectory
            .appendingPathComponent("DayEdge-Index-\(ProcessInfo.processInfo.processIdentifier)/calendar-index.sqlite")
        do {
            let runtime = CalendarIndexRuntime(service: try CalendarIndexService.live(databaseURL: temporary), activity: activity)
            activity.isTemporary = true
            return runtime
        } catch {
            activity.isUnavailable = true
            return nil
        }
    }

    /// Begins syncing; whenever Calendar access is granted. Idempotent.
    /// After a revocation the index is empty and refills from scratch:
    /// "Updating calendars…" until the near months are back.
    package func start() {
        guard !isStarted else { return }
        isStarted = true
        activity.update(hasAccess: true)
        if wasRevoked {
            wasRevoked = false
            activity.beginRefill()
        }
        begin()
    }

    /// Calendar access is gone: stop syncing and erase every event the
    /// index holds. Idempotent.
    package func revoke() {
        activity.update(hasAccess: false)
        guard !wasRevoked else { return }
        wasRevoked = true
        isStarted = false
        removeObservers()
        let service = service
        enqueue { await service.revoke() }
    }

    private func enqueue(_ work: @escaping @Sendable () async -> Void) {
        let previous = transition
        transition = Task {
            await previous?.value
            await work()
        }
    }

    private init(service: CalendarIndexService, activity: CalendarIndexActivity) {
        self.service = service
        self.activity = activity
        activity.onSetPaused = { [service] paused in
            service.setPaused(paused)
        }
        activity.onReindex = { [service] in
            Task { await service.reindex() }
        }
        activity.update(hasAccess: service.authorization != .denied)
        let url = service.store.url
        activity.measureSize = {
            let sizes = ["", "-wal", "-shm"].compactMap {
                (try? FileManager.default.attributesOfItem(atPath: url.path + $0))?[.size] as? Int64
            }
            return sizes.isEmpty ? nil : sizes.reduce(0, +)
        }
        activity.refreshSize()
    }

    private func begin() {
        if activityTask == nil { feedActivity() }
        let coordinator = service.coordinator
        enqueue { await coordinator.start() }
        observe(NSWorkspace.didWakeNotification, center: NSWorkspace.shared.notificationCenter) { $0.noteLifecycle(.wake) }
        observe(NSApplication.didBecomeActiveNotification) { $0.noteLifecycle(.activate) }
        observe(.NSSystemTimeZoneDidChange) { $0.noteLifecycle(.timeZoneChanged) }
    }

    package func stop() {
        removeObservers()
        activityTask?.cancel()
        activityTask = nil
        service.stop()
    }

    private func removeObservers() {
        observers.forEach { NotificationCenter.default.removeObserver($0); NSWorkspace.shared.notificationCenter.removeObserver($0) }
        observers = []
    }

    private func observe(_ name: Notification.Name, center: NotificationCenter = .default,
                         _ action: @escaping (CalendarIndexService) -> Void) {
        let service = service
        observers.append(center.addObserver(forName: name, object: nil, queue: .main) { _ in action(service) })
    }

    /// The footer indicator's live state.
    private func feedActivity() {
        let events = service.events()
        activityTask = Task { [activity] in
            for await event in events {
                switch event {
                case .progress(let progress):
                    let pacing: CalendarIndexActivity.Pacing
                    switch progress.pacing {
                    case .normal: pacing = .normal
                    case .lowPower: pacing = .lowPower
                    case .thermal: pacing = .thermal
                    }
                    activity.update(isIndexing: progress.isRefreshing, coveredChunks: progress.coveredChunks,
                                    totalChunks: progress.totalChunks, pacing: pacing, isPaused: progress.isPaused)
                    activity.refreshSize()
                case .nearReady:
                    activity.nearReady()
                case .reset:
                    activity.didReset()
                    activity.refreshSize()
                case .authorizationChanged(let authorization):
                    activity.update(hasAccess: authorization != .denied)
                default:
                    continue
                }
            }
        }
    }
}
