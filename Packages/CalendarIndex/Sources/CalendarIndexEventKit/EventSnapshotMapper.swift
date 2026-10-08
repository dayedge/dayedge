import CalendarIndex
import EventKit
import Foundation

/// `EKEvent`/`EKCalendar` → plain snapshots. The only code in the index
/// that touches EventKit objects; runs on `EventKitSnapshotSource`'s queue.
///
/// Captures what the app reads from an event (its `CalendarEventMapper`
/// rules and `ReminderMapper` recurrence parsing work on these values).
enum EventSnapshotMapper {
    static func snapshot(of event: EKEvent, series: SeriesRuleLookup) -> OccurrenceSnapshot? {
        guard let calendar = event.calendar, let start = event.startDate, let end = event.endDate,
              let itemIdentifier = event.calendarItemIdentifier as String? else { return nil }
        // EventKit returns attendees in a different order on every fetch;
        // a fixed order keeps the fingerprint (and the display) stable.
        let attendees = (event.attendees ?? []).map(attendee).sorted {
            (($0.name ?? "").lowercased(), $0.email ?? "") < (($1.name ?? "").lowercased(), $1.email ?? "")
        }
        let isRecurring = event.hasRecurrenceRules || event.isDetached || SeriesRuleLookup.looksLikeOccurrence(event)
        let ownRule = event.recurrenceRules?.first
        let rule = ownRule ?? series.rules(for: event)?.first
        return OccurrenceSnapshot(
            calendarIdentifier: calendar.calendarIdentifier,
            eventIdentifier: event.eventIdentifier,
            calendarItemIdentifier: itemIdentifier,
            externalIdentifier: event.calendarItemExternalIdentifier,
            occurrenceDate: event.occurrenceDate,
            start: start,
            end: end,
            isAllDay: event.isAllDay,
            timeZone: event.timeZone?.identifier,
            title: event.title ?? "",
            location: event.location,
            notes: event.notes,
            url: event.url?.absoluteString,
            attendees: attendees,
            organizer: event.organizer.map { OrganizerSnapshot(name: $0.name, email: email(of: $0), isCurrentUser: $0.isCurrentUser) },
            status: status(event.status),
            participation: (event.attendees ?? []).first(where: \.isCurrentUser).map { participation($0.participantStatus) },
            availability: availability(event.availability),
            isRecurring: isRecurring,
            isDetached: event.isDetached,
            hasOwnRecurrenceRules: event.hasRecurrenceRules,
            recurrence: rule.map(recurrence),
            alarms: (event.alarms ?? []).map {
                AlarmSnapshot(relativeOffset: $0.absoluteDate == nil ? $0.relativeOffset : nil, absoluteDate: $0.absoluteDate,
                              isLocationBased: $0.structuredLocation != nil)
            },
            hasAttendees: !attendees.isEmpty,
            isInvitation: !attendees.isEmpty && event.organizer?.isCurrentUser != true,
            created: event.creationDate,
            modified: event.lastModifiedDate
        )
    }

    static func snapshot(of calendar: EKCalendar) -> CalendarSnapshot {
        let color = calendar.cgColor.flatMap { $0.converted(to: CGColorSpace(name: CGColorSpace.sRGB)!, intent: .defaultIntent, options: nil) }
        let components = color?.components ?? [0.5, 0.5, 0.5, 1]
        return CalendarSnapshot(
            identifier: calendar.calendarIdentifier,
            title: calendar.title,
            sourceIdentifier: calendar.source?.sourceIdentifier ?? "",
            sourceTitle: calendar.source?.title ?? "",
            sourceKind: sourceKind(calendar.source?.sourceType),
            color: .init(red: Double(components[safe: 0] ?? 0.5), green: Double(components[safe: 1] ?? 0.5),
                         blue: Double(components[safe: 2] ?? 0.5), alpha: Double(components[safe: 3] ?? 1)),
            allowsModifications: calendar.allowsContentModifications
        )
    }

    private static func attendee(_ participant: EKParticipant) -> AttendeeSnapshot {
        AttendeeSnapshot(name: participant.name, email: email(of: participant),
                         status: participation(participant.participantStatus), isCurrentUser: participant.isCurrentUser)
    }

