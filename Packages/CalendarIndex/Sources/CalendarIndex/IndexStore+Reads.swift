import Foundation
import GRDB

/// Reads: concurrent with sync (WAL), milliseconds, safe to call from the
/// main thread. Every read shows only live rows (not soft-deleted) of
/// active calendars.
extension IndexStore {
    private static let occurrenceColumns = """
        o.id, o.occurrence_key, o.payload, c.ek_identifier, c.payload
        """

    /// Occurrences overlapping `interval`, by start. A zero-length event
    /// counts when it starts inside the interval.
    public func occurrences(in interval: DateInterval) throws -> [IndexedOccurrence] {
        try pool.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT \(Self.occurrenceColumns)
                FROM occurrence o JOIN calendar c ON c.id = o.calendar_id
                WHERE \(Self.overlapClause) AND o.missing_since IS NULL AND c.is_active = 1
                ORDER BY o.start, o.id
                """, arguments: try Self.overlapArguments(db, interval))
            var calendars: [String: CalendarSnapshot] = [:]
            return try rows.map { try Self.occurrence(from: $0, calendars: &calendars) }
        }
    }

    /// Month-grid markers: no payload decoding.
    public func dayMarkers(in interval: DateInterval) throws -> [DayMarker] {
        try pool.read { db in
            try Row.fetchAll(db, sql: """
                SELECT o.id, c.ek_identifier, o.start, o."end", o.is_all_day, o.participation, o.status
                FROM occurrence o JOIN calendar c ON c.id = o.calendar_id
                WHERE \(Self.overlapClause) AND o.missing_since IS NULL AND c.is_active = 1
                ORDER BY o.start, o.id
                """, arguments: try Self.overlapArguments(db, interval)).map { row in
                DayMarker(occurrenceID: row[0], calendarIdentifier: row[1],
                          start: Date(timeIntervalSince1970: row[2]), end: Date(timeIntervalSince1970: row[3]),
                          isAllDay: row[4], participation: (row[5] as String?).flatMap(ParticipationStatus.init(rawValue:)),
                          status: (row[6] as String?).flatMap(OccurrenceSnapshot.Status.init(rawValue:)))
            }
        }
    }

    /// Full-text search (title, location, people, notes), best first; ties
    /// by distance from `now`.
    public func search(_ request: SearchRequest, now: Date = Date()) throws -> [SearchHit] {
        guard request.limit > 0 else { return [] }
        return try pool.read { db in
            guard let filter = try Self.searchFilter(db, request) else { return [] }
            var arguments = filter.arguments
            arguments += [now.timeIntervalSince1970, request.limit]
            let rows = try Row.fetchAll(db, sql: """
                SELECT \(Self.occurrenceColumns), \(filter.rank) AS rank
                \(filter.from)
                WHERE \(filter.whereClause)
                ORDER BY rank, abs(o.start - ?)
                LIMIT ?
                """, arguments: arguments)
            var calendars: [String: CalendarSnapshot] = [:]
            return try rows.map { row in
                SearchHit(occurrence: try Self.occurrence(from: row, calendars: &calendars), rank: row["rank"])
            }
        }
    }

    /// Every match, in date order — ids and starts only (no payloads), so
    /// even thousands of matches are small. A search view builds its days
    /// from this and loads full occurrences by id for what's on screen.
    public func searchMatches(_ request: SearchRequest) throws -> [SearchMatch] {
        try pool.read { db in
            guard let filter = try Self.searchFilter(db, request) else { return [] }
            return try Row.fetchAll(db, sql: """
                SELECT o.id, o.start, o.is_all_day
                \(filter.from)
                WHERE \(filter.whereClause)
                ORDER BY o.start, o.id
                """, arguments: filter.arguments).map {
                SearchMatch(id: $0[0], start: Date(timeIntervalSince1970: $0[1]), isAllDay: $0[2])
            }
        }
    }

    /// Candidates for ranking a few top results, with their titles (no
    /// payloads) and bm25 scores (title weighted most, then location,
    /// people, notes). Three lists of up to `limit` each, merged without
    /// duplicates:
    /// - the best text matches (ties: closest to `now`),
    /// - the nearest matches — upcoming from `upcomingFrom` soonest first,
    ///   then the most recent past (where browsing starts),
    /// - the nearest *title* matches, the same way.
    /// So a caller can rank title matches above the rest and, within that,
    /// by closeness — even when thousands match (an attendee's name).
    public func searchRanked(_ request: SearchRequest, now: Date = Date(), upcomingFrom: Date? = nil) throws -> [RankedMatch] {
        guard request.limit > 0 else { return [] }
        let boundary = (upcomingFrom ?? now).timeIntervalSince1970
        return try pool.read { db in
            guard let filter = try Self.searchFilter(db, request) else { return [] }
            // The same request with every word required in the title.
            var titled = request
            titled.titleText = [request.titleText, request.text].compactMap { $0 }.joined(separator: " ")
            titled.text = ""
            let titleFilter = try Self.searchFilter(db, titled)
            func fetch(_ filter: SearchSQL?, order: String, _ orderArguments: StatementArguments) throws -> [RankedMatch] {
                guard let filter else { return [] }
                var arguments = filter.arguments
                arguments += orderArguments
                arguments += [request.limit]
                return try Row.fetchAll(db, sql: """
                    SELECT o.id, o.start, o.is_all_day, o.title, \(filter.rank) AS rank
                    \(filter.from)
                    WHERE \(filter.whereClause)
                    ORDER BY \(order)
                    LIMIT ?
                    """, arguments: arguments).map {
                    RankedMatch(match: SearchMatch(id: $0[0], start: Date(timeIntervalSince1970: $0[1]), isAllDay: $0[2]),
                                title: $0[3], rank: $0["rank"])
                }
            }
            let nearest = "o.start < ?, CASE WHEN o.start >= ? THEN o.start ELSE -o.start END, rank"
            let lists = [
                try fetch(filter, order: "rank, abs(o.start - ?)", [now.timeIntervalSince1970]),
                try fetch(filter, order: nearest, [boundary, boundary]),
                try fetch(titleFilter, order: nearest, [boundary, boundary])
            ]
            var seen: Set<Int64> = []
            return lists.joined().filter { seen.insert($0.match.id).inserted }
        }
    }

    /// People whose name or email starts with `prefix` (any word of it,
    /// diacritics and case ignored; empty: everyone), most frequent first.
    public func people(_ role: IndexedPerson.Role, prefix: String, limit: Int = 5) throws -> [IndexedPerson] {
        let column = role == .organizer ? "organizer_text" : "attendees_text"
        let words = SearchQuery.ftsExpression(for: prefix).map { "\(column) : (\($0))" }
        return try pool.read { db in
            let sql = words == nil
                ? "SELECT o.\(column), COUNT(*) FROM occurrence o JOIN calendar c ON c.id = o.calendar_id"
                    + " WHERE o.\(column) IS NOT NULL AND o.missing_since IS NULL AND c.is_active = 1 GROUP BY o.\(column)"
                : "SELECT o.\(column), COUNT(*) FROM occurrence_fts JOIN occurrence o ON o.id = occurrence_fts.rowid"
                    + " JOIN calendar c ON c.id = o.calendar_id"
                    + " WHERE occurrence_fts MATCH ? AND o.missing_since IS NULL AND c.is_active = 1 GROUP BY o.\(column)"
            let rows = try Row.fetchAll(db, sql: sql, arguments: words.map { [$0] } ?? [])
            var counts: [IndexedPerson: Int] = [:]
            for row in rows {
                guard let text: String = row[0] else { continue }
                for person in Self.people(in: text) { counts[person, default: 0] += row[1] }
            }
            let needle = SearchQuery.folded(prefix)
            return counts
                .filter { person, _ in
                    needle.isEmpty || [person.name, person.email].compactMap { $0 }.contains { value in
                        SearchQuery.folded(value).split(whereSeparator: { !$0.isLetter && !$0.isNumber }).contains { $0.hasPrefix(needle) }
                    }
                }
                .map { IndexedPerson(name: $0.key.name, email: $0.key.email, count: $0.value) }
                .sorted { ($0.count, $1.displayName) > ($1.count, $0.displayName) }
                .prefix(limit).map { $0 }
        }
    }

    /// "name\nemail\nname\nemail…" (either may be missing) → people.
    private static func people(in text: String) -> [IndexedPerson] {
        var result: [IndexedPerson] = []
        var pendingName: String?
        for line in text.split(separator: "\n").map(String.init) {
            if line.contains("@") {
                result.append(IndexedPerson(name: pendingName, email: line, count: 0))
                pendingName = nil
            } else {
                if let pendingName { result.append(IndexedPerson(name: pendingName, email: nil, count: 0)) }
                pendingName = line
            }
        }
        if let pendingName { result.append(IndexedPerson(name: pendingName, email: nil, count: 0)) }
        return result
    }

    /// Full occurrences for these row ids (live, active calendars), in date
    /// order — the window a search view shows.
    public func occurrences(ids: [Int64]) throws -> [IndexedOccurrence] {
        guard !ids.isEmpty else { return [] }
        return try pool.read { db in
            var calendars: [String: CalendarSnapshot] = [:]
            var result: [IndexedOccurrence] = []
            for chunk in stride(from: 0, to: ids.count, by: 500).map({ Array(ids[$0..<min($0 + 500, ids.count)]) }) {
                let rows = try Row.fetchAll(db, sql: """
                    SELECT \(Self.occurrenceColumns)
                    FROM occurrence o JOIN calendar c ON c.id = o.calendar_id
                    WHERE o.id IN (\(Array(repeating: "?", count: chunk.count).joined(separator: ",")))
                      AND o.missing_since IS NULL AND c.is_active = 1
                    """, arguments: StatementArguments(chunk))
                result += try rows.map { try Self.occurrence(from: $0, calendars: &calendars) }
            }
            return result.sorted { ($0.snapshot.start, $0.id) < ($1.snapshot.start, $1.id) }
        }
    }

    /// A search's FROM, rank and WHERE: full-text when there are words to
    /// match; without words (only a date range) a plain scan of the range
    /// with no rank.
    struct SearchSQL {
        var from: String
        var rank: String
        var clauses: [String]
        var arguments: StatementArguments
        var whereClause: String { clauses.joined(separator: " AND ") }
    }

    /// The user's own events: they organized it, or it has no organizer
    /// (an event of their own, without invitees) on a calendar they can
    /// edit — not a subscription or birthdays, which have none either.
    static let organizedByMeClause = """
        (o.organizer_is_me = 1 OR (o.organizer_text IS NULL
            AND json_extract(CAST(c.payload AS TEXT), '$.allowsModifications') = 1
            AND json_extract(CAST(c.payload AS TEXT), '$.sourceKind') NOT IN ('subscribed', 'birthdays')))
        """

    /// bm25 weights in `IndexMigrations.searchColumns` order: title most,
    /// then location and people, notes least; the organizer column only
    /// filters (`from:`).
    static let rankExpression = "bm25(occurrence_fts, 10.0, 3.0, 3.0, 1.0, 0.0)"

    /// What a search shares (nil: nothing can match). Declined means
    /// declined by me and not cancelled by the organizer — the agenda's
    /// rule.
    static func searchFilter(_ db: Database, _ request: SearchRequest) throws -> SearchSQL? {
        let expression = SearchQuery.ftsExpression(for: request)
        guard expression != nil || request.interval != nil || request.organizedByMe else { return nil }
        var sql = expression == nil
            ? SearchSQL(from: "FROM occurrence o JOIN calendar c ON c.id = o.calendar_id", rank: "0.0", clauses: [], arguments: [])
            : SearchSQL(from: """
                FROM occurrence_fts JOIN occurrence o ON o.id = occurrence_fts.rowid JOIN calendar c ON c.id = o.calendar_id
                """, rank: rankExpression, clauses: ["occurrence_fts MATCH ?"], arguments: [expression!])
        sql.clauses += ["o.missing_since IS NULL", "c.is_active = 1"]
        if request.organizedByMe { sql.clauses.append(organizedByMeClause) }
        if let interval = request.interval {
            sql.clauses.append(overlapClause)
            sql.arguments += try overlapArguments(db, interval)
        }
        if let included = request.includedCalendars {
            guard !included.isEmpty else { return nil }
            sql.clauses.append("c.ek_identifier IN (\(Array(repeating: "?", count: included.count).joined(separator: ",")))")
            sql.arguments += StatementArguments(Array(included))
        }
        if !request.excludedCalendars.isEmpty {
            sql.clauses.append("c.ek_identifier NOT IN (\(Array(repeating: "?", count: request.excludedCalendars.count).joined(separator: ",")))")
            sql.arguments += StatementArguments(Array(request.excludedCalendars))
        }
        if !request.includesDeclined {
            sql.clauses.append("NOT (o.participation IS 'declined' AND (o.status IS NULL OR o.status != 'canceled'))")
        }
        return sql
    }

    /// Which months of `interval` aren't indexed yet for every active
    /// calendar, and the oldest refresh among those that are.
    public func coverageInfo(for interval: DateInterval, isRefreshing: Bool = false) throws -> CoverageInfo {
        let months = MonthGrid.months(overlapping: interval)
        return try pool.read { db in
            let active = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM calendar WHERE is_active = 1") ?? 0
            guard let first = months.first, let last = months.last else {
                return CoverageInfo(missingMonths: [], oldestFetch: nil, isRefreshing: isRefreshing)
            }
            let rows = try Row.fetchAll(db, sql: """
                SELECT v.month_start, COUNT(*), MIN(v.fetched_at)
                FROM coverage v JOIN calendar c ON c.id = v.calendar_id
                WHERE c.is_active = 1 AND v.month_start >= ? AND v.month_start <= ?
                GROUP BY v.month_start
                """, arguments: [first.timeIntervalSince1970, last.timeIntervalSince1970])
            var counts: [Double: Int] = [:]
            var oldest: Double?
            for row in rows {
                counts[row[0]] = row[1]
                let fetched: Double = row[2]
                oldest = min(oldest ?? fetched, fetched)
            }
            // No calendars known yet (a new index before its first
            // inventory): nothing is covered, not everything.
            let missing = active == 0 ? months : months.filter { (counts[$0.timeIntervalSince1970] ?? 0) < active }
            return CoverageInfo(missingMonths: missing, oldestFetch: oldest.map(Date.init(timeIntervalSince1970:)),
                                isRefreshing: isRefreshing)
        }
    }

    // MARK: - Helpers

    /// `start < end-of-range AND (end > start-of-range OR starts inside)`,
    /// bounded below by the longest stored duration so it stays on the
    /// `start` index even with multi-day events.
    private static let overlapClause = """
        o.start < ? AND o.start >= ? AND (o."end" > ? OR o.start >= ?)
        """

    private static func overlapArguments(_ db: Database, _ interval: DateInterval) throws -> StatementArguments {
        let start = interval.start.timeIntervalSince1970
        let end = interval.end.timeIntervalSince1970
        return [end, start - (try maxSpan(db)) - 1, start, start]
    }

    static func occurrence(from row: Row, calendars: inout [String: CalendarSnapshot]) throws -> IndexedOccurrence {
        let calendarIdentifier: String = row[3]
        let calendar: CalendarSnapshot
        if let cached = calendars[calendarIdentifier] {
            calendar = cached
        } else {
            calendar = try SnapshotCoding.decode(CalendarSnapshot.self, from: row[4])
            calendars[calendarIdentifier] = calendar
        }
        let key: String = row[1]
        return IndexedOccurrence(id: row[0], stableKey: "\(calendarIdentifier)|\(key)",
                                 snapshot: try SnapshotCoding.decode(OccurrenceSnapshot.self, from: row[2]),
                                 calendar: calendar)
    }
}
