import Foundation

/// What a search query asks for, resolved: words to look for anywhere, the
/// operators' constraints and a date range. The session searches with it;
/// the index turns it into one request.
package struct SearchQueryParts: Equatable, Sendable {
    package enum Kind: Sendable { case event, task }

    /// Words matched anywhere (ranked by relevance).
    package var text: String
    /// `subject:` — words matched in the title only.
    package var subject: String?
    /// `from:` — the organizer.
    package var organizer: String?
    /// `with:` — someone taking part.
    package var attendee: String?
    /// `from:me` — the user's own events (organized by them, or theirs with
    /// no organizer); tasks are theirs too.
    package var organizedByMe = false
    /// `type:` — only events or only tasks; nil: both.
    package var kind: Kind?
    package var interval: DateInterval?
    /// The range came from an operator (`day:` …), not a phrase in the
    /// words — so it searches even with no words.
    package var hasExplicitDate = false
    /// What was understood, for the result count: "from Anna · Tue, 6 Oct".
    package var label: String?

    package static func plain(_ text: String) -> SearchQueryParts { SearchQueryParts(text: text) }

    /// Letters and digits a query needs before it searches.
    package static let minimumCharacters = 3

    package static func isSearchable(_ query: String) -> Bool {
        query.unicodeScalars.lazy.filter { CharacterSet.alphanumerics.contains($0) }.count >= minimumCharacters
    }

    package var includesEvents: Bool { kind != .task }
    /// Tasks have no organizer or attendees.
    package var includesTasks: Bool { kind != .event && organizer == nil && attendee == nil }

    /// Enough to search: three letters of free words, or any operator that
    /// narrows by text or date. A date phrase alone ("tomorrow") is Go to's.
    package var isSearchable: Bool {
        if Self.isSearchable(text) { return true }
        if [subject, organizer, attendee].contains(where: { ($0?.count ?? 0) >= 2 }) { return true }
        return hasExplicitDate || organizedByMe
    }

    /// The words that rank titles: the free ones, else the subject's.
    package var rankingText: String { text.isEmpty ? (subject ?? "") : text }

    package init(
        text: String,
        subject: String? = nil,
        organizer: String? = nil,
        attendee: String? = nil,
        organizedByMe: Bool = false,
        kind: Kind? = nil,
        interval: DateInterval? = nil,
        hasExplicitDate: Bool = false,
        label: String? = nil
    ) {
        self.text = text
        self.subject = subject
        self.organizer = organizer
        self.attendee = attendee
        self.organizedByMe = organizedByMe
        self.kind = kind
        self.interval = interval
        self.hasExplicitDate = hasExplicitDate
        self.label = label
    }
}
