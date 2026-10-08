import XCTest
@testable import Domain
@testable import Intelligence

@MainActor
final class AssistantMemoryBoundsTests: XCTestCase {
    private typealias T = AssistantTestData

    private func context(_ data: LookupData, now: Date = T.now) -> AssistantToolContext {
        AssistantToolContext(data: data, calendar: T.calendar, now: { now })
    }

    private func section(_ date: Date, id: String, title: String, end: Date? = nil) -> AgendaDaySection {
        .init(date: date, events: [.init(id: id, startTime: "12:00", endTime: "13:00", startDate: date,
                                       endDate: end ?? date.addingTimeInterval(13 * 3_600), title: title)])
    }

    func testWideLookupKeepsLateExactMatchAndCurrentOccurrence() async throws {
        let first = T.calendar.date(from: DateComponents(year: 2026, month: 1, day: 1))!
        let last = T.calendar.date(from: DateComponents(year: 2026, month: 12, day: 31))!
        let end = T.calendar.date(byAdding: .day, value: 1, to: last)!
        let data = LookupData(sections: [section(first, id: "old", title: "Daily"),
                                         section(T.date(23), id: "current", title: "Daily"),
                                         section(last, id: "late", title: "Daily")])
        let ctx = context(data)
        let details = try await EventDetailsTool.find("daily", in: .init(start: first, end: end), context: ctx)
        guard case .found(let selected, _) = details else { return XCTFail("uniform titles should choose a current occurrence") }
        XCTAssertEqual(selected.id, "current")
        let calls = await data.calls()
        XCTAssertEqual(calls.count, 12)
        XCTAssertTrue(calls.allSatisfy { AssistantWhen.days(in: $0, calendar: T.calendar, limit: 32).count <= 31 })

        let resolverData = LookupData(sections: [section(first, id: "loose", title: "Déjà later"),
                                                 section(last, id: "exact", title: "DEJA")])
        let resolved = try await AssistantTargetResolver.event("“déjà”", when: "2026-01-01..2026-12-31", context: context(resolverData))
        guard case .found(let exact) = resolved else { return XCTFail("a late exact match outranks an earlier loose match") }
        XCTAssertEqual(exact.id, "exact")
    }

    func testHalfOpenChunkBoundariesAndDSTDoNotRepeatOrAddEndDay() async throws {
        var calendar = T.calendar
        calendar.timeZone = TimeZone(identifier: "Europe/Warsaw")!
        let first = calendar.date(from: DateComponents(year: 2026, month: 3, day: 20))!
        let end = calendar.date(byAdding: .day, value: 70, to: first)!
        let sections = (0...70).map { offset in section(calendar.date(byAdding: .day, value: offset, to: first)!, id: "e\(offset)", title: "Event") }
        let data = LookupData(sections: sections, includesEndDay: true)
        let ctx = AssistantToolContext(data: data, calendar: calendar)
        var seen: [Date] = []
        try await AssistantEventLookup.scan(in: .init(start: first, end: end), context: ctx) { seen.append($0.date) }
        XCTAssertEqual(seen.count, 70)
        XCTAssertEqual(Set(seen).count, 70)
        XCTAssertFalse(seen.contains(end))
        let calls = await data.calls()
        XCTAssertEqual(calls.map { AssistantWhen.days(in: $0, calendar: calendar, limit: 32).count }, [31, 31, 8])
        XCTAssertEqual(calls[0].duration + 1, 31 * 86_400 - 3_600, accuracy: 0.01)
        XCTAssertEqual(calls.last?.end.addingTimeInterval(1), end)
    }

    func testResolverDeduplicatesBeforeMatchingAcrossChunks() async throws {
        let first = T.date(1), boundary = T.calendar.date(byAdding: .day, value: 31, to: first)!
        let data = LookupData(sections: [section(first, id: "same", title: "Other"),
                                         section(boundary, id: "same", title: "Target"),
                                         section(boundary, id: "unique", title: "Target")])
        let outcome = try await AssistantTargetResolver.event("Target", when: "2026-09-01..2026-11-01", context: context(data))
        guard case .found(let event) = outcome else { return XCTFail("the first occurrence of an ID is authoritative") }
        XCTAssertEqual(event.id, "unique")

        let trip = LookupData(sections: [section(first, id: "trip", title: "Trip"), section(boundary, id: "trip", title: "Trip")])
        let resolved = try await AssistantTargetResolver.event("Trip", when: "2026-09-01..2026-11-01", context: context(trip))
        guard case .found(let event) = resolved else { return XCTFail("one multi-day event is not ambiguous") }
        XCTAssertEqual(event.id, "trip")
    }

