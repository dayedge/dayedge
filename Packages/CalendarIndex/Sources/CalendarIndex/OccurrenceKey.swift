import Foundation

/// The index's own identity for an occurrence, unique per calendar —
/// stable across ordinary edits, moves, reschedules, time-zone changes and
/// sync round-trips, so those rewrite one row instead of replacing it.
///
/// - Item part: the server UID (`calendarItemExternalIdentifier`, which
///   survives local `eventIdentifier` churn) without Exchange's `/RID=…`
///   detached-occurrence suffix; `calendarItemIdentifier` when there is no
///   external identifier (local calendars).
/// - Occurrence part, repeating events only: the *original* occurrence
///   date (unchanged when one occurrence is moved) — UTC seconds for timed
///   events, the floating calendar date for all-day ones (EventKit hands
///   all-day dates out at local midnight, which moves with the time zone).
///   A non-repeating event has no date part, so moving it keeps its row.
public enum OccurrenceKey {
    public static func make(for snapshot: OccurrenceSnapshot, calendar: Calendar = .current) -> String {
        let item = itemPart(for: snapshot)
        guard snapshot.isRecurring else { return item }
        let original = snapshot.occurrenceDate ?? snapshot.start
        if snapshot.isAllDay {
            let parts = calendar.dateComponents([.year, .month, .day], from: original)
            return String(format: "%@@d%04d-%02d-%02d", item, parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
        }
        return "\(item)@t\(Int64(original.timeIntervalSince1970.rounded()))"
    }

    static func itemPart(for snapshot: OccurrenceSnapshot) -> String {
        if let external = snapshot.externalIdentifier, !external.isEmpty {
            return "x:" + seriesIdentifier(external)
        }
        return "i:" + snapshot.calendarItemIdentifier
    }

    /// The series' external identifier: Exchange appends "/RID=<n>" to a
    /// detached occurrence's (same rule as the app's
    /// `CalendarEventMapper.seriesIdentifier`).
    static func seriesIdentifier(_ externalIdentifier: String) -> String {
        guard let range = externalIdentifier.range(of: "/RID=") else { return externalIdentifier }
        return String(externalIdentifier[..<range.lowerBound])
    }

    /// The key for a second item claiming a key already taken (server-side
    /// duplicates of one UID): deterministic, by its own item identifier.
    static func disambiguated(_ key: String, calendarItemIdentifier: String) -> String {
        "\(key)#\(calendarItemIdentifier)"
    }
}
