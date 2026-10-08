import CalendarIndex
import EventKit
import Foundation

/// The production `EventSnapshotSource`: its own `EKEventStore`, used only
/// on one dedicated serial queue. EventKit's fetches are synchronous, so
/// they run there rather than on the cooperative pool; only plain
/// snapshots ever leave the queue.
///
/// `@unchecked Sendable`: `eventStore` and `lastAuthorization` are touched
/// only inside `queue`.
public final class EventKitSnapshotSource: EventSnapshotSource, @unchecked Sendable {
    private let queue: DispatchQueue
    private var eventStore: EKEventStore?
    private var lastAuthorization: EKAuthorizationStatus?
    private var observer: NSObjectProtocol?
    private let changeStream: AsyncStream<Void>
    private let changeContinuation: AsyncStream<Void>.Continuation

    public init(qos: DispatchQoS = .utility) {
        queue = DispatchQueue(label: "com.dayedge.calendarindex.eventkit", qos: qos)
        (changeStream, changeContinuation) = AsyncStream.makeStream(of: Void.self, bufferingPolicy: .bufferingNewest(1))
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        changeContinuation.finish()
    }

    public func changes() -> AsyncStream<Void> {
        changeStream
    }

    public func authorization() async -> SourceAuthorization {
        currentAuthorization()
    }

    public func currentAuthorization() -> SourceAuthorization {
        Self.map(EKEventStore.authorizationStatus(for: .event))
    }

    public func calendars() async throws -> [CalendarSnapshot] {
        try await onQueue { store in
            store.calendars(for: .event).map(EventSnapshotMapper.snapshot(of:))
        }
    }

    public func occurrences(in range: DateInterval, calendars identifiers: [String]) async throws -> SourceFetch {
        try await onQueue { store in
            let calendars = identifiers.compactMap { store.calendar(withIdentifier: $0) }
            // Never an empty calendar list: EventKit would read it as "all".
            guard !calendars.isEmpty else { throw SourceError.calendarsUnavailable }
            let predicate = store.predicateForEvents(withStart: range.start, end: range.end, calendars: calendars)
            let series = SeriesRuleLookup(eventStore: store)
            var snapshots: [OccurrenceSnapshot] = []
            store.enumerateEvents(matching: predicate) { event, _ in
                autoreleasepool {
                    if let snapshot = EventSnapshotMapper.snapshot(of: event, series: series) { snapshots.append(snapshot) }
                }
            }
            return SourceFetch(snapshots: snapshots, calendars: Set(calendars.map(\.calendarIdentifier)))
        }
    }

    /// Runs `work` on the queue with an authorized store — created there,
    /// and recreated when access was granted after it was made (a store
    /// made before the grant doesn't see calendars).
    private func onQueue<T: Sendable>(_ work: @escaping (EKEventStore) throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                continuation.resume(with: autoreleasepool {
                    Result {
                        let status = EKEventStore.authorizationStatus(for: .event)
                        guard status == .fullAccess else { throw SourceError.unauthorized }
                        if self.eventStore == nil || self.lastAuthorization != status {
                            self.replaceStore()
                        }
                        self.lastAuthorization = status
                        return try work(self.eventStore!)
                    }
                })
            }
        }
    }

    private func replaceStore() {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        let store = EKEventStore()
        let continuation = changeContinuation
        observer = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: nil) { _ in
            continuation.yield()
        }
        eventStore = store
    }

    static func map(_ status: EKAuthorizationStatus) -> SourceAuthorization {
        switch status {
        case .fullAccess: return .authorized
        case .notDetermined: return .notDetermined
        default: return .denied
        }
    }
}

extension CalendarIndexService {
    /// The production index: EventKit source, database at the default
    /// location.
    public static func live(databaseURL: URL? = nil, policy: SyncPolicy = .default) throws -> CalendarIndexService {
        let store = try IndexStore.open(at: databaseURL ?? IndexStore.defaultURL())
        return CalendarIndexService(store: store, source: EventKitSnapshotSource(), policy: policy)
    }
}
