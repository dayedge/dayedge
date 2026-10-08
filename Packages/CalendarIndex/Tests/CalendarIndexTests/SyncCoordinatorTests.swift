import XCTest
@testable import CalendarIndex

/// Bands with `smallPolicy()` and today = 15 Oct 2026:
/// P0 Oct · P1 Sep, Nov · P2 Aug, Dec · P3 Jul, Jan.
final class SyncCoordinatorTests: XCTestCase {
    private let now = date("2026-10-15T12:00:00Z")
    private var clock: TestClock!
    private var store: IndexStore!
    private var source: FakeSnapshotSource!
    private var broadcaster: IndexEventBroadcaster!

    private var p0: [Date] { [month("2026-10-01T00:00:00Z")] }
    private var near: Set<Date> { Set(["2026-09-01", "2026-10-01", "2026-11-01"].map { month($0 + "T00:00:00Z") }) }
    private var all: Set<Date> {
        Set(["2026-07-01", "2026-08-01", "2026-09-01", "2026-10-01", "2026-11-01", "2026-12-01", "2027-01-01"]
            .map { month($0 + "T00:00:00Z") })
    }

    override func setUpWithError() throws {
        clock = TestClock(now)
        store = try makeStore()
        source = FakeSnapshotSource(calendars: ["A"])
        broadcaster = IndexEventBroadcaster()
    }

    private var conditions = SyncConditions()

    private func coordinator(_ policy: SyncPolicy = smallPolicy(), store: IndexStore? = nil) -> SyncCoordinator {
        SyncCoordinator(store: store ?? self.store, source: source, policy: policy, clock: clock,
                        broadcaster: broadcaster, conditions: { [unowned self] in self.conditions })
    }

    private func isOuter(_ month: Date) -> Bool { !near.contains(month) }

    // MARK: - Pacing

    func testLowPowerStillFillsEverythingWithGapsBetweenOuterChunks() async throws {
        conditions = SyncConditions(isLowPower: true)
        source.clock = clock
        let policy = smallPolicy()
        await coordinator(policy).runUntilIdle()
        XCTAssertEqual(Set(source.fetchedMonths), all, "outer years are slowed, never skipped")
        let outerTimes = source.fetches.filter { $0.months.allSatisfy(isOuter) }.compactMap(\.at)
        XCTAssertGreaterThan(outerTimes.count, 1)
        for (a, b) in zip(outerTimes, outerTimes.dropFirst()) {
            XCTAssertGreaterThanOrEqual(b.timeIntervalSince(a), policy.lowPowerMinGap.timeInterval)
        }
    }

    func testGapNeverExceedsTheCap() async throws {
        conditions = SyncConditions(thermal: .critical)
        source.clock = clock
        source.fetchSeconds = 30  // ×30 duty cycle would be 15 minutes
        var policy = smallPolicy()
        policy.maxOuterGap = .seconds(60)
        await coordinator(policy).runUntilIdle()
        XCTAssertEqual(Set(source.fetchedMonths), all)
        let outerTimes = source.fetches.filter { $0.months.allSatisfy(isOuter) }.compactMap(\.at)
        for (a, b) in zip(outerTimes, outerTimes.dropFirst()) {
            XCTAssertLessThanOrEqual(b.timeIntervalSince(a), 60 + source.fetchSeconds + 0.001)
        }
    }

    func testNearWorkIsNotDelayedByOuterPacing() async throws {
        conditions = SyncConditions(isLowPower: true)
        let sync = coordinator()
        // Fill near, then one outer chunk: the next outer one is now paced.
        while source.fetches.filter({ $0.months.allSatisfy(isOuter) }).isEmpty {
            _ = await sync.step()
        }
        let waiting = await sync.step()
        guard case .waiting = waiting else { return XCTFail("expected outer pacing, got \(waiting)") }

        source.resetLog()
        await sync.applyChange()
        while case .worked = await sync.step() {}
        XCTAssertEqual(Set(source.fetchedMonths), near, "near months ran while outer waited")
    }

