import Foundation
import GRDB
import os

/// One (calendar, month) coverage cell — the unit of reconciliation.
public struct WorkKey: Hashable, Sendable, CustomStringConvertible {
    public var calendarIdentifier: String
    /// Start of a UTC month (`MonthGrid`).
    public var month: Date

    public init(calendarIdentifier: String, month: Date) {
        self.calendarIdentifier = calendarIdentifier
        self.month = month
    }

    public var description: String {
        "\(calendarIdentifier)@\(ISO8601DateFormatter().string(from: month).prefix(7))"
    }
}

/// What one reconciliation did. `changed` rows were written; `unchanged`
/// rows were fetched again but not touched.
public struct ReconcileResult: Sendable, Equatable {
    public var inserted = 0
    public var updated = 0
    public var revived = 0
    public var softDeleted = 0
    public var unchanged = 0

    public var changedCount: Int { inserted + updated + revived + softDeleted }
    /// Where changed rows were and now are — for `.rangeCommitted`.
    public var changedSpan: DateInterval?
}

public struct CalendarInventoryChange: Sendable, Equatable {
    public var added: [String] = []
    public var deactivated: [String] = []
    public var reactivated: [String] = []
    public var updated: [String] = []

    public var isEmpty: Bool { added.isEmpty && deactivated.isEmpty && reactivated.isEmpty && updated.isEmpty }
}

public enum IndexStoreError: Error {
    /// The database was written by a newer version of the app (unknown migrations).
    case superseded
    case unknownCalendar(String)
}

/// The SQLite mirror: one serial writer with short per-(calendar, month)
/// transactions, concurrent readers (WAL), so reads and search never wait
/// on sync. Rebuildable, but never thrown away for an ordinary error.
public final class IndexStore: Sendable {
    public struct Options: Sendable {
        /// DEBUG convenience while a migration is being written: wipe the
        /// database when a registered migration's schema changes.
        public var eraseOnSchemaChange: Bool
        /// Extra migrations after `IndexMigrations.all` (tests).
        public var extraMigrations: [IndexMigrations.Migration] = []
        public var busyTimeout: TimeInterval = 5
        public var openAttempts = 3
        public var retryBackoff: TimeInterval = 0.2
        /// The calendar all-day occurrence keys use (floating dates).
        public var keyCalendar: Calendar = .autoupdatingCurrent

        public init() {
            #if DEBUG
            eraseOnSchemaChange = true
            #else
            eraseOnSchemaChange = false
            #endif
        }
    }

    static let logger = Logger(subsystem: "com.dayedge.calendarindex", category: "store")

    let pool: DatabasePool
    public let url: URL
    let keyCalendar: Calendar

    private init(pool: DatabasePool, url: URL, keyCalendar: Calendar) throws {
        self.pool = pool
        self.url = url
        self.keyCalendar = keyCalendar
    }

    /// `~/Library/Application Support/<app>/Index/calendar-index.sqlite`
    public static func defaultURL() throws -> URL {
        let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                  appropriateFor: nil, create: true)
        return support.appendingPathComponent("DayEdge/Index/calendar-index.sqlite")
    }

    // MARK: - Open and recover

    /// Opens (creating or migrating) the index at `url`.
    ///
    /// - Transient errors (busy, locked, I/O, full): retried with backoff;
    ///   data is kept.
    /// - Written by a newer build, a failed migration, or confirmed
    ///   corruption: a replacement database is built beside it and swapped
    ///   in; coverage starts empty and refills in priority order.
    public static func open(at url: URL, options: Options = Options()) throws -> IndexStore {
        try prepareDirectory(for: url)
        var lastError: Error?
        for attempt in 0..<max(1, options.openAttempts) {
            do {
                return try openMigrated(at: url, options: options)
            } catch let error where isTransient(error) {
                lastError = error
                logger.error("open attempt \(attempt + 1) failed (transient): \(String(describing: error), privacy: .public)")
                Thread.sleep(forTimeInterval: options.retryBackoff * pow(2, Double(attempt)))
            } catch {
                logger.error("index unusable, replacing: \(String(describing: error), privacy: .public)")
                return try replace(at: url, options: options)
            }
        }
        throw lastError ?? DatabaseError(resultCode: .SQLITE_BUSY)
    }

    private static func openMigrated(at url: URL, options: Options) throws -> IndexStore {
        var configuration = Configuration()
        configuration.busyMode = .timeout(options.busyTimeout)
        configuration.label = "CalendarIndex"
        let pool = try DatabasePool(path: url.path, configuration: configuration)
        do {
            let migrator = IndexMigrations.migrator(extra: options.extraMigrations,
                                                    eraseOnSchemaChange: options.eraseOnSchemaChange)
            if try pool.read({ try migrator.hasBeenSuperseded($0) }) {
                throw IndexStoreError.superseded
            }
            try migrator.migrate(pool)
            try pool.write { db in
                // Integrity is cheap on an index this size and the only
                // reliable signal of a corrupt-but-openable file.
                if let result = try String.fetchOne(db, sql: "PRAGMA quick_check"), result != "ok" {
                    throw DatabaseError(resultCode: .SQLITE_CORRUPT, message: result)
                }
            }
            restrictPermissions(url)
            return try IndexStore(pool: pool, url: url, keyCalendar: options.keyCalendar)
        } catch {
            try? pool.close()
            throw error
        }
    }

    private static func replace(at url: URL, options: Options) throws -> IndexStore {
        let replacement = url.appendingPathExtension("new")
        removeDatabaseFiles(at: replacement)
        do {
            var configuration = Configuration()
            configuration.busyMode = .timeout(options.busyTimeout)
            let pool = try DatabasePool(path: replacement.path, configuration: configuration)
            try IndexMigrations.migrator(extra: options.extraMigrations, eraseOnSchemaChange: false).migrate(pool)
            try pool.close()
        }
        removeDatabaseFiles(at: url)
        try FileManager.default.moveItem(at: replacement, to: url)
        return try openMigrated(at: url, options: options)
    }

    static func isTransient(_ error: Error) -> Bool {
        guard let error = error as? DatabaseError else { return false }
        switch error.resultCode {
        case .SQLITE_BUSY, .SQLITE_LOCKED, .SQLITE_IOERR, .SQLITE_FULL, .SQLITE_CANTOPEN, .SQLITE_PROTOCOL:
            return true
        default:
            return false
        }
    }

    private static func prepareDirectory(for url: URL) throws {
        var directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? directory.setResourceValues(values)
    }

    private static func restrictPermissions(_ url: URL) {
        for path in [url.path, url.path + "-wal", url.path + "-shm"] where FileManager.default.fileExists(atPath: path) {
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path)
        }
    }

    private static func removeDatabaseFiles(at url: URL) {
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(atPath: url.path + suffix)
        }
    }

    public func close() throws {
        try pool.close()
    }
}

/// A calendar row as `updateCalendars` compares it.
struct StoredCalendar {
    let id: Int64
    let payload: Data
    let active: Bool
}

/// An occurrence encoded before the write transaction.
struct PreparedOccurrence {
    let key: String
    let snapshot: OccurrenceSnapshot
    let payload: Data
    let fingerprint: Int64
}
