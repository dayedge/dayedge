import AppKit
import Domain
import Foundation

/// Isolates the app's one use of the undocumented `ical://ekevent`
/// Calendar.app deep link behind a single seam — URL construction never
/// happens anywhere else (`EventActionCoordinator` only ever calls this).
/// No fallback: if this fails, `openWithDetails` just returns `false` and
/// the caller does nothing further, per explicit product decision — the
/// previously shipped `calshow:` fallback didn't actually work and was
/// removed outright rather than kept as a second broken path.
package final class AppleCalendarBridge: AppleCalendarOpening {
    package init() {}

    private static let occurrenceDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        return formatter
    }()

    /// `calendarItemIdentifier` becomes exactly one URL path component —
    /// percent-encoded against a narrowed allowed set (path-allowed minus
    /// `/?#`) rather than the plain `.urlPathAllowed` set, since that set
    /// still permits characters that would restructure the URL if they
    /// ever appeared in an identifier. Real identifiers are UUIDs today,
    /// but this doesn't assume that. `internal`, not `private`, so tests
    /// can exercise the URL shape directly without going through
    /// `NSWorkspace`.
    package static func deepLinkURL(calendarItemIdentifier: String, occurrenceDate: Date) -> URL? {
        let datePart = occurrenceDateFormatter.string(from: occurrenceDate)
        let allowed = CharacterSet.urlPathAllowed.subtracting(CharacterSet(charactersIn: "/?#"))
        guard let encodedID = calendarItemIdentifier.addingPercentEncoding(withAllowedCharacters: allowed) else {
            return nil
        }
        return URL(string: "ical://ekevent/\(datePart)/\(encodedID)?method=show&options=more")
    }

    @discardableResult
    package func openWithDetails(calendarItemIdentifier: String, occurrenceDate: Date) -> Bool {
        guard let url = Self.deepLinkURL(calendarItemIdentifier: calendarItemIdentifier, occurrenceDate: occurrenceDate) else {
            return false
        }
        return NSWorkspace.shared.open(url)
    }
}
