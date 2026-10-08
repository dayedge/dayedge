import Foundation

/// Permission for a data source (Calendar, Reminders) as Settings presents
/// it: a status dot, a short label, and the one action that can change it.
/// Pure; the EventKit mapping lives in `EventKitAccess`.
package enum SourceAccessStatus: Equatable, Sendable {
    case granted
    case notDetermined
    case denied

    package var title: String {
        switch self {
        case .granted: return L10n.tr("sourceaccessstatus.full.access", "Full access")
        case .notDetermined: return L10n.tr("sourceaccessstatus.not.requested", "Not requested")
        case .denied: return L10n.tr("sourceaccessstatus.no.access", "No access")
        }
    }

    package var actionTitle: String? {
        switch self {
        case .granted: return nil
        case .notDetermined: return L10n.tr("sourceaccessstatus.allow.access", "Allow Access…")
        case .denied: return L10n.tr("sourceaccessstatus.open.system.settings", "Open System Settings…")
        }
    }
}