    func testDetailsPreserveMultiDayOccurrenceAndRawTitleSemantics() async throws {
        let first = T.date(1), later = T.calendar.date(byAdding: .day, value: 31, to: first)!
        let data = LookupData(sections: [section(first, id: "same", title: "Trip", end: T.date(1, month: 11)),
                                         section(later, id: "same", title: "Trip", end: T.date(1, month: 11))])
        let match = try await EventDetailsTool.find("trip", in: .init(start: first, end: T.date(1, month: 11)), context: context(data))
        guard case .found(_, let day) = match else { return XCTFail("same titles keep existing occurrence semantics") }
        XCTAssertEqual(day, first)
        let mixed = LookupData(sections: [section(first, id: "a", title: "Trip"), section(later, id: "b", title: "TRIP")])
        let differing = try await EventDetailsTool.find("trip", in: .init(start: first, end: T.date(1, month: 11)), context: context(mixed))
        guard case .several(let choices) = differing else { return XCTFail("raw title comparison remains case-sensitive") }
        XCTAssertEqual(choices.count, 2)
    }

    func testCandidatePreviewCannotTurnNineDistinctTargetsIntoOne() async throws {
        let data = LookupData(sections: (0..<12).map { section(T.date(24), id: "e\($0)", title: "Target") })
        let ctx = context(data)
        let result = try await AssistantTargetResolver.event("Target", when: "tomorrow", context: ctx)
        guard case .unresolved(let text) = result else { return XCTFail("all distinct matches must count") }
        XCTAssertTrue(text.hasPrefix("Several events match"))
        XCTAssertNotNil(ctx.references.reference(for: "E8"))
        XCTAssertNil(ctx.references.reference(for: "E9"))

        let varied = LookupData(sections: (0..<12).map { section(T.date(24), id: "e\($0)", title: "Target \($0)") })
        let choices = try await EventDetailsTool.find("Target", in: .init(start: T.date(24), end: T.date(25)), context: context(varied))
        guard case .several(let candidates) = choices else { return XCTFail("different titles must remain ambiguous") }
        XCTAssertEqual(candidates.count, 8)
    }

    func testContainingPrecedesReverseContainingAndFinalPastOccurrenceWins() async throws {
        let data = LookupData(sections: [section(T.date(20), id: "reverse", title: "Dentist"),
                                         section(T.date(21), id: "containing", title: "Dentist checkup agenda")])
        let result = try await AssistantTargetResolver.event("Dentist checkup", when: "2026-09-20..2026-09-21", context: context(data))
        guard case .found(let found) = result else { return XCTFail("containing titles outrank reverse-containing ones") }
        XCTAssertEqual(found.id, "containing")
        let past = LookupData(sections: [section(T.date(20), id: "old", title: "Daily"), section(T.date(21), id: "last", title: "Daily")])
        let detail = try await EventDetailsTool.find("Daily", in: .init(start: T.date(20), end: T.date(22)), context: context(past))
        guard case .found(let last, _) = detail else { return XCTFail("past-only uniform titles resolve to the last occurrence") }
        XCTAssertEqual(last.id, "last")
    }

    func testListingFormatsOnlyReturnedItemsAndPreservesOmissionCount() async throws {
        var ctx = T.context(tasks: (0..<5).map { TaskItem(id: "t\($0)", title: "Task \($0)", listID: "work", sourceOrder: $0) })
        ctx.maxLines = 3
        let answer = await TaskListTool.answer(filter: .open, list: nil, context: ctx)
        XCTAssertTrue(answer.contains("…and 3 more"), answer)
        XCTAssertNotNil(ctx.references.reference(for: "T2"))
        XCTAssertNil(ctx.references.reference(for: "T3"))
        XCTAssertTrue(answer.hasSuffix(AssistantFormat.referenceHint))
        var agenda = T.context(events: [23: (0..<5).map { T.event("A\($0)", day: 23) },
                                       24: (0..<5).map { T.event("B\($0)", day: 24) }])
        agenda.maxLines = 3
        let listed = await AgendaTool.answer(for: .init(start: T.date(23), end: T.date(25)), context: agenda)
        XCTAssertTrue(listed.contains("…and 10 more"), listed)
        XCTAssertNotNil(agenda.references.reference(for: "E1"))
        XCTAssertNil(agenda.references.reference(for: "E2"))
        XCTAssertNotNil(agenda.references.reference(for: "D1"))
        XCTAssertNil(agenda.references.reference(for: "D2"))
    }

    func testDetailsUseOneOperationClockSnapshot() async throws {
        let clock = AdvancingClock()
        let data = LookupData(sections: [section(T.date(23), id: "current", title: "Daily"),
                                         section(T.date(24), id: "next", title: "Daily")])
        var ctx = context(data)
        ctx.now = { clock.read() }
        let result = try await EventDetailsTool.find("Daily", in: .init(start: T.date(23), end: T.date(25)), context: ctx)
        guard case .found(let event, _) = result else { return XCTFail("operation-time occurrence should resolve") }
        XCTAssertEqual(event.id, "current")
        XCTAssertEqual(clock.count, 1)
    }

