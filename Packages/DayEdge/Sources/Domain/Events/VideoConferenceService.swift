import Foundation

/// Service detected from an event's meeting URL.
package enum VideoConferenceService: Hashable {
    case zoom
    case teams
    case googleMeet
    case other

    package var badgeLabel: String? {
        switch self {
        case .zoom: return "Z"
        case .teams: return "T"
        case .googleMeet: return "G"
        case .other: return nil
        }
    }

    /// Name of the bundled SVG in `Resources/` for services we have a real
    /// icon for (see `BrandIcon`). Call icons without a resource use a generic camera glyph.
    package var iconResourceName: String? {
        switch self {
        case .zoom: return "zoom-icon"
        case .teams: return "teams-icon"
        case .googleMeet, .other: return nil
        }
    }

    package var displayName: String {
        switch self {
        case .zoom: return "Zoom Meeting"
        case .teams: return "Microsoft Teams"
        case .googleMeet: return "Google Meet"
        case .other: return L10n.tr("videoconferenceservice.video.call", "Video Call")
        }
    }
}
