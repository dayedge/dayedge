import Foundation
import GRDB

/// The index schema, as append-only named migrations.
///
/// Rules (the index is rebuildable, but a rebuild means refetching years of
/// EventKit data — migrate instead):
/// - Never edit a migration once shipped; add a new one.
/// - Never recreate the `occurrence` table: row ids are the occurrences'
///   stable ids.
/// - Structural change (a new queried column or index): ALTER/CREATE; if
///   the new column needs EventKit data, also `resetCoverage(db)` so every
///   month is refetched in priority order while old rows keep serving.
/// - FTS or tokenizer change: `recreateSearch(db, …)` — local only, keeps
///   rowids.
/// - Display-only snapshot fields: no migration — bump
///   `SnapshotFormat.version`.
public enum IndexMigrations {
    public typealias Migration = (identifier: String, migrate: @Sendable (Database) throws -> Void)

    public static let all: [Migration] = [
        ("v1-initial", { try v1($0) }),
        ("v2-status", { try v2Status($0) }),
        ("v3-organizer", { try v3Organizer($0) }),
        ("v4-organizer-is-me", { try v4OrganizerIsMe($0) })
    ]

    static func migrator(extra: [Migration] = [], eraseOnSchemaChange: Bool) -> DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.eraseDatabaseOnSchemaChange = eraseOnSchemaChange
        for migration in all + extra {
            migrator.registerMigration(migration.identifier, migrate: migration.migrate)
        }
        return migrator
    }

    @Sendable private static func v1(_ db: Database) throws {
        try db.execute(sql: """
            CREATE TABLE calendar (
                id INTEGER PRIMARY KEY,
                ek_identifier TEXT NOT NULL UNIQUE,
                payload BLOB NOT NULL,
                is_active INTEGER NOT NULL DEFAULT 1,
                inactive_since REAL
            );

            CREATE TABLE occurrence (
                id INTEGER PRIMARY KEY,
                calendar_id INTEGER NOT NULL REFERENCES calendar(id) ON DELETE CASCADE,
                occurrence_key TEXT NOT NULL,
                event_identifier TEXT,
                calendar_item_identifier TEXT NOT NULL,
                start REAL NOT NULL,
                "end" REAL NOT NULL,
                is_all_day INTEGER NOT NULL,
                participation TEXT,
                title TEXT NOT NULL,
                location TEXT,
                attendees_text TEXT,
                notes TEXT,
                fingerprint INTEGER NOT NULL,
                snapshot_version INTEGER NOT NULL,
                missing_since REAL,
                payload BLOB NOT NULL,
                UNIQUE (calendar_id, occurrence_key)
            );
            CREATE INDEX occurrence_start ON occurrence(start);
            CREATE INDEX occurrence_calendar_start ON occurrence(calendar_id, start);
            CREATE INDEX occurrence_missing ON occurrence(missing_since) WHERE missing_since IS NOT NULL;

            CREATE TABLE coverage (
                calendar_id INTEGER NOT NULL REFERENCES calendar(id) ON DELETE CASCADE,
                month_start REAL NOT NULL,
                fetched_at REAL NOT NULL,
                PRIMARY KEY (calendar_id, month_start)
            ) WITHOUT ROWID;

            CREATE TABLE meta (
                key TEXT PRIMARY KEY,
                value TEXT NOT NULL
            ) WITHOUT ROWID;
            """)
        try createSearch(db, columns: v1SearchColumns, tokenize: "unicode61 remove_diacritics 2", prefix: "2 3")
    }

    /// The event's status (cancelled by its organizer) as a column, so the
    /// month grid can apply the declined filter without decoding payloads.
    /// Needs EventKit data: every row is marked for rewrite and every month
    /// refetched in priority order; old rows keep serving (null = unknown,
    /// read as not cancelled) until then.
    @Sendable private static func v2Status(_ db: Database) throws {
        try db.execute(sql: "ALTER TABLE occurrence ADD COLUMN status TEXT")
        try db.execute(sql: "UPDATE occurrence SET snapshot_version = 0")
        try resetCoverage(db)
    }

    /// The organizer on its own (`attendees_text` has everyone), so search
    /// can tell who organized from who took part (`from:` / `with:`).
    /// Filled from the stored payloads — no EventKit refetch — and searched
    /// as a fifth FTS column (weight 0 in ranking: a filter only).
    @Sendable private static func v3Organizer(_ db: Database) throws {
        try db.execute(sql: "ALTER TABLE occurrence ADD COLUMN organizer_text TEXT")
        try backfillOrganizers(db)
        try recreateSearch(db, columns: searchColumns, tokenize: "unicode61 remove_diacritics 2", prefix: "2 3")
    }

    /// Whether the organizer is the user (`from:me`), from the payloads.
    @Sendable private static func v4OrganizerIsMe(_ db: Database) throws {
        try db.execute(sql: "ALTER TABLE occurrence ADD COLUMN organizer_is_me INTEGER NOT NULL DEFAULT 0")
        try backfillOrganizers(db)
    }

    /// Fills `organizer_text` and `organizer_is_me` from each row's stored
    /// payload.
    static func backfillOrganizers(_ db: Database) throws {
        let hasIsMe = try db.columns(in: "occurrence").contains { $0.name == "organizer_is_me" }
        let rows = try Row.fetchCursor(db, sql: "SELECT id, payload FROM occurrence")
        var updates: [OrganizerUpdate] = []
        while let row = try rows.next() {
            let payload: Data = row[1]
            guard let snapshot = try? SnapshotCoding.decode(OccurrenceSnapshot.self, from: payload),
                  let text = snapshot.organizerText else { continue }
            updates.append(OrganizerUpdate(id: row[0], text: text, isMe: snapshot.organizer?.isCurrentUser ?? false))
        }
        for update in updates {
            if hasIsMe {
                try db.execute(sql: "UPDATE occurrence SET organizer_text = ?, organizer_is_me = ? WHERE id = ?",
                               arguments: [update.text, update.isMe, update.id])
            } else {
                try db.execute(sql: "UPDATE occurrence SET organizer_text = ? WHERE id = ?", arguments: [update.text, update.id])
            }
        }
    }

    // MARK: - Helpers for future migrations

    /// The search columns as v1 created them (never change: v1 is shipped).
    static let v1SearchColumns = ["title", "location", "attendees_text", "notes"]
    /// The current search columns, in bm25 weight order.
    static let searchColumns = ["title", "location", "attendees_text", "notes", "organizer_text"]

    /// External-content FTS5 over `occurrence`, kept in sync by triggers.
    /// Raw SQL on purpose: independent of GRDB's FTS5 compile flag; macOS's
    /// system SQLite ships FTS5.
    static func createSearch(_ db: Database, columns searchColumns: [String], tokenize: String, prefix: String) throws {
        let columns = searchColumns.joined(separator: ", ")
        let old = searchColumns.map { "old.\($0)" }.joined(separator: ", ")
        let new = searchColumns.map { "new.\($0)" }.joined(separator: ", ")
        let changed = searchColumns.map { "old.\($0) IS NOT new.\($0)" }.joined(separator: " OR ")
        try db.execute(sql: """
            CREATE VIRTUAL TABLE occurrence_fts USING fts5(
                \(columns), content='occurrence', content_rowid='id',
                tokenize='\(tokenize)', prefix='\(prefix)'
            );
            CREATE TRIGGER occurrence_fts_insert AFTER INSERT ON occurrence BEGIN
                INSERT INTO occurrence_fts(rowid, \(columns)) VALUES (new.id, \(new));
            END;
            CREATE TRIGGER occurrence_fts_delete AFTER DELETE ON occurrence BEGIN
                INSERT INTO occurrence_fts(occurrence_fts, rowid, \(columns)) VALUES ('delete', old.id, \(old));
            END;
            CREATE TRIGGER occurrence_fts_update AFTER UPDATE ON occurrence WHEN \(changed) BEGIN
                INSERT INTO occurrence_fts(occurrence_fts, rowid, \(columns)) VALUES ('delete', old.id, \(old));
                INSERT INTO occurrence_fts(rowid, \(columns)) VALUES (new.id, \(new));
            END;
            """)
    }

    /// Replaces the search index (new tokenizer, prefix sizes…) and
    /// rebuilds it from `occurrence` — no EventKit refetch, rowids kept.
    public static func recreateSearch(_ db: Database, columns: [String], tokenize: String, prefix: String) throws {
        try db.execute(sql: """
            DROP TRIGGER IF EXISTS occurrence_fts_insert;
            DROP TRIGGER IF EXISTS occurrence_fts_delete;
            DROP TRIGGER IF EXISTS occurrence_fts_update;
            DROP TABLE IF EXISTS occurrence_fts;
            """)
        try createSearch(db, columns: columns, tokenize: tokenize, prefix: prefix)
        try db.execute(sql: "INSERT INTO occurrence_fts(occurrence_fts) VALUES ('rebuild')")
    }

    /// Marks every month as never fetched: the coordinator refetches all
    /// of them in priority order; existing rows keep serving meanwhile.
    public static func resetCoverage(_ db: Database) throws {
        try db.execute(sql: "UPDATE coverage SET fetched_at = 0")
    }
}

/// One row's organizer columns, as the v3/v4 backfill writes them.
private struct OrganizerUpdate {
    let id: Int64
    let text: String
    let isMe: Bool
}