    func testPacingFollowsConditionsAsTheyChange() async throws {
        let policy = smallPolicy()
        XCTAssertEqual(policy.outerGap(afterFetch: 0.05, pacing: .normal), 0.1, accuracy: 0.0001)
        XCTAssertEqual(policy.outerGap(afterFetch: 0.05, pacing: .lowPower), 2)
        XCTAssertEqual(policy.outerGap(afterFetch: 1, pacing: .lowPower), 10)
        XCTAssertEqual(policy.outerGap(afterFetch: 1, pacing: .thermal), 30)
        XCTAssertEqual(policy.outerGap(afterFetch: 10, pacing: .thermal), 60)

        conditions = SyncConditions(isLowPower: true)
        source.clock = clock
        let sync = coordinator()
        while source.fetches.filter({ $0.months.allSatisfy(isOuter) }).isEmpty { _ = await sync.step() }
        conditions = SyncConditions()
        await sync.runUntilIdle()
        // Gaps shrink once Low Power Mode is off: the rest finishes without
        // more than the one already-scheduled 2 s wait.
        let outerTimes = source.fetches.filter { $0.months.allSatisfy(isOuter) }.compactMap(\.at)
        XCTAssertLessThanOrEqual(outerTimes.last!.timeIntervalSince(outerTimes.first!), 2.001)
        XCTAssertEqual(Set(source.fetchedMonths), all)
    }

    func testProgressReportsCoverageAndNearReadiness() async throws {
        let events = broadcaster.subscribe()
        await coordinator().runUntilIdle()
        var sawNearReady = false
        var final: SyncProgress?
        var iterator = events.makeAsyncIterator()
        while let event = await withTaskGroup(of: IndexEvent?.self, body: { group in
            group.addTask { await iterator.next() }
            group.addTask { try? await Task.sleep(for: .milliseconds(100)); return nil }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }) {
            if case .nearReady = event { sawNearReady = true }
            if case .progress(let progress) = event, !progress.isRefreshing { final = progress }
        }
        XCTAssertTrue(sawNearReady)
        XCTAssertEqual(final?.coveredChunks, all.count)
        XCTAssertEqual(final?.totalChunks, all.count)
    }

    // MARK: - Reindex

    private func drain(_ events: AsyncStream<IndexEvent>) async -> [IndexEvent] {
        var collected: [IndexEvent] = []
        var iterator = events.makeAsyncIterator()
        while let event = await withTaskGroup(of: IndexEvent?.self, body: { group in
            group.addTask { await iterator.next() }
            group.addTask { try? await Task.sleep(for: .milliseconds(100)); return nil }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }) { collected.append(event) }
        return collected
    }

    func testReindexErasesEverythingThenRefillsTheSameOccurrences() async throws {
        source.events = [event("a", start: "2026-10-05T09:00:00Z", title: "Standup"),
                         event("b", start: "2027-01-10T09:00:00Z", title: "Far review")]
        let sync = coordinator()
        await sync.runUntilIdle()
        let before = try store.allRows().map(\.key).sorted()
        XCTAssertEqual(before.count, 2)

        let events = broadcaster.subscribe()
        await sync.reindex()
        XCTAssertTrue(try store.allRows().isEmpty)
        XCTAssertTrue(try store.coverage().isEmpty)
        XCTAssertEqual(try store.searchMatches(SearchRequest(text: "standup")).count, 0)

        source.resetLog()
        await sync.runUntilIdle()
        XCTAssertEqual(try store.allRows().map(\.key).sorted(), before, "same stable keys")
        XCTAssertEqual(try store.searchMatches(SearchRequest(text: "standup")).count, 1)
        XCTAssertEqual(source.fetchedMonths.first, p0.first, "the visible month comes back first")
        XCTAssertEqual(Set(source.fetchedMonths), all)

        let seen = await drain(events)
        let reset = seen.firstIndex(of: .reset)
        let commit = seen.firstIndex { if case .rangeCommitted = $0 { true } else { false } }
        guard let reset, let commit else { return XCTFail("missing reset or commit in \(seen)") }
        XCTAssertLessThan(reset, commit)
    }

