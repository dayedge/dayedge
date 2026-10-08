import Foundation
import os

/// Why something should be refetched.
public enum SyncLifecycle: Sendable {
    case launch, wake, activate, timeZoneChanged
}

/// Keeps the index matching EventKit: one worker, a bounded set of due
/// (calendar, month) chunks, priority bands from `SyncPolicy`.
///
/// - Fetches happen before any write transaction; a failed, cancelled or
///   unauthorized fetch never touches stored data.
/// - Triggers only mark chunks due. A trigger that arrives while a chunk
///   is being fetched makes it due again after that fetch commits.
/// - A change notification refetches P0+P1 only; P2/P3 follow by a
///   rolling oldest-first backstop. Never a full rescan per change.
/// - After `outerEveryNChunks` near chunks one outer chunk runs, so outer
///   bands progress under a notification storm.
/// - Outer chunks are paced, never skipped: after each one the next waits
///   a gap that grows under Low Power Mode or thermal pressure (bounded by
///   `maxOuterGap`), while urgent and near work runs at once.
public actor SyncCoordinator {
    struct Pending {
        var seq: UInt64
        var isUrgent: Bool
    }

    struct Block {
        var until: Date
        var failures: Int
    }

    /// A trigger that arrived before the calendar list was known (launch):
    /// expanded into keys right after the first inventory.
    enum DeferredScope {
        case near, all
        case months([Date], urgent: Bool)
    }

    /// What one step did.
    enum StepResult: Equatable {
        case worked
        /// Nothing due at all.
        case idle
        /// Only paced outer chunks are due, from this time.
        case waiting(until: Date)
    }

    struct Waiter {
        var keys: Set<WorkKey>
        var continuation: CheckedContinuation<Bool, Never>
    }

    static let logger = Logger(subsystem: "com.dayedge.calendarindex", category: "sync")

    let store: IndexStore
    let source: EventSnapshotSource
    let policy: SyncPolicy
    let clock: IndexClock
    let broadcaster: IndexEventBroadcaster
    let conditions: @Sendable () -> SyncConditions
    let planner: SyncPlanner

    var focus: DateInterval?
    var calendars: [String] = []
    var authorization: SourceAuthorization?
    var needsInventory = true
    var pending: [WorkKey: Pending] = [:]
    var deferred: [DeferredScope] = []
    var seq: UInt64 = 0
    var blocked: [WorkKey: Block] = [:]
    var nearSinceOuter = 0
    var monthsPerQuery = 1
    var waiters: [UUID: Waiter] = [:]
    var isRefreshing = false
    /// Outer chunks wait until this (pacing); near work never does.
    var outerNotBefore: Date = .distantPast
    /// The user paused background filling: outer chunks wait until resumed.
    var isPaused = false
    /// Near/urgent work ran this pass and `.nearReady` isn't out yet.
    var nearWorkPending = false
    var passStart: Date?

    var worker: Task<Void, Never>?
    private var changeListener: Task<Void, Never>?
    var backstop: Task<Void, Never>?
    var debounce: Task<Void, Never>?
    var idle: CheckedContinuation<Void, Never>?
    var wakeTimer: Task<Void, Never>?
    var kickPending = false

    var stepBusy = false
    var stepQueue: [CheckedContinuation<Void, Never>] = []

    public init(store: IndexStore, source: EventSnapshotSource, policy: SyncPolicy = .default,
                clock: IndexClock = SystemIndexClock(), broadcaster: IndexEventBroadcaster = IndexEventBroadcaster(),
                conditions: @escaping @Sendable () -> SyncConditions = { SyncConditions.current() }) {
        self.store = store
        self.source = source
        self.policy = policy
        self.clock = clock
        self.broadcaster = broadcaster
        self.conditions = conditions
        self.planner = SyncPlanner(policy: policy)
    }

    // MARK: - Lifecycle

    /// Starts the background worker, the change listener and the backstop.
    public func start() {
        guard worker == nil else { return }
        noteLifecycle(.launch)
        worker = Task { [weak self] in await self?.runLoop() }
        let changes = source.changes()
        changeListener = Task { [weak self] in
            for await _ in changes { await self?.sourceChanged() }
        }
        let tick = policy.backstopTick
        let clock = clock
        backstop = Task { [weak self] in
            while !Task.isCancelled {
                do { try await clock.sleep(for: tick) } catch { return }
                await self?.backstopTick()
            }
        }
    }

    /// Stops after the in-flight fetch (a synchronous EventKit query can't
    /// be interrupted; its result is discarded).
    public func stop() {
        for task in [worker, changeListener, backstop, debounce, wakeTimer] { task?.cancel() }
        worker = nil
        changeListener = nil
        backstop = nil
        debounce = nil
        idle?.resume()
        idle = nil
        resolveWaiters(force: true)
    }
}
