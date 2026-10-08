import EventKit
import Foundation
import Domain

/// Event rules, stateless and on plain values: the stored index snapshot →
/// `AgendaEventModel` mapping (`CalendarEventMapper+Snapshot.swift`) builds
/// models from them, and the EventKit writers use the `EKEvent` helpers
/// (alarms, invitation, series identity) when they edit live events.
package enum CalendarEventMapper {
    /// Time alerts (location alarms aren't the app's business).
    package static func alerts(from alarms: [EKAlarm]?) -> [EventAlert] {
        (alarms ?? []).filter { $0.structuredLocation == nil }.map {
            alert(absoluteDate: $0.absoluteDate, relativeOffset: $0.relativeOffset)
        }
    }

    package static func alert(absoluteDate: Date?, relativeOffset: TimeInterval) -> EventAlert {
        if let absoluteDate { return .at(absoluteDate) }
        return .before(minutes: Int((-relativeOffset / 60).rounded()))
    }

    package static func displayTitle(_ title: String?) -> String {
        (title?.isEmpty == false) ? title! : L10n.tr("calendareventmapper.no.title", "(no title)")
    }

    package static func alarm(for alert: EventAlert) -> EKAlarm {
        switch alert {
        case .before(let minutes): return EKAlarm(relativeOffset: -TimeInterval(minutes) * 60)
        case .at(let date): return EKAlarm(absoluteDate: date)
        }
    }

    // swiftlint:disable:next function_parameter_count - mirrors the EventKit fields it reads; labelled at the call
    package static func editReference(eventIdentifier: String?, calendarIdentifier: String, start: Date, end: Date,
                                      isWritable: Bool, organizerName: String?, isInvitation: Bool,
                                      hasAttendees: Bool) -> EventEditReference? {
        guard let eventIdentifier else { return nil }
        return EventEditReference(
            eventIdentifier: eventIdentifier,
            calendarIdentifier: calendarIdentifier,
            occurrenceStart: start,
            occurrenceEnd: end,
            isWritable: isWritable,
            invitationFrom: isInvitation ? organizerName : nil,
            isInvitation: isInvitation,
            hasAttendees: hasAttendees
        )
    }

    /// A series' identity: the external identifier without an occurrence's
    /// "/RID=…" suffix — a detached occurrence carries one, so it otherwise
    /// matched none of its series' other occurrences (Next/Previous
    /// Occurrence found nothing).
    package static func seriesIdentifier(_ externalIdentifier: String) -> String {
        externalIdentifier.components(separatedBy: "/RID=").first ?? externalIdentifier
    }

    /// Part of a series: it has a repeat rule, or it's an occurrence
    /// detached from one (edited on its own).
    package static func isRecurring(_ event: EKEvent) -> Bool {
        event.hasRecurrenceRules || event.isDetached
    }

    /// Has other attendees and the user doesn't organize it.
    package static func isInvitation(_ event: EKEvent) -> Bool {
        guard let attendees = event.attendees, !attendees.isEmpty else { return false }
        return event.organizer?.isCurrentUser != true
    }

    package static func eventID(for event: EKEvent) -> String {
        eventID(eventIdentifier: event.eventIdentifier, start: event.startDate)
    }

    package static func eventID(eventIdentifier: String?, start: Date) -> String {
        "\(eventIdentifier ?? UUID().uuidString)-\(start.timeIntervalSince1970)"
    }

    // swiftlint:disable:next function_parameter_count - mirrors the EventKit fields it reads; labelled at the call
    package static func recurrenceReference(isRecurring: Bool, externalIdentifier: String?, eventIdentifier: String?,
                                            calendarIdentifier: String, eventID: String, start: Date,
                                            occurrenceDate: Date?) -> RecurringSeriesReference? {
        guard isRecurring,
              let identifier = externalIdentifier,
              !identifier.isEmpty,
              eventIdentifier != nil else { return nil }
        return RecurringSeriesReference(
            seriesIdentifier: seriesIdentifier(identifier),
            calendarIdentifier: calendarIdentifier,
            sourceEventID: eventID,
            sourceStart: start,
            sourceOccurrenceDate: occurrenceDate
        )
    }

    // swiftlint:disable function_parameter_count - mirrors the EventKit fields it reads; labelled at the call
    /// `isCanceled` is the raw EventKit status (cancelled by the organizer),
    /// deliberately not `eventStatus`'s mapped `EventStatus.cancelled` — that
    /// UI case also covers an event the user merely *declined*, which is
    /// still live for every other attendee and must never be offered for
    /// removal.
    package static func removalReference(isCanceled: Bool, isWritable: Bool, eventIdentifier: String?,
                                         calendarIdentifier: String, start: Date, end: Date) -> EventRemovalReference? {
        guard isCanceled, isWritable, let eventIdentifier else { return nil }
        return EventRemovalReference(
            eventIdentifier: eventIdentifier,
            calendarIdentifier: calendarIdentifier,
            occurrenceStart: start,
            occurrenceEnd: end
        )
    }
    // swiftlint:enable function_parameter_count

    /// Detects the video-conferencing service *and* its join URL together
    /// — previously two independent passes (`videoService(for:)`/
    /// `meetingURL(for:)`) that could disagree: the URL `NSDataDetector`
    /// happened to find first wasn't necessarily the one belonging to the
    /// service the keyword scan detected. Narrows matching to URL
    /// *hosts* specifically rather than a loose substring search over the
    /// whole haystack — a deliberate tightening: the old
    /// `haystack.contains("zoom.us")` would also match those literal
    /// characters appearing in plain prose with no real link behind them.
    package static func meetingLink(url eventURL: URL?, location: String?, notes: String?) -> (service: VideoConferenceService?, url: String?) {
        // Exact hosts and web schemes only (`MeetingHost`): invitations are
        // other people's text.
        let eventURL = eventURL.flatMap { MeetingHost.isWebLink($0) ? $0 : nil }
        if let eventURL, let service = MeetingHost.service(for: eventURL) {
            return (service, eventURL.absoluteString)
        }
        let haystack = [location, notes].compactMap { $0 }.joined(separator: " ")
        let candidates = detectedURLs(in: haystack).filter(MeetingHost.isWebLink)
        for url in candidates {
            if let service = MeetingHost.service(for: url) { return (service, url.absoluteString) }
        }
        if let eventURL { return (.other, eventURL.absoluteString) }
        return (nil, candidates.first?.absoluteString)
    }

    /// `NSDataDetector` is the robust, idiomatic way to find a URL
    /// sitting in free text, rather than a hand-rolled regex.
    private static func detectedURLs(in text: String) -> [URL] {
        guard !text.isEmpty,
              let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return detector.matches(in: text, options: [], range: range).compactMap(\.url)
    }

    package static func attendee(name: String?, status: EventAttendee.Status, email: String?, isCurrentUser: Bool) -> EventAttendee {
        EventAttendee(name: name ?? L10n.tr("calendareventmapper.unknown", "Unknown"), status: status, email: email, isCurrentUser: isCurrentUser)
    }

    /// `myStatus` nil: the user isn't an attendee.
    package static func eventStatus(isCanceled: Bool, myStatus: EventAttendee.Status?) -> EventStatus {
        if isCanceled { return .cancelled }
        guard let myStatus else { return .confirmed }
        switch myStatus {
        case .accepted: return .confirmed
        case .declined: return .cancelled
        default: return .tentative
        }
    }

    package static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
}