    func testReindexResumesAPausedIndex() async throws {
        let sync = coordinator()
        await sync.setPaused(true)
        await sync.runUntilIdle()
        XCTAssertEqual(Set(source.fetchedMonths), near, "paused: outer years wait")
        await sync.reindex()
        source.resetLog()
        await sync.runUntilIdle()
        XCTAssertEqual(Set(source.fetchedMonths), all)
        let pending = await sync.pendingCount
        XCTAssertEqual(pending, 0)
    }

    private func titles() throws -> [String] {
        try store.occurrences(in: DateInterval(start: date("2026-06-01T00:00:00Z"), end: date("2027-03-01T00:00:00Z")))
            .map(\.snapshot.title)
    }

    func testFirstFillGoesBandByBandAndStopsAtTheFarHorizon() async throws {
        let sync = coordinator()
        await sync.runUntilIdle()
        let months = source.fetchedMonths
        XCTAssertEqual(months.first, p0.first)
        XCTAssertEqual(Set(months.prefix(3)), near)
        XCTAssertEqual(Set(months), all)
        XCTAssertEqual(months.count, all.count, "each month fetched once")
        XCTAssertEqual(try store.coverageInfo(for: DateInterval(start: date("2026-07-01T00:00:00Z"),
                                                                 end: date("2027-02-01T00:00:00Z"))).missingMonths, [])
    }

    func testBatchesCombineMonthsAndCalendars() async throws {
        source.calendarIdentifiers = ["A", "B"]
        let sync = coordinator(smallPolicy(monthsPerQuery: 3))
        await sync.runUntilIdle()
        XCTAssertLessThan(source.fetches.count, all.count)
        XCTAssertTrue(source.fetches.allSatisfy { $0.calendars == ["A", "B"] })
        XCTAssertEqual(try store.coverage().count, all.count * 2)
    }

    func testWiderHorizonFetchesOnlyTheNewMonths() async throws {
        await coordinator().runUntilIdle()
        source.resetLog()
        var wider = smallPolicy()
        wider.farMonths = 4
        await coordinator(wider).runUntilIdle()
        XCTAssertEqual(Set(source.fetchedMonths), [month("2026-06-01T00:00:00Z"), month("2027-02-01T00:00:00Z")])
    }

    func testEnsureJumpsTheQueueAndWaitsForTheCommit() async throws {
        source.events = [event("far", start: "2027-01-10T09:00:00Z", title: "Far away")]
        let sync = coordinator()
        let covered = await sync.ensure(DateInterval(start: date("2027-01-05T00:00:00Z"), duration: 86400))
        XCTAssertTrue(covered)
        XCTAssertEqual(source.fetchedMonths.first, month("2027-01-01T00:00:00Z"))
        XCTAssertEqual(try store.occurrences(in: MonthGrid.interval(of: month("2027-01-01T00:00:00Z"))).map(\.snapshot.title),
                       ["Far away"])
        XCTAssertEqual(source.fetchedMonths, [month("2027-01-01T00:00:00Z")], "only the asked-for month, not the whole fill")
        source.resetLog()
        let again = await sync.ensure(DateInterval(start: date("2027-01-05T00:00:00Z"), duration: 86400))
        XCTAssertTrue(again)
        XCTAssertEqual(source.fetches, [], "covered months return at once")
    }

