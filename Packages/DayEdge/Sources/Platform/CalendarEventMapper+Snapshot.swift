import CalendarIndex
import EventKit
import Foundation
import Domain

/// A stored index snapshot → `AgendaEventModel`. (Proven field-for-field
/// identical to the former live-`EKEvent` mapping on real calendars before
/// that path was removed.)
extension CalendarEventMapper {
    // swiftlint:disable:next function_body_length - one field per line of the event model
    package static func agendaEventModel(from snapshot: OccurrenceSnapshot, calendar: CalendarSnapshot) -> AgendaEventModel {
        let s = snapshot
        let meeting = meetingLink(url: s.url.flatMap(URL.init(string:)), location: s.location, notes: s.notes)
        let eventID = eventID(eventIdentifier: s.eventIdentifier, start: s.start)
        let myStatus = s.participation.map(attendeeStatus)
        // The series' rule counts for `isRecurring` only when the event has
        // none of its own — as `seriesRecurrenceRules` does on the live path.
        let seriesRuleFound = s.recurrence != nil && !s.hasOwnRecurrenceRules
        let rules = s.recurrence.map { [ekRule($0)] }
        return AgendaEventModel(
            id: eventID,
            startTime: s.isAllDay ? nil : timeFormatter.string(from: s.start),
            endTime: s.isAllDay ? nil : timeFormatter.string(from: s.end),
            startDate: s.start,
            endDate: s.end,
            title: displayTitle(s.title),
            subtitle: s.location,
            status: eventStatus(isCanceled: s.status == .canceled, myStatus: myStatus),
            videoService: meeting.service,
            isRecurring: s.hasOwnRecurrenceRules || s.isDetached || seriesRuleFound,
            tint: tint(calendar.color),
            calendarName: calendar.title,
            notes: s.notes,
            videoURL: meeting.url,
            attendees: EventAttendee.uniquingIDs(s.attendees.map {
                attendee(name: $0.name, status: attendeeStatus($0.status), email: $0.email, isCurrentUser: $0.isCurrentUser)
            }),
            myResponseStatus: myStatus,
            removalReference: removalReference(isCanceled: s.status == .canceled, isWritable: calendar.allowsModifications,
                                               eventIdentifier: s.eventIdentifier, calendarIdentifier: s.calendarIdentifier,
                                               start: s.start, end: s.end),
            calendarItemIdentifier: s.calendarItemIdentifier,
            occurrenceDate: s.occurrenceDate,
            reminderOccurrenceKey: ReminderOccurrenceKey.eventKit(
                calendarIdentifier: s.calendarIdentifier,
                isRecurring: s.hasOwnRecurrenceRules || s.isDetached || s.occurrenceDate != nil,
                seriesIdentifier: s.externalIdentifier,
                calendarItemIdentifier: s.calendarItemIdentifier,
                eventIdentifier: s.eventIdentifier,
                startDate: s.start,
                occurrenceDate: s.occurrenceDate
            ),
            recurrenceReference: recurrenceReference(
                isRecurring: s.hasOwnRecurrenceRules || s.isDetached, externalIdentifier: s.externalIdentifier,
                eventIdentifier: s.eventIdentifier, calendarIdentifier: s.calendarIdentifier, eventID: eventID,
                start: s.start, occurrenceDate: s.occurrenceDate),
            organizerName: s.organizer?.name,
            createdAt: s.created,
            modifiedAt: s.modified,
            editReference: editReference(eventIdentifier: s.eventIdentifier, calendarIdentifier: s.calendarIdentifier,
                                         start: s.start, end: s.end, isWritable: calendar.allowsModifications,
                                         organizerName: s.organizer?.name, isInvitation: s.isInvitation,
                                         hasAttendees: s.hasAttendees),
            recurrence: ReminderMapper.recurrence(from: rules, due: s.start, calendar: .autoupdatingCurrent),
            recurrenceRule: rules?.first.map(ReminderMapper.rule(from:)),
            alerts: s.alarms.filter { !$0.isLocationBased }.map {
                alert(absoluteDate: $0.absoluteDate, relativeOffset: $0.relativeOffset ?? 0)
            }
        )
    }

    package static func tint(_ rgba: CalendarSnapshot.RGBA) -> RGBAColor {
        RGBAColor(red: rgba.red, green: rgba.green, blue: rgba.blue, alpha: rgba.alpha)
    }

    /// Same buckets as the live `EKParticipantStatus` mapping.
    package static func attendeeStatus(_ status: ParticipationStatus) -> EventAttendee.Status {
        switch status {
        case .accepted: return .accepted
        case .declined: return .declined
        case .tentative: return .tentative
        case .pending: return .pending
        case .unknown, .delegated, .completed, .inProcess: return .unknown
        }
    }

    /// The stored rule rebuilt as a plain `EKRecurrenceRule` (no store
    /// needed), so `ReminderMapper`'s classification and summary text are
    /// the very same code for both paths.
    package static func ekRule(_ rule: RecurrenceDescription) -> EKRecurrenceRule {
        let frequency: EKRecurrenceFrequency
        switch rule.frequency {
        case .daily: frequency = .daily
        case .weekly: frequency = .weekly
        case .monthly: frequency = .monthly
        case .yearly: frequency = .yearly
        }
        let days = rule.daysOfWeek?.compactMap { day -> EKRecurrenceDayOfWeek? in
            guard let weekday = EKWeekday(rawValue: day.weekday) else { return nil }
            return day.weekNumber == 0 ? EKRecurrenceDayOfWeek(weekday) : EKRecurrenceDayOfWeek(weekday, weekNumber: day.weekNumber)
        }
        let end: EKRecurrenceEnd?
        switch rule.end {
        case .count(let count): end = EKRecurrenceEnd(occurrenceCount: count)
        case .date(let date): end = EKRecurrenceEnd(end: date)
        case nil: end = nil
        }
        func numbers(_ values: [Int]?) -> [NSNumber]? { values.map { $0.map(NSNumber.init(value:)) } }
        return EKRecurrenceRule(
            recurrenceWith: frequency, interval: rule.interval, daysOfTheWeek: days,
            daysOfTheMonth: numbers(rule.daysOfMonth), monthsOfTheYear: numbers(rule.monthsOfYear),
            weeksOfTheYear: numbers(rule.weeksOfYear), daysOfTheYear: numbers(rule.daysOfYear),
            setPositions: numbers(rule.setPositions), end: end
        )
    }
}
