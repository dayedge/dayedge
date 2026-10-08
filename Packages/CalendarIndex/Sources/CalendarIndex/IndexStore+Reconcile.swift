import Foundation
import GRDB
import os

extension IndexStore {
    // MARK: - Reconcile

    // swiftlint:disable function_body_length - one month reconciled in one transaction
    /// Makes one calendar's month match a successful fetch, atomically.
    ///
    /// Call only with a fetch that succeeded for this calendar — never
    /// with an empty array standing in for a failure.
    ///
    /// - Ownership: only snapshots *starting* in the month are taken; an
    ///   event overlapping in from a neighbor belongs to that month.
    /// - Upsert by `(calendar, OccurrenceKey)` wherever the row lives now,
    ///   so a moved event keeps its row. Unchanged fingerprints aren't
    ///   written at all (no FTS churn).
    /// - Rows of this month that the fetch no longer has are soft-deleted:
    ///   hidden at once, revived if another month's fetch finds them.
    public func reconcile(calendarIdentifier: String, month: Date, snapshots: [OccurrenceSnapshot],
                          fetchedAt: Date) throws -> ReconcileResult {
        let interval = MonthGrid.interval(of: month)
        let owned = snapshots
            .filter { $0.calendarIdentifier == calendarIdentifier && interval.contains($0.start) && $0.start < interval.end }
            .sorted { ($0.calendarItemIdentifier, $0.start) < ($1.calendarItemIdentifier, $1.start) }

        // Encoding outside the write transaction keeps it short.
        var prepared: [PreparedOccurrence] = []
        var claimed: Set<String> = []
        for snapshot in owned {
            var key = OccurrenceKey.make(for: snapshot, calendar: keyCalendar)
            if !claimed.insert(key).inserted {
                key = OccurrenceKey.disambiguated(key, calendarItemIdentifier: snapshot.calendarItemIdentifier)
                claimed.insert(key)
            }
            let payload = try SnapshotCoding.payload(snapshot)
            prepared.append(PreparedOccurrence(key: key, snapshot: snapshot, payload: payload.data, fingerprint: payload.fingerprint))
        }

        return try pool.write { db in
            guard let calendarRowID = try Int64.fetchOne(
                db, sql: "SELECT id FROM calendar WHERE ek_identifier = ? AND is_active = 1", arguments: [calendarIdentifier]
            ) else { throw IndexStoreError.unknownCalendar(calendarIdentifier) }

            let start = interval.start.timeIntervalSince1970
            let end = interval.end.timeIntervalSince1970
            let before = try Int64.fetchSet(db, sql: """
                SELECT id FROM occurrence
                WHERE calendar_id = ? AND start >= ? AND start < ? AND missing_since IS NULL
                """, arguments: [calendarRowID, start, end])

            var result = ReconcileResult()
            var touched: Set<Int64> = []
            var span: (Double, Double)?
            func widen(_ a: Double, _ b: Double) {
                span = span.map { (min($0.0, a), max($0.1, b)) } ?? (a, b)
            }

            for item in prepared {
                var key = item.key
                var existing = try Self.fetchExisting(db, calendarRowID: calendarRowID, key: key)
                // Another live item elsewhere already owns this key: a
                // server-side duplicate UID, not a move. Keep both.
                if let row = existing, row.missingSince == nil, row.calendarItemIdentifier != item.snapshot.calendarItemIdentifier,
                   !(row.start >= start && row.start < end), !touched.contains(row.id) {
                    key = OccurrenceKey.disambiguated(key, calendarItemIdentifier: item.snapshot.calendarItemIdentifier)
                    existing = try Self.fetchExisting(db, calendarRowID: calendarRowID, key: key)
                }

                let s = item.snapshot
                let arguments: StatementArguments = [
                    s.eventIdentifier, s.calendarItemIdentifier, s.start.timeIntervalSince1970, s.end.timeIntervalSince1970,
                    s.isAllDay, s.participation?.rawValue, s.title, s.location, s.attendeesText, s.notes,
                    item.fingerprint, SnapshotFormat.version, item.payload, s.status.rawValue, s.organizerText,
                    s.organizer?.isCurrentUser ?? false
                ]
                guard let row = existing else {
                    try db.execute(sql: """
                        INSERT INTO occurrence (event_identifier, calendar_item_identifier, start, "end", is_all_day,
                            participation, title, location, attendees_text, notes, fingerprint, snapshot_version, payload,
                            status, organizer_text, organizer_is_me, calendar_id, occurrence_key)
                        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                        """, arguments: arguments + [calendarRowID, key])
                    touched.insert(db.lastInsertedRowID)
                    result.inserted += 1
                    widen(s.start.timeIntervalSince1970, s.end.timeIntervalSince1970)
                    continue
                }
                touched.insert(row.id)
                let revived = row.missingSince != nil
                guard revived || row.fingerprint != item.fingerprint || row.snapshotVersion != SnapshotFormat.version else {
                    result.unchanged += 1
                    continue
                }
                try db.execute(sql: """
                    UPDATE occurrence SET event_identifier = ?, calendar_item_identifier = ?, start = ?, "end" = ?,
                        is_all_day = ?, participation = ?, title = ?, location = ?, attendees_text = ?, notes = ?,
                        fingerprint = ?, snapshot_version = ?, payload = ?, status = ?, organizer_text = ?, organizer_is_me = ?, missing_since = NULL
                    WHERE id = ?
                    """, arguments: arguments + [row.id])
                if revived { result.revived += 1 } else { result.updated += 1 }
                widen(min(row.start, s.start.timeIntervalSince1970), max(row.end, s.end.timeIntervalSince1970))
            }

            for id in before.subtracting(touched) {
                try db.execute(sql: "UPDATE occurrence SET missing_since = ? WHERE id = ?",
                               arguments: [fetchedAt.timeIntervalSince1970, id])
                result.softDeleted += 1
                widen(start, end)
            }

            try db.execute(sql: """
                INSERT INTO coverage (calendar_id, month_start, fetched_at) VALUES (?, ?, ?)
                ON CONFLICT (calendar_id, month_start) DO UPDATE SET fetched_at = excluded.fetched_at
                """, arguments: [calendarRowID, start, fetchedAt.timeIntervalSince1970])

            if let longest = prepared.map({ $0.snapshot.end.timeIntervalSince($0.snapshot.start) }).max(),
               longest > (try Self.maxSpan(db)) {
                try Self.setMeta(db, "max_span", String(longest))
            }

            result.changedSpan = span.map {
                DateInterval(start: Date(timeIntervalSince1970: $0.0), end: Date(timeIntervalSince1970: max($0.0, $0.1)))
            }
            return result
        }
    }
    // swiftlint:enable function_body_length

    private struct ExistingRow {
        var id: Int64
        var fingerprint: Int64
        var snapshotVersion: Int
        var missingSince: Double?
        var calendarItemIdentifier: String
        var start: Double
        var end: Double
    }

    private static func fetchExisting(_ db: Database, calendarRowID: Int64, key: String) throws -> ExistingRow? {
        try Row.fetchOne(db, sql: """
            SELECT id, fingerprint, snapshot_version, missing_since, calendar_item_identifier, start, "end"
            FROM occurrence WHERE calendar_id = ? AND occurrence_key = ?
            """, arguments: [calendarRowID, key]).map {
            ExistingRow(id: $0[0], fingerprint: $0[1], snapshotVersion: $0[2], missingSince: $0[3],
                        calendarItemIdentifier: $0[4], start: $0[5], end: $0[6])
        }
    }
}