    func testChangesWhileClosedAreCaughtAtLaunchWithoutAFullRescan() async throws {
        source.events = [event("a", start: "2026-10-05T09:00:00Z", title: "Before", external: "UID")]
        await coordinator().runUntilIdle()

        source.events = [event("a", start: "2026-10-05T09:00:00Z", title: "After", external: "UID")]
        source.resetLog()
        let relaunched = coordinator()
        await relaunched.noteLifecycle(.launch)
        await relaunched.runUntilIdle()
        XCTAssertEqual(try titles(), ["After"])
        XCTAssertEqual(Set(source.fetchedMonths), near, "only P0+P1 refetched")
    }

    func testChangeNotificationStormIsOnePassOverNearMonths() async throws {
        await coordinator().runUntilIdle()
        source.resetLog()
        let sync = coordinator()
        await sync.runUntilIdle()
        XCTAssertEqual(source.fetches, [])
        for _ in 0..<100 { await sync.applyChange() }
        await sync.runUntilIdle()
        XCTAssertEqual(source.fetchedMonths.sorted(), near.sorted())
    }

    func testDebouncedChangesCoalesce() async throws {
        let sync = coordinator()
        await sync.runUntilIdle()
        source.resetLog()
        for _ in 0..<50 { await sync.sourceChanged() }
        try await Task.sleep(for: .milliseconds(50))
        await sync.runUntilIdle()
        XCTAssertEqual(source.fetchedMonths.sorted(), near.sorted())
    }

    func testChangeDuringFetchSchedulesAnotherPass() async throws {
        source.events = [event("a", start: "2026-10-05T09:00:00Z", title: "Old", external: "UID")]
        let sync = coordinator()
        source.holdNextFetch()
        let run = Task { await sync.runUntilIdle() }
        await source.waitUntilHeld()
        // Changed after EventKit answered the held query.
        source.events = [event("a", start: "2026-10-05T09:00:00Z", title: "New", external: "UID")]
        await sync.applyChange()
        source.release()
        await run.value
        XCTAssertEqual(try titles(), ["New"])
        XCTAssertEqual(source.fetchedMonths.filter { $0 == p0[0] }.count, 2)
    }

    func testFailedFetchKeepsDataAndRetriesLater() async throws {
        source.events = [event("a", start: "2026-10-05T09:00:00Z", title: "Kept", external: "UID")]
        let sync = coordinator()
        await sync.runUntilIdle()

        source.events = []
        source.failMonths(Set(p0))
        await sync.applyChange()
        await sync.runUntilIdle()
        XCTAssertEqual(try titles(), ["Kept"], "a failed fetch never empties a month")
        let stillDue = await sync.pendingCount
        XCTAssertEqual(stillDue, 1)

        source.failMonths([])
        clock.advance(by: 3600)
        await sync.noteLifecycle(.activate)
        await sync.runUntilIdle()
        XCTAssertEqual(try titles(), [])
        let nothingDue = await sync.pendingCount
        XCTAssertEqual(nothingDue, 0)
    }

    func testCancelledRunDiscardsTheInFlightResult() async throws {
        source.events = [event("a", start: "2026-10-05T09:00:00Z", title: "Never written")]
        let sync = coordinator()
        source.holdNextFetch()
        let run = Task { await sync.runUntilIdle() }
        await source.waitUntilHeld()
        run.cancel()
        source.release()
        await run.value
        XCTAssertEqual(try store.allRows().count, 0)
        XCTAssertEqual(try store.coverage().count, 0)
    }

