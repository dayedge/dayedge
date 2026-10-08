import Foundation

/// Priority band of a month. P0 follows the visible range; P1–P3 are
/// distances from today's month (`SyncHorizons`).
public enum SyncBand: Int, Comparable, Sendable {
    case visible = 0, near, mid, far

    var isOuter: Bool { self >= .mid }

    public static func < (a: SyncBand, b: SyncBand) -> Bool { a.rawValue < b.rawValue }
}

/// One EventKit query: some calendars × contiguous months.
struct SyncBatch: Equatable {
    var calendars: [String]
    /// Ascending, contiguous.
    var months: [Date]
    var band: SyncBand
    var isUrgent: Bool

    var range: DateInterval {
        DateInterval(start: months.first!, end: MonthGrid.month(months.last!, adding: 1))
    }

    var keys: [WorkKey] {
        calendars.flatMap { calendar in months.map { WorkKey(calendarIdentifier: calendar, month: $0) } }
    }
}

/// Pure scheduling: given what's covered, dirty and urgent, which chunk
/// runs next. Kept apart from `SyncCoordinator` (which does the I/O) so
/// the policy is testable without timing — and so scheduling never
/// affects reconciliation correctness, only order.
struct SyncPlanner {
    struct Inputs {
        var now: Date
        var focus: DateInterval?
        var calendars: [String]
        var coverage: [WorkKey: Date]
        var dirty: Set<WorkKey>
        /// Most urgent first.
        var urgent: [WorkKey]
        var blocked: Set<WorkKey>
        /// False while outer chunks are paced (waiting out their gap);
        /// urgent and near work is never paced.
        var outerAvailable: Bool
        var nearSinceOuter: Int
        var monthsPerQuery: Int
    }

    var policy: SyncPolicy

    func todayMonth(_ now: Date) -> Date { MonthGrid.month(containing: now) }

    func visibleMonths(now: Date, focus: DateInterval?) -> [Date] {
        let base = focus ?? DateInterval(start: now, duration: 0)
        let first = MonthGrid.month(MonthGrid.month(containing: base.start), adding: -policy.visiblePaddingMonths)
        let lastStart = base.duration > 0 ? base.end.addingTimeInterval(-0.001) : base.start
        let last = MonthGrid.month(MonthGrid.month(containing: lastStart), adding: policy.visiblePaddingMonths)
        return MonthGrid.months(overlapping: DateInterval(start: first, end: MonthGrid.month(last, adding: 1)))
    }

    func band(of month: Date, now: Date, focus: DateInterval?) -> SyncBand? {
        if visibleMonths(now: now, focus: focus).contains(month) { return .visible }
        let distance = abs(MonthGrid.distance(from: todayMonth(now), to: month))
        if distance <= policy.nearMonths { return .near }
        if distance <= policy.midMonths { return .mid }
        if distance <= policy.farMonths { return .far }
        return nil
    }

    /// Every month the index keeps, with its band.
    func bandMonths(now: Date, focus: DateInterval?) -> [(month: Date, band: SyncBand)] {
        let today = todayMonth(now)
        let visible = Set(visibleMonths(now: now, focus: focus))
        var result = visible.sorted().map { (month: $0, band: SyncBand.visible) }
        for offset in -policy.farMonths...policy.farMonths {
            let month = MonthGrid.month(today, adding: offset)
            guard !visible.contains(month), let band = band(of: month, now: now, focus: focus) else { continue }
            result.append((month, band))
        }
        return result
    }

    /// Months in P0 ∪ P1 — what a change notification refetches.
    func nearMonths(now: Date, focus: DateInterval?) -> [Date] {
        bandMonths(now: now, focus: focus).filter { !$0.band.isOuter }.map(\.month)
    }

    func isDue(_ key: WorkKey, band: SyncBand, _ inputs: Inputs) -> Bool {
        if inputs.blocked.contains(key) { return false }
        if inputs.dirty.contains(key) { return true }
        guard let fetched = inputs.coverage[key] else { return true }
        let maxAge = band.isOuter ? policy.farMaxAge : policy.nearMaxAge
        return inputs.now.timeIntervalSince(fetched) >= maxAge.timeInterval
    }