    /// The app's exact rule (`CalendarEventMapper.email(for:)`): a
    /// `mailto:` URL is the only place EventKit surfaces an address.
    private static func email(of participant: EKParticipant) -> String? {
        let url = participant.url
        guard url.scheme?.lowercased() == "mailto" else { return nil }
        return url.absoluteString.replacingOccurrences(of: "mailto:", with: "").removingPercentEncoding
    }

    static func participation(_ status: EKParticipantStatus) -> ParticipationStatus {
        switch status {
        case .pending: return .pending
        case .accepted: return .accepted
        case .declined: return .declined
        case .tentative: return .tentative
        case .delegated: return .delegated
        case .completed: return .completed
        case .inProcess: return .inProcess
        case .unknown: return .unknown
        @unknown default: return .unknown
        }
    }

    private static func status(_ status: EKEventStatus) -> OccurrenceSnapshot.Status {
        switch status {
        case .confirmed: return .confirmed
        case .tentative: return .tentative
        case .canceled: return .canceled
        case .none: return .none
        @unknown default: return .none
        }
    }

    private static func availability(_ availability: EKEventAvailability) -> OccurrenceSnapshot.Availability {
        switch availability {
        case .busy: return .busy
        case .free: return .free
        case .tentative: return .tentative
        case .unavailable: return .unavailable
        case .notSupported: return .notSupported
        @unknown default: return .notSupported
        }
    }

    private static func sourceKind(_ type: EKSourceType?) -> CalendarSnapshot.SourceKind {
        switch type {
        case .local: return .local
        case .exchange: return .exchange
        case .calDAV: return .calDAV
        case .mobileMe: return .mobileMe
        case .subscribed: return .subscribed
        case .birthdays: return .birthdays
        default: return .other
        }
    }

    static func recurrence(_ rule: EKRecurrenceRule) -> RecurrenceDescription {
        let frequency: RecurrenceDescription.Frequency
        switch rule.frequency {
        case .daily: frequency = .daily
        case .weekly: frequency = .weekly
        case .monthly: frequency = .monthly
        case .yearly: frequency = .yearly
        @unknown default: frequency = .daily
        }
        let end: RecurrenceDescription.End? = rule.recurrenceEnd.flatMap { end in
            if let date = end.endDate { return .date(date) }
            return end.occurrenceCount > 0 ? .count(end.occurrenceCount) : nil
        }
        return RecurrenceDescription(
            frequency: frequency,
            interval: rule.interval,
            daysOfWeek: rule.daysOfTheWeek?.map { .init(weekday: $0.dayOfTheWeek.rawValue, weekNumber: $0.weekNumber) },
            daysOfMonth: rule.daysOfTheMonth?.map(\.intValue),
            monthsOfYear: rule.monthsOfTheYear?.map(\.intValue),
            weeksOfYear: rule.weeksOfTheYear?.map(\.intValue),
            daysOfYear: rule.daysOfTheYear?.map(\.intValue),
            setPositions: rule.setPositions?.map(\.intValue),
            firstDayOfWeek: rule.firstDayOfTheWeek,
            end: end
        )
    }
}

/// The repeat rule of the series an occurrence belongs to, once per series
/// per fetch. A detached occurrence (or an Exchange exception sent as its
/// own item) has no rule of its own; the series answers to the external
/// identifier without the "/RID=…" suffix.
final class SeriesRuleLookup {
    private let eventStore: EKEventStore
    private var rulesBySeries: [String: [EKRecurrenceRule]?] = [:]

    init(eventStore: EKEventStore) {
        self.eventStore = eventStore
    }

    func rules(for event: EKEvent) -> [EKRecurrenceRule]? {
        guard !event.hasRecurrenceRules, Self.looksLikeOccurrence(event),
              let externalID = event.calendarItemExternalIdentifier, !externalID.isEmpty else { return nil }
        let seriesID = externalID.range(of: "/RID=").map { String(externalID[..<$0.lowerBound]) } ?? externalID
        if let cached = rulesBySeries[seriesID] { return cached }
        let rules = [seriesID, externalID].lazy
            .flatMap { self.eventStore.calendarItems(withExternalIdentifier: $0) }
            .compactMap { ($0 as? EKEvent)?.recurrenceRules }
            .first { !$0.isEmpty }
        rulesBySeries[seriesID] = rules
        return rules
    }

    static func looksLikeOccurrence(_ event: EKEvent) -> Bool {
        event.isDetached || (event.eventIdentifier?.contains("/RID=") ?? false)
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
