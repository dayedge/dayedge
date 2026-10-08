import Foundation

/// What kind of account a source belongs to. Drives the friendly fallback
/// name when EventKit hands back nothing readable.
package enum SourceKind: String, Hashable, Sendable {
    case iCloud, exchange, google, calDAV, local, subscribed, birthdays, other
}