    func testRecurringFutureEditRefreshesTheTail() async throws {
        let weeks = stride(from: 0, to: 26, by: 1).map { week -> OccurrenceSnapshot in
            let start = date("2026-07-06T09:00:00Z").addingTimeInterval(Double(week) * 7 * 86400)
            var occurrence = event("w", start: "2026-07-06T09:00:00Z", title: "Weekly", external: "SERIES", recurring: true)
            occurrence.start = start
            occurrence.end = start.addingTimeInterval(3600)
            occurrence.occurrenceDate = start
            return occurrence
        }
        source.events = weeks
        let sync = coordinator()
        await sync.runUntilIdle()
        let ids = Set(try store.allRows().map(\.id))

        let pivot = date("2026-10-12T00:00:00Z")
        source.events = weeks.map { var o = $0; if o.start >= pivot { o.title = "Weekly v2" }; return o }
        await sync.noteWrite([DateInterval(start: pivot, end: date("2027-12-31T00:00:00Z"))], calendars: ["A"])
        await sync.runUntilIdle()

        let rows = try store.occurrences(in: DateInterval(start: date("2026-07-01T00:00:00Z"), end: date("2027-02-01T00:00:00Z")))
        XCTAssertTrue(rows.allSatisfy { ($0.snapshot.start >= pivot) == ($0.snapshot.title == "Weekly v2") })
        XCTAssertEqual(Set(rows.map(\.id)), ids, "same rows, rewritten in place")
    }

    func testPermissionLossErasesEverythingAndReturnRefills() async throws {
        source.events = [event("a", start: "2026-10-05T09:00:00Z", title: "Private")]
        let service = CalendarIndexService(store: store, source: source, policy: smallPolicy(), clock: clock)
        await service.coordinator.runUntilIdle()
        let october = MonthGrid.interval(of: p0[0])
        XCTAssertEqual(try service.occurrences(in: october).value.count, 1)

        source.authorizationStatus = .denied
        await service.coordinator.noteLifecycle(.activate)
        await service.coordinator.runUntilIdle()
        let denied = try service.occurrences(in: october)
        XCTAssertEqual(denied.authorization, .denied)
        XCTAssertEqual(denied.value.count, 0)
        XCTAssertEqual(try service.search(SearchRequest(text: "private")).value.count, 0)
        XCTAssertEqual(try store.allRows().count, 0, "nothing EventKit gave is kept")
        XCTAssertTrue(try store.coverage().isEmpty)

        source.authorizationStatus = .authorized
        await service.coordinator.noteLifecycle(.activate)
        await service.coordinator.runUntilIdle()
        XCTAssertEqual(try service.occurrences(in: october).value.map(\.snapshot.title), ["Private"])
    }

    /// The bug: a complete cache was served after access was revoked,
    /// because reads trusted a stored permission and nothing re-checked.
    func testReadsCheckThePermissionNowNotTheCache() async throws {
        source.events = [event("a", start: "2026-10-05T09:00:00Z", title: "Private")]
        let service = CalendarIndexService(store: store, source: source, policy: smallPolicy(), clock: clock)
        await service.coordinator.runUntilIdle()
        let october = MonthGrid.interval(of: p0[0])

        // Revoked; no sync runs, the cache is complete.
        source.authorizationStatus = .denied
        XCTAssertFalse(service.isAuthorized)
        XCTAssertEqual(try service.occurrences(in: october).value.count, 0)
        XCTAssertEqual(try service.dayMarkers(in: october).value.count, 0)
        XCTAssertEqual(try service.search(SearchRequest(text: "private")).value.count, 0)
        XCTAssertEqual(try service.searchMatches(SearchRequest(text: "private")).count, 0)
        XCTAssertEqual(try service.searchRanked(SearchRequest(text: "private")).count, 0)
        XCTAssertEqual(try service.occurrences(ids: store.allRows().map(\.id)).count, 0)
        XCTAssertEqual(try service.activeCalendars().count, 0)
    }

    func testRevokeErasesAndStartRefillsOnceAccessIsBack() async throws {
        source.events = [event("a", start: "2026-10-05T09:00:00Z", title: "Private")]
        let service = CalendarIndexService(store: store, source: source, policy: smallPolicy(), clock: clock)
        await service.coordinator.runUntilIdle()

        source.authorizationStatus = .denied
        await service.revoke()
        XCTAssertEqual(try store.allRows().count, 0)
        XCTAssertTrue(try store.coverage().isEmpty)
        XCTAssertTrue(try store.activeCalendars().isEmpty)

        source.authorizationStatus = .authorized
        await service.coordinator.noteLifecycle(.activate)
        await service.coordinator.runUntilIdle()
        XCTAssertEqual(try service.occurrences(in: MonthGrid.interval(of: p0[0])).value.map(\.snapshot.title), ["Private"])
    }

