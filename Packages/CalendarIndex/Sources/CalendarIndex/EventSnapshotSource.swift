import Foundation

/// Whether the index may read (and serve) calendar data.
public enum SourceAuthorization: String, Sendable, Codable {
    case authorized, notDetermined, denied

    public var isAuthorized: Bool { self == .authorized }
}

/// One successful fetch. `calendars` names exactly the calendars the query
/// covered — only those may be reconciled (a calendar that vanished
/// between inventory and fetch is absent here, never "empty").
public struct SourceFetch: Sendable {
    public var snapshots: [OccurrenceSnapshot]
    public var calendars: Set<String>

    public init(snapshots: [OccurrenceSnapshot], calendars: Set<String>) {
        self.snapshots = snapshots
        self.calendars = calendars
    }
}

public enum SourceError: Error, Sendable {
    case unauthorized
    /// None of the requested calendars could be resolved.
    case calendarsUnavailable
}

/// Where snapshots come from: EventKit in production
/// (`EventKitSnapshotSource`), a scripted fake in tests. A fetch either
/// succeeds completely for the calendars it reports, or throws — it never
/// returns a partial or empty result in place of a failure.
public protocol EventSnapshotSource: Sendable {
    func authorization() async -> SourceAuthorization
    /// The permission right now, synchronously — what every read of the
    /// index checks (cheap: EventKit answers in under a microsecond).
    func currentAuthorization() -> SourceAuthorization
    func calendars() async throws -> [CalendarSnapshot]
    /// Every occurrence overlapping `range` in the given calendars, with
    /// repeating events already expanded by the source.
    func occurrences(in range: DateInterval, calendars: [String]) async throws -> SourceFetch
    /// "Something changed" signals (no deltas); the coordinator decides
    /// what to refetch.
    func changes() -> AsyncStream<Void>
}