    func testDefaultLookupRangesKeepTheirExistingEndpoints() async throws {
        let detailsData = LookupData(sections: [])
        _ = try await EventDetailsTool.find("Missing", in: nil, context: context(detailsData))
        let detailsCalls = await detailsData.calls()
        XCTAssertEqual(detailsCalls.first?.start, T.date(16))
        XCTAssertEqual(detailsCalls.last?.end.addingTimeInterval(1), T.date(24, month: 10))
        let resolverData = LookupData(sections: [])
        _ = try await AssistantTargetResolver.event("Missing", when: nil, context: context(resolverData))
        let resolverCalls = await resolverData.calls()
        XCTAssertEqual(resolverCalls.first?.start, T.date(16))
        XCTAssertEqual(resolverCalls.last?.end.addingTimeInterval(1), T.date(22, month: 11))
    }

    func testCancellationAfterFinalDetailsReadReturnsNoPartialAnswerOrReferences() async throws {
        let data = LookupData(sections: [section(T.date(24), id: "e", title: "Target")], pausesFirstRead: true)
        let ctx = context(data)
        let tool = EventDetailsTool.make(ctx)
        let task = Task { try await tool.call(.init(["event": .string("Target"), "when": .string("tomorrow")])) }
        while await data.calls().isEmpty { await Task.yield() }
        task.cancel()
        await data.resume()
        do { _ = try await task.value; XCTFail("the final read must also check cancellation") } catch is CancellationError {} catch { XCTFail("\(error)") }
        XCTAssertNil(ctx.references.reference(for: "E1"))
        let calls = await data.calls()
        XCTAssertEqual(calls.count, 1)
    }

    func testCancelledLookupPropagatesThroughToolAndCannotProposeOrWriteChanges() async throws {
        let data = LookupData(sections: [section(T.date(24), id: "e", title: "Target")], pausesFirstRead: true)
        let writer = FakeChangeWriter(), approvals = ChatApprovals()
        var ctx = context(data)
        ctx.changes = writer
        ctx.approvals = approvals
        let tool = EventChangeTools.update(ctx)
        let task = Task { try await tool.call(.init(["event": .string("Target"), "title": .string("Changed"),
                                                   "when": .string("2026-01-01..2026-12-31")])) }
        while await data.calls().isEmpty { await Task.yield() }
        task.cancel()
        await data.resume()
        do { _ = try await task.value; XCTFail("cancellation must not become a tool text answer") } catch is CancellationError {} catch { XCTFail("\(error)") }
        XCTAssertNil(approvals.pending)
        XCTAssertTrue(writer.eventUpdates.isEmpty)
        XCTAssertTrue(writer.eventCreates.isEmpty)
        XCTAssertTrue(writer.eventDeletes.isEmpty)
        let calls = await data.calls()
        XCTAssertEqual(calls.count, 1)
    }
}

private actor LookupData: AssistantDataSource {
    let sections: [AgendaDaySection]
    let includesEndDay: Bool
    let pausesFirstRead: Bool
    private var ranges: [DateInterval] = []
    private var continuation: CheckedContinuation<Void, Never>?

    init(sections: [AgendaDaySection], includesEndDay: Bool = false, pausesFirstRead: Bool = false) {
        self.sections = sections
        self.includesEndDay = includesEndDay
        self.pausesFirstRead = pausesFirstRead
    }

    func agenda(in range: DateInterval, calendar: Calendar) async -> [AgendaDaySection] {
        ranges.append(range)
        if pausesFirstRead, ranges.count == 1 { await withCheckedContinuation { continuation = $0 } }
        return sections.filter {
            $0.date >= calendar.startOfDay(for: range.start)
                && (includesEndDay ? $0.date <= calendar.startOfDay(for: range.end) : $0.date < range.end)
        }
    }
    func taskSnapshot() async -> AssistantTaskSnapshot { .init(tasks: [], lists: []) }
    func holidays(in range: DateInterval, calendar: Calendar) async -> AssistantHolidays { .init() }
    func calls() -> [DateInterval] { ranges }
    func resume() { continuation?.resume(); continuation = nil }
}

private final class AdvancingClock: @unchecked Sendable {
    private let lock = NSLock()
    private var reads = 0
    var count: Int { lock.withLock { reads } }
    func read() -> Date {
        lock.withLock {
            defer { reads += 1 }
            return reads == 0 ? AssistantTestData.now : AssistantTestData.now.addingTimeInterval(86_400)
        }
    }
}