    func testAFetchThatEndsAfterRevocationIsNeverWritten() async throws {
        source.events = [event("a", start: "2026-10-05T09:00:00Z", title: "Private")]
        let sync = coordinator()
        source.holdNextFetch()
        let run = Task { await sync.runUntilIdle() }
        await source.waitUntilHeld()
        source.authorizationStatus = .denied
        source.release()
        await run.value
        XCTAssertEqual(try store.allRows().count, 0)
    }

    func testAccountReplacementFillsNewPartitionVisibleFirstWithoutDuplicates() async throws {
        source.events = [event("a", start: "2026-10-05T09:00:00Z", title: "Dentist", external: "UID")]
        let sync = coordinator()
        await sync.runUntilIdle()

        // Account removed and re-added: same events, new calendar identity.
        source.calendarIdentifiers = ["A2"]
        source.events = [event("a", calendar: "A2", start: "2026-10-05T09:00:00Z", title: "Dentist", external: "UID")]
        source.resetLog()
        await sync.applyChange()
        await sync.runUntilIdle()

        XCTAssertEqual(source.fetches.first?.calendars, ["A2"])
        XCTAssertEqual(source.fetchedMonths.first, p0[0])
        XCTAssertEqual(try store.occurrences(in: MonthGrid.interval(of: p0[0])).map(\.calendar.identifier), ["A2"])
        XCTAssertEqual(try store.search(SearchRequest(text: "dentist")).count, 1)
        XCTAssertEqual(try store.allRows().count, 1, "old partition purged in the background")
    }

    func testCommittedChangesArePublishedOnlyWhenRowsChange() async throws {
        let events = broadcaster.subscribe()
        source.events = [event("a", start: "2026-10-05T09:00:00Z", title: "One")]
        let sync = coordinator()
        await sync.runUntilIdle()
        await sync.applyChange()
        await sync.runUntilIdle()

        var committed: [IndexEvent] = []
        var iterator = events.makeAsyncIterator()
        while let event = await withTaskGroup(of: IndexEvent?.self, body: { group in
            group.addTask { await iterator.next() }
            group.addTask { try? await Task.sleep(for: .milliseconds(100)); return nil }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }) {
            if case .rangeCommitted = event { committed.append(event) }
        }
        XCTAssertEqual(committed.count, 1)
    }
}

final class SyncPlannerTests: XCTestCase {
    private let now = date("2026-10-15T12:00:00Z")

    func testOuterBandsProgressUnderAStormOfNearWork() {
        var policy = SyncPolicy()
        policy.outerEveryNChunks = 4
        let planner = SyncPlanner(policy: policy)
        let nearKeys = planner.nearMonths(now: now, focus: nil).map { WorkKey(calendarIdentifier: "A", month: $0) }
        var coverage: [WorkKey: Date] = [:]
        var nearSinceOuter = 0
        var outerPicks = 0
        for _ in 0..<50 {
            // Every near month is dirty again before each pick.
            let inputs = SyncPlanner.Inputs(now: now, focus: nil, calendars: ["A"], coverage: coverage, dirty: Set(nearKeys),
                                            urgent: [], blocked: [], outerAvailable: true, nearSinceOuter: nearSinceOuter,
                                            monthsPerQuery: 1)
            guard let batch = planner.next(inputs) else { return XCTFail("work expected") }
            for key in batch.keys { coverage[key] = now }
            if batch.band.isOuter { outerPicks += 1; nearSinceOuter = 0 } else { nearSinceOuter += 1 }
        }
        XCTAssertEqual(outerPicks, 10)
    }

