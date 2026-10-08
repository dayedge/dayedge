import Foundation
import GRDB
import os

extension IndexStore {
    // MARK: - Calendars

    /// Applies EventKit's current calendar list. Unknown identifiers become
    /// new partitions; missing ones go inactive at once (hidden from every
    /// read) — never matched by name, and their rows are purged later.
    @discardableResult
    public func syncCalendars(_ calendars: [CalendarSnapshot], now: Date) throws -> CalendarInventoryChange {
        try pool.write { db in
            var change = CalendarInventoryChange()
            let rows = try Row.fetchAll(db, sql: "SELECT id, ek_identifier, payload, is_active FROM calendar")
            var stored: [String: StoredCalendar] = [:]
            for row in rows {
                stored[row["ek_identifier"]] = StoredCalendar(id: row["id"], payload: row["payload"], active: row["is_active"])
            }
            let current = Set(calendars.map(\.identifier))
            for calendar in calendars {
                let payload = try SnapshotCoding.encode(calendar)
                if let existing = stored[calendar.identifier] {
                    if !existing.active {
                        change.reactivated.append(calendar.identifier)
                    } else if existing.payload != payload {
                        change.updated.append(calendar.identifier)
                    }
                    if !existing.active || existing.payload != payload {
                        try db.execute(sql: "UPDATE calendar SET payload = ?, is_active = 1, inactive_since = NULL WHERE id = ?",
                                       arguments: [payload, existing.id])
                    }
                } else {
                    try db.execute(sql: "INSERT INTO calendar (ek_identifier, payload, is_active) VALUES (?, ?, 1)",
                                   arguments: [calendar.identifier, payload])
                    change.added.append(calendar.identifier)
                }
            }
            for (identifier, existing) in stored where existing.active && !current.contains(identifier) {
                try db.execute(sql: "UPDATE calendar SET is_active = 0, inactive_since = ? WHERE id = ?",
                               arguments: [now.timeIntervalSince1970, existing.id])
                change.deactivated.append(identifier)
            }
            return change
        }
    }

    public func activeCalendars() throws -> [CalendarSnapshot] {
        try pool.read { db in
            try Data.fetchAll(db, sql: "SELECT payload FROM calendar WHERE is_active = 1 ORDER BY id")
                .map { try SnapshotCoding.decode(CalendarSnapshot.self, from: $0) }
        }
    }

    // MARK: - Coverage

    /// When each (active calendar, month) was last fetched successfully.
    public func coverage() throws -> [WorkKey: Date] {
        try pool.read { db in
            var result: [WorkKey: Date] = [:]
            let rows = try Row.fetchAll(db, sql: """
                SELECT c.ek_identifier, v.month_start, v.fetched_at
                FROM coverage v JOIN calendar c ON c.id = v.calendar_id
                WHERE c.is_active = 1
                """)
            for row in rows {
                let key = WorkKey(calendarIdentifier: row[0], month: Date(timeIntervalSince1970: row[1]))
                result[key] = Date(timeIntervalSince1970: row[2])
            }
            return result
        }
    }
}
