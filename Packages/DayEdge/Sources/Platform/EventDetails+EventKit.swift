import CoreLocation
import Domain
import EventKit

extension EventDetails {
    package init(_ event: EKEvent) {
        self.init(url: event.url, timeZone: event.timeZone, availability: event.availability.rawValue,
                  place: event.structuredLocation.map(EventPlace.init), alarms: (event.alarms ?? []).map(EventAlarm.init))
    }

    /// Writes all of it onto `event`, replacing its alarms. Availability
    /// only where the event's calendar supports it.
    package func apply(to event: EKEvent) {
        event.url = url
        event.timeZone = timeZone
        if let place { event.structuredLocation = place.structuredLocation }
        if let availability = EKEventAvailability(rawValue: availability), Self.supports(availability, in: event.calendar?.supportedEventAvailabilities) {
            event.availability = availability
        }
        for alarm in event.alarms ?? [] { event.removeAlarm(alarm) }
        for alarm in alarms { event.addAlarm(alarm.ekAlarm) }
    }

    /// `supported` is the calendar's; nil when the event isn't in one yet.
    package static func supports(_ availability: EKEventAvailability, in supported: EKCalendarEventAvailabilityMask?) -> Bool {
        guard availability != .notSupported else { return false }
        guard let supported else { return true }
        switch availability {
        case .busy: return supported.contains(.busy)
        case .free: return supported.contains(.free)
        case .tentative: return supported.contains(.tentative)
        case .unavailable: return supported.contains(.unavailable)
        default: return false
        }
    }
}

extension EventPlace {
    package init(_ location: EKStructuredLocation) {
        self.init(title: location.title, latitude: location.geoLocation?.coordinate.latitude,
                  longitude: location.geoLocation?.coordinate.longitude, radius: location.radius)
    }

    package var structuredLocation: EKStructuredLocation {
        let location = EKStructuredLocation(title: title ?? "")
        if let latitude, let longitude { location.geoLocation = CLLocation(latitude: latitude, longitude: longitude) }
        location.radius = radius
        return location
    }
}

extension EventAlarm {
    package init(_ alarm: EKAlarm) {
        self.init(relativeOffset: alarm.relativeOffset, absoluteDate: alarm.absoluteDate, proximity: alarm.proximity.rawValue,
                  place: alarm.structuredLocation.map(EventPlace.init), soundName: alarm.soundName,
                  emailAddress: alarm.emailAddress)
    }

    package var ekAlarm: EKAlarm {
        let alarm = absoluteDate.map { EKAlarm(absoluteDate: $0) } ?? EKAlarm(relativeOffset: relativeOffset)
        if let place {
            alarm.structuredLocation = place.structuredLocation
            alarm.proximity = EKAlarmProximity(rawValue: proximity) ?? .none
        }
        // Setting one clears the other (EventKit): an alarm is one kind.
        if let soundName { alarm.soundName = soundName }
        if let emailAddress { alarm.emailAddress = emailAddress }
        return alarm
    }
}
