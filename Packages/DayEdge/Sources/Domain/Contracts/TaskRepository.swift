import Foundation
import Observation

/// The app-wide source of truth for reminders. Owns what the provider last
/// said (`confirmed`) and the writes still on their way to it (`pending`);
/// `tasks` is always confirmed + pending, so an edit shows instantly, a
/// failed one simply falls out, and a reload that lands mid-write can't
/// flicker the UI back to the old value.
///
/// `TaskStore` (Tasks tab presentation), Settings and — later — the agenda
/// and day view all read this one object.
@MainActor
@Observable
package final class TaskRepository {
    private struct PendingWrite {
        let token = UUID()
        let taskID: String
        let kind: PendingWriteKind
        /// A failure shows the global notice — unless the caller reports it
        /// itself (the chat's receipt).
        var notifies = true
    }

    package let listVisibility: SourceVisibilityStore
    package private(set) var lists: [CalendarSource] = []
    /// Confirmed tasks with pending writes applied.
    package private(set) var tasks: [TaskItem] = []
    package private(set) var accessStatus: SourceAccessStatus
    package private(set) var isLoading = false
    package private(set) var hasLoaded = false
    /// Bumped on every visible data change; part of the Tasks section cache key.
    package private(set) var revision = 0
    package private(set) var lastError: TaskSourceError?

    /// Set by the root view, which owns the notice host.
    @ObservationIgnored package var noticeCenter: NoticeCenter?
    @ObservationIgnored private let provider: TaskDataProviding
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let calendar: Calendar
    @ObservationIgnored private let now: () -> Date

    @ObservationIgnored private var confirmed: [TaskItem] = []
    @ObservationIgnored private var pending: [PendingWrite] = []
    /// Bumped whenever a write settles; a fetch that straddles one is stale.
    @ObservationIgnored private var writeGeneration = 0
    /// The last queued write; its value is the failure, if it failed.
    @ObservationIgnored private var lastWrite: Task<Error?, Never>?
    @ObservationIgnored private var isReloading = false
    @ObservationIgnored private var reloadRequested = false
    @ObservationIgnored private var reloadTask: Task<Void, Never>?
    @ObservationIgnored private var changesTask: Task<Void, Never>?
    @ObservationIgnored private var visibilityObserver: NSObjectProtocol?
    /// The excluded set the current data was fetched with.
    @ObservationIgnored private var fetchedExcludedIDs: Set<String>?
    @ObservationIgnored private var fetchedCompletedWindow: Int?

    @ObservationIgnored private var scheduledCache: ScheduledTaskIndex?
    @ObservationIgnored private var scheduledCacheKey: (revision: Int, today: Date)?

    package var supportsManualOrder: Bool { provider.supportsManualOrder }

    /// Open, dated tasks by day for the calendar views. Rebuilt only when
    /// the data or the current day changes; reads are O(1) per day.
    package func scheduledIndex(now: Date = Date(), calendar: Calendar = .autoupdatingCurrent) -> ScheduledTaskIndex {
        let today = calendar.startOfDay(for: now)
        if let scheduledCache, let key = scheduledCacheKey, key.revision == revision, key.today == today {
            return scheduledCache
        }
        var hasher = Hasher()
        hasher.combine(revision)
        hasher.combine(today)
        let index = ScheduledTaskIndex(tasks: tasks, now: now, calendar: calendar, signature: hasher.finalize())
        scheduledCache = index
        scheduledCacheKey = (revision, today)
        return index
    }

    package init(provider: TaskDataProviding,
                 listVisibility: SourceVisibilityStore,
                 noticeCenter: NoticeCenter? = nil,
                 defaults: UserDefaults = .standard,
                 calendar: Calendar = .autoupdatingCurrent,
                 now: @escaping () -> Date = { Date() }) {
        self.provider = provider
        self.listVisibility = listVisibility
        self.noticeCenter = noticeCenter
        self.defaults = defaults
        self.calendar = calendar
        self.now = now
        self.accessStatus = provider.accessStatus
    }

    // MARK: - Lifecycle

    /// Starts listening to the provider and to Settings. Idempotent.
    package func start() {
        if changesTask == nil {
            let stream = provider.changes
            changesTask = Task { [weak self] in
                for await _ in stream {
                    guard let self else { return }
                    await self.reload()
                }
            }
        }
        if visibilityObserver == nil {
            // Registered synchronously (not via an async sequence) so a change
            // posted right after `start()` can't be missed.
            visibilityObserver = NotificationCenter.default.addObserver(
                forName: .sourceVisibilityDidChange, object: listVisibility, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    // The footer's hide/show is a view filter; only Settings'
                    // exclusions change what is worth fetching.
                    guard let self, self.fetchedExcludedIDs != self.listVisibility.excludedIDs else { return }
                    self.scheduleReload()
                }
            }
        }
    }

    package func stop() {
        changesTask?.cancel(); changesTask = nil
        if let visibilityObserver { NotificationCenter.default.removeObserver(visibilityObserver) }
        visibilityObserver = nil
    }

    /// Loads once; later calls are no-ops. Use `reload()` to force.
    package func loadIfNeeded() async {
        guard !hasLoaded else { return }
        await reload()
    }

    /// Refetches lists and tasks. Concurrent calls coalesce into one extra
    /// pass, so a burst of change notifications costs at most two fetches.
    package func reload() async {
        accessStatus = provider.accessStatus
        guard accessStatus == .granted else {
            lists = []
            confirmed = []
            listVisibility.update([])
            fetchedExcludedIDs = nil
            hasLoaded = true
            rebuild()
            return
        }
        if isReloading {
            reloadRequested = true
            return
        }
        isReloading = true
        isLoading = true
        defer {
            isReloading = false
            isLoading = false
        }
        repeat {
            reloadRequested = false
            await fetchOnce()
        } while reloadRequested
        hasLoaded = true
    }

    private func fetchOnce() async {
        let generation = writeGeneration
        let excluded = listVisibility.excludedIDs
        let window = TaskSettings.completedWindowDays(defaults: defaults)
        let query = TaskQuery(
            completedSince: TaskSettings.completedSince(now: now(), defaults: defaults, calendar: calendar),
            excludedListIDs: excluded
        )
        let fetchedLists = await provider.lists()
        do {
            let fetchedTasks = try await provider.tasks(query)
            // A write settled while fetching: the snapshot may predate it.
            guard generation == writeGeneration else {
                reloadRequested = true
                return
            }
            lists = fetchedLists
            listVisibility.update(fetchedLists)
            confirmed = fetchedTasks
            fetchedExcludedIDs = excluded
            fetchedCompletedWindow = window
            lastError = nil
            rebuild()
        } catch let error as TaskSourceError {
            lastError = error
            if error == .accessDenied { accessStatus = .denied }
        } catch {
            lastError = .saveFailed(error.localizedDescription)
        }
    }

    /// Re-checks permission (the app just became active, say) and loads if
    /// it has newly been granted.
    package func refreshAccess() async {
        let status = provider.accessStatus
        guard status != accessStatus || (status == .granted && !hasLoaded) else { return }
        await reload()
    }

    package func requestAccess() async {
        accessStatus = await provider.requestAccess()
        await reload()
    }

    /// What the access button does: ask, or send the user to System Settings.
    package func performAccessAction() async {
        switch accessStatus {
        case .granted: break
        case .notDetermined: await requestAccess()
        case .denied:
            provider.openAccessSettings()
        }
    }

    /// The Tasks tab came to the front: the moment to ask for permission.
    package func activate() async {
        if provider.accessStatus == .notDetermined {
            await requestAccess()
        } else {
            await refreshAccess()
        }
    }

    /// The completed-window setting changed.
    package func reloadIfCompletedWindowChanged() async {
        guard fetchedCompletedWindow != TaskSettings.completedWindowDays(defaults: defaults) else { return }
        await reload()
    }

    // MARK: - Writes

    package func revealInSourceApp(taskID id: String) { provider.revealInSourceApp(taskID: id) }

    /// Creates a reminder and shows it right away (the store change that
    /// follows reloads it anyway).
    @discardableResult
    package func create(_ draft: TaskDraft) async throws -> TaskItem {
        let item = try await provider.create(draft)
        if !confirmed.contains(where: { $0.id == item.id }) { confirmed.append(item) }
        writeGeneration += 1
        rebuild()
        return item
    }

    /// Waits until every queued write and reload has settled (tests).
    package func flush() async {
        while let write = lastWrite {
            _ = await write.value
            if lastWrite == write { break }
        }
        await reloadTask?.value
    }

    @discardableResult
    private func enqueue(_ write: PendingWrite) -> Task<Error?, Never> {
        pending.append(write)
        rebuild()
        let previous = lastWrite
        let task = Task { [weak self] () -> Error? in
            _ = await previous?.value
            return await self?.commit(write)
        }
        lastWrite = task
        return task
    }

    /// nil once saved; the failure otherwise (already rolled back).
    private func commit(_ write: PendingWrite) async -> Error? {
        do {
            switch write.kind {
            case .change(let change):
                let stored = try await provider.apply(change, toTaskID: write.taskID)
                settle(write) { confirmed in
                    guard let index = confirmed.firstIndex(where: { $0.id == write.taskID }) else { return }
                    confirmed[index] = stored ?? confirmed[index].applying(change, now: now())
                }
            case .delete:
                try await provider.delete(taskID: write.taskID)
                settle(write) { $0.removeAll { $0.id == write.taskID } }
            }
            return nil
        } catch {
            // Settling without touching `confirmed` is the rollback.
            settle(write) { _ in }
            let failure = (error as? TaskSourceError) ?? .saveFailed(error.localizedDescription)
            lastError = failure
            if write.notifies { noticeCenter?.show(.error(title: failure.title, message: failure.message)) }
            // The source may know better than we do (deleted elsewhere, say).
            if failure == .notFound { scheduleReload() }
            return failure
        }
    }

    private func settle(_ write: PendingWrite, update: (inout [TaskItem]) -> Void) {
        pending.removeAll { $0.token == write.token }
        update(&confirmed)
        writeGeneration += 1
        rebuild()
    }

    private func scheduleReload() {
        reloadTask = Task { [weak self] in await self?.reload() }
    }

    /// `tasks` = confirmed, plus what is still on its way.
    private func rebuild() {
        var result = confirmed
        for write in pending {
            guard let index = result.firstIndex(where: { $0.id == write.taskID }) else { continue }
            switch write.kind {
            case .change(let change): result[index] = result[index].applying(change, now: now())
            case .delete: result.remove(at: index)
            }
        }
        tasks = result
        revision += 1
    }
}