    func testPacedOuterWorkIsHeldBackButUrgentAndNearAreNot() {
        let planner = SyncPlanner(policy: smallPolicy())
        let near = Set(planner.nearMonths(now: now, focus: nil).map { WorkKey(calendarIdentifier: "A", month: $0) })
        let coverage = Dictionary(uniqueKeysWithValues: near.map { ($0, now) })
        var inputs = SyncPlanner.Inputs(now: now, focus: nil, calendars: ["A"], coverage: coverage, dirty: [], urgent: [],
                                        blocked: [], outerAvailable: false, nearSinceOuter: 9, monthsPerQuery: 1)
        XCTAssertNil(planner.next(inputs), "only outer work is due, and it's paced")

        let urgent = WorkKey(calendarIdentifier: "A", month: month("2027-01-01T00:00:00Z"))
        inputs.urgent = [urgent]
        XCTAssertEqual(planner.next(inputs)?.keys, [urgent], "urgent work ignores pacing, even in outer months")

        inputs.urgent = []
        inputs.dirty = [near.first!]
        XCTAssertEqual(planner.next(inputs)?.band.isOuter, false)

        inputs.dirty = []
        inputs.outerAvailable = true
        XCTAssertEqual(planner.next(inputs)?.band.isOuter, true)
    }

    func testFocusFarAwayIsP0() {
        let planner = SyncPlanner(policy: smallPolicy())
        let focus = DateInterval(start: date("2031-03-10T00:00:00Z"), duration: 86400 * 7)
        XCTAssertEqual(planner.band(of: month("2031-03-01T00:00:00Z"), now: now, focus: focus), .visible)
        let inputs = SyncPlanner.Inputs(now: now, focus: focus, calendars: ["A"], coverage: [:], dirty: [], urgent: [],
                                        blocked: [], outerAvailable: true, nearSinceOuter: 0, monthsPerQuery: 1)
        XCTAssertEqual(planner.next(inputs)?.months, [month("2031-03-01T00:00:00Z")])
    }

    func testStaleMonthsRefreshAfterMaxAge() {
        let policy = smallPolicy()
        let planner = SyncPlanner(policy: policy)
        let months = planner.bandMonths(now: now, focus: nil)
        let coverage = Dictionary(uniqueKeysWithValues: months.map { (WorkKey(calendarIdentifier: "A", month: $0.month), now) })
        func next(at time: Date) -> SyncBatch? {
            planner.next(.init(now: time, focus: nil, calendars: ["A"], coverage: coverage, dirty: [], urgent: [], blocked: [],
                               outerAvailable: true, nearSinceOuter: 0, monthsPerQuery: 1))
        }
        XCTAssertNil(next(at: now))
        XCTAssertEqual(next(at: now.addingTimeInterval(policy.nearMaxAge.timeInterval))?.band, .visible)
    }
}

/// The real worker loop with real timers: start, react to a source change
/// notification, ensure, stop.
final class SyncWorkerTests: XCTestCase {
    func testBackgroundWorkerFillsReactsToChangesAndStops() async throws {
        let store = try makeStore()
        let source = FakeSnapshotSource(calendars: ["A"])
        let today = Date()
        var first = event("a", start: "2026-01-01T09:00:00Z", title: "First", external: "UID")
        first.start = today
        first.end = today.addingTimeInterval(3600)
        source.events = [first]
        var policy = smallPolicy(monthsPerQuery: 3)
        policy.changeDebounce = .milliseconds(20)
        let service = CalendarIndexService(store: store, source: source, policy: policy)
        let events = service.events()
        service.start()

        let ready = await service.ensure(DateInterval(start: today, duration: 3600))
        XCTAssertTrue(ready)
        XCTAssertEqual(try service.occurrences(in: DateInterval(start: today, duration: 3600)).value.map(\.snapshot.title), ["First"])

        var renamed = first
        renamed.title = "Renamed"
        source.events = [renamed]
        source.signalChange()
        for await event in events {
            if case .rangeCommitted = event,
               try service.search(SearchRequest(text: "renamed")).value.count == 1 { break }
        }
        await service.coordinator.stop()
    }

