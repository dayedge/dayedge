import Foundation

/// What an event carries beyond the fields DayEdge edits — kept so a
/// recreated event (Undo of a delete, a detached occurrence's new series)
/// is the same event: its link, time zone (nil = floating), Free/Busy, map
/// location and every alarm as it was (location-based, sound and email
/// alarms included, which `EventAlert` can't express). EventKit conversions:
/// `EventDetails+EventKit`.
package struct EventDetails: Equatable, Sendable {
    /// `EKEventAvailability.notSupported`.
    package static let availabilityNotSupported = -1

    package var url: URL?
    package var timeZone: TimeZone?
    /// `EKEventAvailability.rawValue`.
    package var availability: Int
    package var place: EventPlace?
    package var alarms: [EventAlarm]

    package init(url: URL? = nil, timeZone: TimeZone? = nil, availability: Int = Self.availabilityNotSupported,
                 place: EventPlace? = nil, alarms: [EventAlarm] = []) {
        self.url = url
        self.timeZone = timeZone
        self.availability = availability
        self.place = place
        self.alarms = alarms
    }
}

/// A map location (`EKStructuredLocation`).
package struct EventPlace: Hashable, Sendable {
    package var title: String?
    package var latitude: Double?
    package var longitude: Double?
    /// Metres; 0 = the default.
    package var radius: Double

    package init(title: String?, latitude: Double? = nil, longitude: Double? = nil, radius: Double = 0) {
        self.title = title
        self.latitude = latitude
        self.longitude = longitude
        self.radius = radius
    }
}

/// One alarm, verbatim: when (relative or absolute), where (arriving or
/// leaving a place) and how (a sound or an email; otherwise a display).
package struct EventAlarm: Hashable, Sendable {
    /// `EKAlarmProximity.none`.
    package static let proximityNone = 0

    package var relativeOffset: TimeInterval = 0
    package var absoluteDate: Date?
    /// `EKAlarmProximity.rawValue`.
    package var proximity = Self.proximityNone
    package var place: EventPlace?
    package var soundName: String?
    package var emailAddress: String?

    package init(relativeOffset: TimeInterval = 0, absoluteDate: Date? = nil, proximity: Int = Self.proximityNone,
                 place: EventPlace? = nil, soundName: String? = nil, emailAddress: String? = nil) {
        self.relativeOffset = relativeOffset
        self.absoluteDate = absoluteDate
        self.proximity = proximity
        self.place = place
        self.soundName = soundName
        self.emailAddress = emailAddress
    }
}
