import Foundation
import os

extension SyncCoordinator {
    // MARK: - Triggers

    /// Pauses or resumes background filling of the outer years. Visible and
    /// near months, the app's writes and EventKit changes keep syncing, so
    /// what's on screen never goes stale.
    public func setPaused(_ paused: Bool) {
        guard paused != isPaused else { return }
        isPaused = paused
        if let coverage = try? store.coverage() {
            broadcaster.publish(.progress(progress(coverage: coverage, now: clock.now(), isRefreshing: isRefreshing)))
        }
        kick()
    }

    /// Recreates the index: waits for the chunk in flight (its result is
    /// dropped with everything else), erases every row and starts over —
    /// calendars first, then the visible and near months, then the rest.
    /// Resumes background filling if it was paused.
    public func reindex() async {
        await acquireStep()
        defer { releaseStep() }
        guard erase() else { return }
        isPaused = false
        broadcaster.publish(.progress(SyncProgress(pendingChunks: 0, isRefreshing: true, coveredChunks: 0,
                                                   totalChunks: 0, pacing: conditions().pacing, isPaused: false)))
        isRefreshing = true
        passStart = clock.now()
        kick()
    }

    /// Calendar access is gone: stops, then erases everything EventKit
    /// gave (after the chunk in flight, whose result goes with it). Nothing
    /// is kept to serve; once access is back, `start()` refills from
    /// scratch, visible and near months first.
    public func revoke() async {
        stop()
        await acquireStep()
        defer { releaseStep() }
        authorization = .denied
        _ = erase()
        broadcaster.publish(.authorizationChanged(.denied))
    }

    /// Every row gone and the plan back to the start: calendars first,
    /// then everything in band order. Under the step lock.
    func erase() -> Bool {
        do {
            try store.eraseAll()
        } catch {
            Self.logger.error("erase failed: \(String(describing: error), privacy: .public)")
            return false
        }
        pending = [:]
        blocked = [:]
        calendars = []
        needsInventory = true
        deferred = [.all]
        monthsPerQuery = 1
        outerNotBefore = .distantPast
        nearSinceOuter = 0
        nearWorkPending = false
        resolveWaiters(force: true)
        broadcaster.publish(.reset)
        return true
    }

    /// The visible range — P0.
    public func setFocus(_ interval: DateInterval?) {
        focus = interval
        kick()
    }

    /// EventKit said something changed. Debounced: a burst is one pass.
    public func sourceChanged() {
        debounce?.cancel()
        let delay = policy.changeDebounce
        let clock = clock
        debounce = Task { [weak self] in
            do { try await clock.sleep(for: delay) } catch { return }
            await self?.applyChange()
        }
    }

    /// The undebounced effect of a change: inventory, then P0+P1 due.
    public func applyChange() {
        needsInventory = true
        markDue(.near)
        kick()
    }

    public func noteLifecycle(_ event: SyncLifecycle) {
        needsInventory = true
        authorization = nil
        switch event {
        case .launch, .wake, .activate:
            markDue(.near)
        case .timeZoneChanged:
            // All-day occurrences move with the zone: everything, in band order.
            markDue(.all)
        }
        kick()
    }

    /// The app wrote to these ranges: the visible/near part is refetched
    /// first, the rest (a "this and future events" tail) marked due.
    public func noteWrite(_ ranges: [DateInterval], calendars ids: [String]) {
        let kept = planner.bandMonths(now: clock.now(), focus: focus)
        let bands = Dictionary(uniqueKeysWithValues: kept.map { ($0.month, $0.band) })
        // Only months the index keeps; an open-ended ("this and future
        // events") range stops at the horizon.
        let months = Set(ranges.flatMap { range -> [Date] in
            kept.map(\.month).filter { MonthGrid.interval(of: $0).intersects(range) }
        }).sorted()
        guard !months.isEmpty else { return }
        guard !ids.isEmpty || !calendars.isEmpty else {
            deferred.append(.months(months, urgent: true))
            kick()
            return
        }
        let targets = ids.isEmpty ? calendars : ids
        var urgent: [WorkKey] = []
        var later: [WorkKey] = []
        for month in months {
            let keys = targets.map { WorkKey(calendarIdentifier: $0, month: month) }
            if bands[month]?.isOuter == true { later += keys } else { urgent += keys }
        }
        markDue(urgent, urgent: true)
        markDue(later, urgent: false)
        kick()
    }

    /// Makes sure `range` is indexed (months never fetched are fetched
    /// first), waiting up to `ensureTimeout`. Already-covered months return
    /// at once — staleness is the backstop's job. True when covered.
    @discardableResult
    public func ensure(_ range: DateInterval, calendars ids: [String]? = nil) async -> Bool {
        if calendars.isEmpty || needsInventory {
            await acquireStep()
            _ = await prepare()
            releaseStep()
        }
        let months = Array(MonthGrid.months(overlapping: range).prefix(policy.farMonths * 2 + 1))
        let targets = ids ?? calendars
        guard let coverage = try? store.coverage() else { return false }
        let missing = targets.flatMap { calendar in
            months.map { WorkKey(calendarIdentifier: calendar, month: $0) }
        }.filter { coverage[$0] == nil }
        guard !missing.isEmpty else { return true }
        markDue(missing, urgent: true)

        if worker == nil {
            // Not started: fetch just these months (urgent work runs
            // first), never the whole fill inline.
            while !missing.allSatisfy({ pending[$0] == nil }) {
                guard case .worked = await step() else { break }
            }
            return missing.allSatisfy { pending[$0] == nil }
        }
        kick()
        let id = UUID()
        let timeout = policy.ensureTimeout
        let clock = clock
        Task { [weak self] in
            try? await clock.sleep(for: timeout)
            await self?.expireWaiter(id)
        }
        return await withCheckedContinuation { continuation in
            waiters[id] = Waiter(keys: Set(missing), continuation: continuation)
        }
    }

    func backstopTick() {
        needsInventory = true
        let now = clock.now()
        blocked = blocked.filter { $0.value.until > now }
        kick()
    }
}
