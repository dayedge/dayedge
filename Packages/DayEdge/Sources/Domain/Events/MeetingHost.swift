import Foundation

/// What counts as a meeting link. Event URLs, locations and notes come from
/// other people's invitations, so a link is classified only by its parsed
/// scheme and an exact host (or a subdomain of it) — never a substring,
/// which would make `teams.microsoft.com.example.org` "Teams".
package enum MeetingHost {
    private static let domains: [(domain: String, service: VideoConferenceService)] = [
        ("zoom.us", .zoom), ("zoomgov.com", .zoom),
        ("teams.microsoft.com", .teams), ("teams.live.com", .teams),
        ("meet.google.com", .googleMeet)
    ]

    /// Only web links can be joined or opened: no `file:`, `javascript:` or
    /// another app's scheme from an invitation.
    package static func isWebLink(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http" else { return false }
        return !(url.host ?? "").isEmpty
    }

    /// The service a web link belongs to; nil for anything else.
    package static func service(for url: URL) -> VideoConferenceService? {
        guard isWebLink(url), var host = url.host?.lowercased() else { return nil }
        if host.hasSuffix(".") { host.removeLast() }
        return domains.first { host == $0.domain || host.hasSuffix("." + $0.domain) }?.service
    }
}
