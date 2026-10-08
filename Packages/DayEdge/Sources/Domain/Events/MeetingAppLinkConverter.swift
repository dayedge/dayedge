import Foundation

/// Converts a web meeting URL into the custom URL scheme its native app
/// registers, so joining can open Zoom.app/Teams.app directly instead of
/// always going through the browser. Kept separate from `MeetingLink`
/// itself: this is "how do you turn a web link into an app deep link" —
/// a distinct piece of knowledge from "does this event have a joinable
/// link at all."
package enum MeetingAppLinkConverter {
    package static func appURL(for service: VideoConferenceService, webURL: URL) -> URL? {
        // Converted only when the link really is that service's (the
        // Teams scheme keeps the web link's host).
        guard MeetingHost.service(for: webURL) == service else { return nil }
        switch service {
        case .zoom: return zoomAppURL(from: webURL)
        case .teams: return teamsAppURL(from: webURL)
        case .googleMeet, .other: return nil // no native macOS app deep link
        }
    }

    /// https://zoom.us/j/1234567890?pwd=abc → zoommtg://zoom.us/join?confno=1234567890&pwd=abc
    private static func zoomAppURL(from url: URL) -> URL? {
        let pathParts = url.pathComponents
        guard let jIndex = pathParts.firstIndex(of: "j"), pathParts.indices.contains(jIndex + 1) else { return nil }
        let confno = pathParts[jIndex + 1]

        var components = URLComponents()
        components.scheme = "zoommtg"
        components.host = "zoom.us"
        components.path = "/join"

        var queryItems = [URLQueryItem(name: "confno", value: confno)]
        if let pwd = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "pwd" })?.value {
            queryItems.append(URLQueryItem(name: "pwd", value: pwd))
        }
        components.queryItems = queryItems
        return components.url
    }

    /// Teams accepts the identical host/path/query as its web link — just
    /// with `msteams:` in place of `https:`.
    private static func teamsAppURL(from url: URL) -> URL? {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        components.scheme = "msteams"
        return components.url
    }
}
