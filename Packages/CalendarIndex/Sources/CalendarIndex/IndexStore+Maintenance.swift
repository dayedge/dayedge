import Foundation
import GRDB
import os

extension IndexStore {
    // MARK: - Maintenance

    /// Hard-deletes soft-deleted rows once they can no longer come back:
    /// every covered month of their calendar has been refetched since they
    /// went missing (had they moved within coverage, they'd have been
    /// revived), or they're older than `ttl`.
    @discardableResult
    public func purgeTombstones(now: Date, ttl: Duration, limit: Int = 500) throws -> Int {
        try pool.write { db in
            try db.execute(sql: """
                DELETE FROM occurrence WHERE id IN (
                    SELECT o.id FROM occurrence o
                    WHERE o.missing_since IS NOT NULL AND (
                        o.missing_since < ?
                        OR o.missing_since <= (SELECT MIN(v.fetched_at) FROM coverage v WHERE v.calendar_id = o.calendar_id)
                    )
                    LIMIT ?
                )
                """, arguments: [now.timeIntervalSince1970 - ttl.timeInterval, limit])
            return db.changesCount
        }
    }

    /// Deletes rows of inactive calendars in small batches; the calendar
    /// row itself goes once it's empty. Already hidden from every read.
    @discardableResult
    public func purgeInactive(limit: Int = 500) throws -> Int {
        try pool.write { db in
            try db.execute(sql: """
                DELETE FROM occurrence WHERE id IN (
                    SELECT o.id FROM occurrence o JOIN calendar c ON c.id = o.calendar_id
                    WHERE c.is_active = 0 LIMIT ?
                )
                """, arguments: [limit])
            let deleted = db.changesCount
            try db.execute(sql: """
                DELETE FROM calendar WHERE is_active = 0
                AND NOT EXISTS (SELECT 1 FROM occurrence o WHERE o.calendar_id = calendar.id)
                """)
            return deleted + db.changesCount
        }
    }

    // MARK: - Reindex

    /// Every calendar, occurrence and covered month gone (the schema and
    /// non-calendar metadata stay): the index starts over from the source.
    /// Also what losing Calendar access does — nothing EventKit gave is
    /// kept. The search index is emptied whole, not row by row.
    public func eraseAll() throws {
        try pool.write { db in
            // The search triggers would delete row by row; they're set
            // aside (as defined, whatever the tokenizer) and the search
            // index is emptied at once.
            let triggers = try String.fetchAll(db, sql: """
                SELECT sql FROM sqlite_master WHERE type = 'trigger' AND tbl_name = 'occurrence' AND name LIKE 'occurrence_fts_%'
                """)
            for name in try String.fetchAll(db, sql: """
                SELECT name FROM sqlite_master WHERE type = 'trigger' AND tbl_name = 'occurrence' AND name LIKE 'occurrence_fts_%'
                """) {
                try db.execute(sql: "DROP TRIGGER \(name)")
            }
            try db.execute(sql: """
                INSERT INTO occurrence_fts(occurrence_fts) VALUES ('delete-all');
                DELETE FROM coverage;
                DELETE FROM occurrence;
                DELETE FROM calendar;
                DELETE FROM meta WHERE key = 'max_span';
                DELETE FROM meta WHERE key = 'source_authorization';
                """)
            for trigger in triggers { try db.execute(sql: trigger) }
        }
        // Give the space back (outside the transaction).
        try pool.writeWithoutTransaction { db in try db.execute(sql: "VACUUM") }
    }

    // MARK: - Meta

    static func maxSpan(_ db: Database) throws -> Double {
        try String.fetchOne(db, sql: "SELECT value FROM meta WHERE key = 'max_span'").flatMap(Double.init) ?? 0
    }

    static func setMeta(_ db: Database, _ key: String, _ value: String) throws {
        try db.execute(sql: """
            INSERT INTO meta (key, value) VALUES (?, ?)
            ON CONFLICT (key) DO UPDATE SET value = excluded.value
            """, arguments: [key, value])
    }
}