    // swiftlint:disable:next cyclomatic_complexity - the planning order: urgent, then near, then outer months
    func next(_ inputs: Inputs) -> SyncBatch? {
        let calendars = Set(inputs.calendars)
        if let first = inputs.urgent.first(where: { calendars.contains($0.calendarIdentifier) && !inputs.blocked.contains($0) }) {
            return urgentBatch(from: first, inputs)
        }

        struct Candidate { var key: WorkKey; var band: SyncBand; var order: SyncOrder }
        let today = todayMonth(inputs.now)
        var near: [Candidate] = []
        var outer: [Candidate] = []
        for (month, band) in bandMonths(now: inputs.now, focus: inputs.focus) {
            if band.isOuter && !inputs.outerAvailable { continue }
            for calendar in inputs.calendars {
                let key = WorkKey(calendarIdentifier: calendar, month: month)
                guard isDue(key, band: band, inputs) else { continue }
                // Dirty first, then never-fetched (outward from today),
                // then stale (oldest first).
                let order: SyncOrder
                if inputs.dirty.contains(key) {
                    order = (0, abs(MonthGrid.distance(from: today, to: month)), 0)
                } else if let fetched = inputs.coverage[key] {
                    order = (2, 0, fetched.timeIntervalSince1970)
                } else {
                    order = (1, abs(MonthGrid.distance(from: today, to: month)), 0)
                }
                let candidate = Candidate(key: key, band: band, order: order)
                if band.isOuter { outer.append(candidate) } else { near.append(candidate) }
            }
        }
        let preferOuter = inputs.nearSinceOuter >= policy.outerEveryNChunks && !outer.isEmpty
        let pool = preferOuter || near.isEmpty ? outer : near
        guard let best = pool.min(by: { ($0.band, $0.order.0, $0.order.1, $0.order.2) < ($1.band, $1.order.0, $1.order.1, $1.order.2) })
        else { return nil }

        // Every calendar due in that month rides along in the same query.
        let month = best.key.month
        let batchCalendars = inputs.calendars.filter {
            isDue(WorkKey(calendarIdentifier: $0, month: month), band: best.band, inputs)
        }
        // Extend away from today while the same calendars are due in the
        // same near/outer group.
        let step = month < today ? -1 : 1
        var months = [month]
        while months.count < max(1, inputs.monthsPerQuery) {
            let candidate = MonthGrid.month(step < 0 ? months.first! : months.last!, adding: step)
            guard let band = band(of: candidate, now: inputs.now, focus: inputs.focus), band.isOuter == best.band.isOuter,
                  batchCalendars.allSatisfy({ isDue(WorkKey(calendarIdentifier: $0, month: candidate), band: band, inputs) })
            else { break }
            if step < 0 { months.insert(candidate, at: 0) } else { months.append(candidate) }
        }
        return SyncBatch(calendars: batchCalendars, months: months, band: best.band, isUrgent: false)
    }

    private func urgentBatch(from first: WorkKey, _ inputs: Inputs) -> SyncBatch {
        let urgent = Set(inputs.urgent).subtracting(inputs.blocked)
        let calendarsInMonth = inputs.calendars.filter { urgent.contains(WorkKey(calendarIdentifier: $0, month: first.month)) }
        var months = [first.month]
        while months.count < max(1, inputs.monthsPerQuery) {
            let candidate = MonthGrid.month(months.last!, adding: 1)
            guard calendarsInMonth.allSatisfy({ urgent.contains(WorkKey(calendarIdentifier: $0, month: candidate)) }) else { break }
            months.append(candidate)
        }
        let band = self.band(of: first.month, now: inputs.now, focus: inputs.focus) ?? .visible
        return SyncBatch(calendars: calendarsInMonth, months: months, band: band, isUrgent: true)
    }
}

// Which due month goes first: (kind, distance, last fetch), compared in
// that order.
private typealias SyncOrder = (Int, Int, Double) // swiftlint:disable:this large_tuple - compared lexicographically