// MARK: - Edits and deletions (queued, shown at once, rolled back on failure)

extension TaskRepository {
    package func apply(_ change: TaskChange, toTaskID id: String) {
        guard confirmed.contains(where: { $0.id == id }) else { return }
        enqueue(PendingWrite(taskID: id, kind: .change(change)))
    }

    package func delete(taskID id: String) {
        guard confirmed.contains(where: { $0.id == id }) else { return }
        enqueue(PendingWrite(taskID: id, kind: .delete))
    }

    /// `apply`, for a caller that must know the outcome: the same queue and
    /// instant update, but it returns only once the source saved — or throws
    /// what failed (rolled back, no global notice).
    package func applyAndWait(_ change: TaskChange, toTaskID id: String) async throws {
        guard confirmed.contains(where: { $0.id == id }) else { throw TaskSourceError.notFound }
        if let failure = await enqueue(PendingWrite(taskID: id, kind: .change(change), notifies: false)).value { throw failure }
    }

    /// `delete`, waiting for the outcome like `applyAndWait`.
    package func deleteAndWait(taskID id: String) async throws {
        guard confirmed.contains(where: { $0.id == id }) else { throw TaskSourceError.notFound }
        if let failure = await enqueue(PendingWrite(taskID: id, kind: .delete, notifies: false)).value { throw failure }
    }
}

/// What a queued task write does.
private enum PendingWriteKind {
    case change(TaskChange)
    case delete
}
