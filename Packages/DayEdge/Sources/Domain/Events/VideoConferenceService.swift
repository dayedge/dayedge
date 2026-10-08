import Foundation

/// Which video conferencing service an event links to, detected from its
/// URL/notes/location. There's no official Zoom/Teams SF Symbol (and
/// copying their actual logos isn't something to do), so each renders as
/// a small colored letter badge instead — enough to tell them apart at a
/// glance without reproducing trademarked artwork.
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
    /// icon for (see `BrandIcon`). Nil falls back to the letter badge.
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
