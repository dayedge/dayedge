import Foundation
import os

extension SyncCoordinator {
    // MARK: - Work

    /// Runs chunks until nothing is due (tests, and `ensure` before
    /// `start`), waiting out outer pacing on the clock. Serialized with
    /// the worker.
    public func runUntilIdle() async {
        while !Task.isCancelled {
            switch await step() {
            case .worked: continue
            case .idle: return
            case .waiting(let until):
                try? await clock.sleep(for: .seconds(max(0, until.timeIntervalSince(clock.now()))))
            }
        }
    }

    /// Chunks still due right now, for progress and tests.
    public var pendingCount: Int { pending.count }

    func runLoop() async {
        while !Task.isCancelled {
            switch await step() {
            case .worked:
                continue
            case .waiting(let until):
                await waitForKick(until: until)
            case .idle:
                await waitForKick(until: nil)
            }
        }
    }

    /// One chunk (or one maintenance batch).
    func step() async -> StepResult {
        await acquireStep()
        defer { releaseStep() }
        guard !Task.isCancelled, await prepare() else { return .idle }

        let now = clock.now()
        blocked = blocked.filter { $0.value.until > now }
        guard let coverage = try? store.coverage() else { return .idle }
        let urgent = pending.filter { $0.value.isUrgent }.sorted { $0.value.seq < $1.value.seq }.map(\.key)
        var inputs = SyncPlanner.Inputs(
            now: now, focus: focus, calendars: calendars, coverage: coverage, dirty: Set(pending.keys),
            urgent: urgent, blocked: Set(blocked.keys), outerAvailable: !isPaused && now >= outerNotBefore,
            nearSinceOuter: nearSinceOuter, monthsPerQuery: monthsPerQuery)

        var nearOnly = inputs
        nearOnly.outerAvailable = false
        if nearWorkPending && planner.next(nearOnly) == nil {
            nearWorkPending = false
            broadcaster.publish(.nearReady)
        }
        if let batch = planner.next(inputs), !batch.calendars.isEmpty {
            return await run(batch)
        }
        if maintenance(now: now) { return .worked }
        inputs.outerAvailable = true
        if !isPaused, !inputs.calendars.isEmpty, planner.next(inputs) != nil {
            return .waiting(until: outerNotBefore)
        }
        finishPass(coverage: coverage, now: now)
        return .idle
    }

    /// Nothing left to do: report a complete pass once.
    private func finishPass(coverage: [WorkKey: Date], now: Date) {
        guard isRefreshing else { return }
        isRefreshing = false
        passStart = nil
        broadcaster.publish(.progress(progress(coverage: coverage, now: now, isRefreshing: false)))
    }

    func progress(coverage: [WorkKey: Date], now: Date, isRefreshing: Bool) -> SyncProgress {
        let months = planner.bandMonths(now: now, focus: focus).map(\.month)
        let total = months.count * calendars.count
        let covered = calendars.reduce(0) { count, calendar in
            count + months.filter { coverage[WorkKey(calendarIdentifier: calendar, month: $0)] != nil }.count
        }
        return SyncProgress(pendingChunks: pending.count, isRefreshing: isRefreshing, coveredChunks: covered,
                            totalChunks: total, pacing: conditions().pacing, isPaused: isPaused)
    }

    /// Authorization and calendar inventory, when stale.
    func prepare() async -> Bool {
        if authorization == nil || needsInventory {
            let current = await source.authorization()
            if current != authorization {
                let previous = authorization
                authorization = current
                if current == .denied {
                    // Revoked (now or while DayEdge wasn't running): keep
                    // nothing EventKit gave.
                    _ = erase()
                }
                broadcaster.publish(.authorizationChanged(current))
                if current.isAuthorized, let previous, previous != .authorized {
                    // Access is back: everything due, P0 first by band.
                    markDue(.all)
                }
            }
        }
        guard authorization?.isAuthorized == true else {
            resolveWaiters(force: true)
            return false
        }
        guard needsInventory else { return true }
        do {
            let snapshots = try await source.calendars()
            let change = try store.syncCalendars(snapshots, now: clock.now())
            calendars = snapshots.map(\.identifier)
            needsInventory = false
            let scopes = deferred
            deferred = []
            for scope in scopes { markDue(scope) }
            if !change.isEmpty {
                let gone = Set(change.deactivated)
                pending = pending.filter { !gone.contains($0.key.calendarIdentifier) }
                broadcaster.publish(.calendarsChanged)
            }
            return true
        } catch {
            Self.logger.error("inventory failed: \(String(describing: error), privacy: .public)")
            return false
        }
    }

