import Foundation
import AppKit
import Domain

/// Everything needed to identify and join a video call from an event,
/// resolved once from the raw model data. Views read `event.meetingLink`
/// rather than each independently parsing `videoURL` and deciding for
/// themselves whether it's actually joinable, or which URL to open — this
/// is the one place that logic lives, so every place that shows a "Join"
/// affordance (the event popover today, others later) agrees on what
/// counts as joinable and prefers the native app the same way.
package struct MeetingLink {
    package let service: VideoConferenceService
    package let webURL: URL?
    package let appURL: URL?

    package var canJoin: Bool { webURL != nil }

    /// The native app's custom-scheme URL when that app is actually
    /// installed (so Zoom/Teams opens directly), falling back to the plain
    /// web link otherwise.
    package var preferredURL: URL? {
        if let appURL, AppAvailability.canOpen(appURL) {
            return appURL
        }
        return webURL
    }

    package static func resolve(service: VideoConferenceService?, videoURLString: String?) -> MeetingLink? {
        guard let service else { return nil }
        // Only a web link is joinable — whatever stored it (`MeetingHost`).
        let webURL = videoURLString.flatMap(URL.init(string:)).flatMap { MeetingHost.isWebLink($0) ? $0 : nil }
        let appURL = webURL.flatMap { MeetingAppLinkConverter.appURL(for: service, webURL: $0) }
        return MeetingLink(service: service, webURL: webURL, appURL: appURL)
    }
}

extension AgendaEventModel {
    package var meetingLink: MeetingLink? {
        MeetingLink.resolve(service: videoService, videoURLString: videoURL)
    }
}

/// Whether an app handles a URL scheme — asked of Launch Services once per
/// scheme a minute, not on every draw of every Join pill (measured).
private enum AppAvailability {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var answers: [String: (canOpen: Bool, at: Date)] = [:]
    private static let lifetime: TimeInterval = 60

    static func canOpen(_ url: URL) -> Bool {
        let scheme = url.scheme ?? ""
        let now = Date()
        if let cached = lock.withLock({ answers[scheme] }), now.timeIntervalSince(cached.at) < lifetime {
            return cached.canOpen
        }
        let canOpen = NSWorkspace.shared.urlForApplication(toOpen: url) != nil
        lock.withLock { answers[scheme] = (canOpen, now) }
        return canOpen
    }
}
