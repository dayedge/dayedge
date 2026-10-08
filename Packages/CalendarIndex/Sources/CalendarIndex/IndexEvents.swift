import Foundation

/// What the index tells its readers. Posted only after the database
/// transaction behind it has committed.
public enum IndexEvent: Sendable, Equatable {
    /// Rows in `interval` changed for these calendars — re-read that range.
    case rangeCommitted(calendars: Set<String>, interval: DateInterval)
    /// The calendar inventory changed (added, removed or re-attached).
    case calendarsChanged
    case authorizationChanged(SourceAuthorization)
    case progress(SyncProgress)
    /// Visible and near months are current; outer years may still be filling.
    case nearReady
    /// The index was erased to be rebuilt: everything read before is gone.
    case reset
}

public struct SyncProgress: Sendable, Equatable {
    /// (calendar, month) chunks still due right now.
    public var pendingChunks: Int
    public var isRefreshing: Bool
    /// (calendar, month) chunks indexed / kept, over the current bands.
    public var coveredChunks: Int
    public var totalChunks: Int
    public var pacing: SyncPacing
    /// Background filling (outer years) is paused by the user; visible and
    /// near months, writes and changes still sync.
    public var isPaused: Bool

    public init(pendingChunks: Int, isRefreshing: Bool, coveredChunks: Int = 0, totalChunks: Int = 0,
                pacing: SyncPacing = .normal, isPaused: Bool = false) {
        self.isPaused = isPaused
        self.pendingChunks = pendingChunks
        self.isRefreshing = isRefreshing
        self.coveredChunks = coveredChunks
        self.totalChunks = totalChunks
        self.pacing = pacing
    }
}

/// Fan-out of `IndexEvent`s to any number of subscribers (an `AsyncStream`
/// alone has a single consumer).
public final class IndexEventBroadcaster: @unchecked Sendable {
    private let lock = NSLock()
    private var continuations: [UUID: AsyncStream<IndexEvent>.Continuation] = [:]
    private var lastProgress = SyncProgress(pendingChunks: 0, isRefreshing: false)

    public init() {}

    /// The latest `.progress`, for reads that report freshness.
    public var progress: SyncProgress {
        lock.withLock { lastProgress }
    }

    public func subscribe() -> AsyncStream<IndexEvent> {
        let id = UUID()
        return AsyncStream(bufferingPolicy: .bufferingNewest(64)) { continuation in
            lock.withLock { continuations[id] = continuation }
            continuation.onTermination = { [weak self] _ in
                guard let self else { return }
                _ = self.lock.withLock { self.continuations.removeValue(forKey: id) }
            }
        }
    }

    func publish(_ event: IndexEvent) {
        let targets = lock.withLock { () -> [AsyncStream<IndexEvent>.Continuation] in
            if case .progress(let progress) = event { lastProgress = progress }
            return Array(continuations.values)
        }
        for continuation in targets { continuation.yield(event) }
    }
}