    func testBackgroundWorkerCompletesUnderLowPowerWithRealTimers() async throws {
        let store = try makeStore()
        let source = FakeSnapshotSource(calendars: ["A", "B"])
        var policy = smallPolicy()
        policy.lowPowerMinGap = .milliseconds(20)
        let broadcaster = IndexEventBroadcaster()
        let events = broadcaster.subscribe()
        let coordinator = SyncCoordinator(store: store, source: source, policy: policy, broadcaster: broadcaster,
                                          conditions: { SyncConditions(isLowPower: true) })
        await coordinator.start()
        var final: SyncProgress?
        for await event in events {
            if case .progress(let progress) = event, !progress.isRefreshing {
                final = progress
                break
            }
        }
        await coordinator.stop()
        XCTAssertEqual(final?.pacing, .lowPower)
        XCTAssertEqual(final?.coveredChunks, final?.totalChunks)
        XCTAssertEqual(final?.totalChunks, 14)
    }
}

final class WriteScopeTests: XCTestCase {
    private let now = date("2026-10-15T12:00:00Z")

    func testWriteRefetchesExactlyItsMonthsAndCalendarFirst() async throws {
        let store = try makeStore()
        let source = FakeSnapshotSource(calendars: ["A", "B"])
        let sync = SyncCoordinator(store: store, source: source, policy: smallPolicy(), clock: TestClock(now),
                                   conditions: { SyncConditions() })
        await sync.runUntilIdle()
        source.resetLog()

        let moved = DateInterval(start: date("2026-11-03T09:00:00Z"), duration: 3600)
        await sync.noteWrite([moved], calendars: ["B"])
        await sync.runUntilIdle()
        XCTAssertEqual(source.fetches.map(\.calendars), [["B"]])
        XCTAssertEqual(source.fetchedMonths, [month("2026-11-01T00:00:00Z")])
    }

    func testOpenEndedWriteStopsAtTheHorizon() async throws {
        let store = try makeStore()
        let source = FakeSnapshotSource(calendars: ["A"])
        let sync = SyncCoordinator(store: store, source: source, policy: smallPolicy(), clock: TestClock(now),
                                   conditions: { SyncConditions() })
        await sync.runUntilIdle()
        source.resetLog()

        await sync.noteWrite([DateInterval(start: date("2026-10-20T09:00:00Z"), end: .distantFuture)], calendars: ["A"])
        await sync.runUntilIdle()
        // Oct (P0) … Jan (far horizon with smallPolicy): the tail, nothing beyond.
        XCTAssertEqual(Set(source.fetchedMonths), Set(["2026-10-01", "2026-11-01", "2026-12-01", "2027-01-01"]
            .map { month($0 + "T00:00:00Z") }))
    }
}


final class PauseTests: XCTestCase {
    func testPauseHoldsOuterYearsButNotNearWorkAndResumeFinishes() async throws {
        let store = try makeStore()
        let source = FakeSnapshotSource(calendars: ["A"])
        let sync = SyncCoordinator(store: store, source: source, policy: smallPolicy(), clock: TestClock(date("2026-10-15T12:00:00Z")),
                                   conditions: { SyncConditions() })
        await sync.setPaused(true)
        await sync.runUntilIdle()
        let near = Set(["2026-09-01", "2026-10-01", "2026-11-01"].map { month($0 + "T00:00:00Z") })
        XCTAssertEqual(Set(source.fetchedMonths), near, "paused: only visible and near months")

        source.resetLog()
        await sync.applyChange()
        await sync.runUntilIdle()
        XCTAssertEqual(Set(source.fetchedMonths), near, "changes still sync while paused")

        await sync.setPaused(false)
        await sync.runUntilIdle()
        XCTAssertEqual(try store.coverage().count, 7, "resumed: the outer years fill")
    }
}
