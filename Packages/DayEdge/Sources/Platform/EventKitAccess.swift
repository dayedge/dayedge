import AppKit
import EventKit
import Domain

/// Requests Calendar access exactly once (no-op if already granted or
/// already denied) and reports whether reads are authorized. A bare,
/// unsigned executable has no code-signed identity of its own, so the
/// resulting TCC prompt may be attributed to the parent process (e.g. the
/// terminal) rather than "the app" until this ships inside a real signed
/// .app bundle — the request itself still works the same way either way.
package enum EventKitAccess {
    /// Every calendar (or Reminders list, with `.reminder`) EventKit knows
    /// about, as view-safe values with a readable account name and kind.
    package static func calendarSources(eventStore: EKEventStore, entity: EKEntityType = .event) -> [CalendarSource] {
        eventStore.calendars(for: entity).map { calendar in
            let kind = sourceKind(for: calendar.source)
            return CalendarSource(
                id: calendar.calendarIdentifier,
                title: calendar.title,
                tint: RGBAColor(calendar.color),
                sourceTitle: SourceDisplayName.name(rawTitle: calendar.source?.title, kind: kind),
                sourceID: calendar.source?.sourceIdentifier ?? "",
                sourceKind: kind,
                allowsModifications: calendar.allowsContentModifications
            )
        }
    }

    package static func sourceKind(for source: EKSource?) -> SourceKind {
        guard let source else { return .other }
        let title = source.title.lowercased()
        switch source.sourceType {
        case .local: return .local
        case .exchange: return .exchange
        case .subscribed: return .subscribed
        case .birthdays: return .birthdays
        case .mobileMe: return .iCloud
        case .calDAV:
            if title.contains("icloud") { return .iCloud }
            if title.contains("google") || title.contains("gmail") { return .google }
            return .calDAV
        @unknown default: return .other
        }
    }

    /// Permission for `entity` as Settings presents it. Write-only and
    /// restricted count as denied: the app needs to read.
    package static func status(for entity: EKEntityType) -> SourceAccessStatus {
        switch EKEventStore.authorizationStatus(for: entity) {
        case .fullAccess: return .granted
        case .notDetermined: return .notDetermined
        default: return .denied
        }
    }

    package static func privacySettingsURL(for entity: EKEntityType) -> URL {
        let pane = entity == .reminder ? "Privacy_Reminders" : "Privacy_Calendars"
        return URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)")!
    }

    package static func openPrivacySettings(for entity: EKEntityType) {
        NSWorkspace.shared.open(privacySettingsURL(for: entity))
    }

    package static func requestAccessIfNeeded(eventStore: EKEventStore) async -> Bool {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess:
            return true
        case .notDetermined:
            return (try? await eventStore.requestFullAccessToEvents()) ?? false
        case .restricted, .denied, .writeOnly:
            return false
        @unknown default:
            return false
        }
    }
}