    // swiftlint:disable:next cyclomatic_complexity function_body_length - one sync step: fetch, authorization, reconcile, publish, in order
    private func run(_ batch: SyncBatch) async -> StepResult {
        let started = clock.now()
        let startSeq = seq
        if !isRefreshing {
            isRefreshing = true
            passStart = started
            broadcaster.publish(.progress(SyncProgress(pendingChunks: pending.count, isRefreshing: true,
                                                       pacing: conditions().pacing, isPaused: isPaused)))
        }
        if !batch.band.isOuter || batch.isUrgent { nearWorkPending = true }
        let fetch: SourceFetch
        do {
            fetch = try await source.occurrences(in: batch.range, calendars: batch.calendars)
        } catch {
            Self.logger.error("fetch \(batch.range, privacy: .public) failed: \(String(describing: error), privacy: .public)")
            if case SourceError.unauthorized = error { authorization = nil }
            if case SourceError.calendarsUnavailable = error { needsInventory = true }
            block(batch.keys, now: started)
            return .worked
        }
        guard !Task.isCancelled else { return .idle }
        // Revoked while the query ran: what it read is never written.
        guard source.currentAuthorization().isAuthorized else {
            authorization = nil
            return .worked
        }

        let duration = clock.now().timeIntervalSince(started)
        adaptBatchSize(after: duration)

        let byCalendar = Dictionary(grouping: fetch.snapshots, by: \.calendarIdentifier)
        var changedCalendars: Set<String> = []
        var changedSpan: DateInterval?
        for calendar in batch.calendars {
            guard fetch.calendars.contains(calendar) else {
                // Vanished between inventory and fetch — never "empty".
                needsInventory = true
                block(batch.months.map { WorkKey(calendarIdentifier: calendar, month: $0) }, now: started)
                continue
            }
            for month in batch.months {
                let key = WorkKey(calendarIdentifier: calendar, month: month)
                do {
                    let result = try store.reconcile(calendarIdentifier: calendar, month: month,
                                                     snapshots: byCalendar[calendar] ?? [], fetchedAt: started)
                    if let span = result.changedSpan {
                        changedCalendars.insert(calendar)
                        changedSpan = changedSpan.map { DateInterval(start: min($0.start, span.start), end: max($0.end, span.end)) } ?? span
                    }
                    blocked[key] = nil
                    if let entry = pending[key], entry.seq <= startSeq { pending[key] = nil }
                } catch IndexStoreError.unknownCalendar {
                    needsInventory = true
                } catch {
                    Self.logger.error("reconcile \(key, privacy: .public) failed: \(String(describing: error), privacy: .public)")
                    block([key], now: started)
                }
            }
        }
        if let changedSpan {
            broadcaster.publish(.rangeCommitted(calendars: changedCalendars, interval: changedSpan))
        }
        resolveWaiters()
        if let coverage = try? store.coverage() {
            broadcaster.publish(.progress(progress(coverage: coverage, now: clock.now(), isRefreshing: true)))
        }

        nearSinceOuter = batch.band.isOuter ? 0 : nearSinceOuter + 1
        if batch.band.isOuter && !batch.isUrgent {
            let gap = policy.outerGap(afterFetch: duration, pacing: conditions().pacing)
            outerNotBefore = clock.now().addingTimeInterval(gap)
        }
        await Task.yield()
        return .worked
    }

    private func maintenance(now: Date) -> Bool {
        let purged = (try? store.purgeTombstones(now: now, ttl: policy.tombstoneTTL)) ?? 0
        let inactive = (try? store.purgeInactive()) ?? 0
        return purged + inactive > 0
    }
}
