import Foundation

/// Decides whether an event's free-text location is worth offering an
/// "Open Location in Maps" action for. Deliberately no geocoding, no
/// network call — a context menu has to build instantly — and
/// deliberately just a blocklist rather than a "looks like a postal
/// address" positive check: a venue name ("Blue Bottle Coffee") or a
/// building name is a perfectly good Maps search query without
/// containing a digit or a comma, and requiring that shape would hide
/// the option for exactly the free-text venue names people actually
/// type. Maps search itself is the fallback for "does this resolve to
/// anything" — this heuristic's only job is to filter out the
/// obviously-not-a-place strings (generic virtual-meeting wording, raw
/// meeting URLs).
package enum LocationMapsHeuristic {
    private static let genericTerms: Set<String> = [
        "office", "remote", "virtual", "online", "tbd", "n/a", "home",
        "teams meeting", "zoom meeting", "google meet", "webex",
        "conference room", "meeting room", "call", "phone", "video call"
    ]

    package static func isLikelyMappableLocation(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let lowered = trimmed.lowercased()
        guard !genericTerms.contains(lowered) else { return false }
        return !lowered.hasPrefix("http")
            && !lowered.contains("zoom.us") && !lowered.contains("teams.microsoft")
            && !lowered.contains("meet.google")
    }
}
