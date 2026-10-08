import Foundation

/// A selectable source: a calendar (from EventKit's `EKCalendar`, or a
/// stand-in for the mock provider) or a Reminders list. Kept separate from
/// EventKit types so views never import EventKit, and shared by calendars
/// and task lists so one selector serves both.
package struct CalendarSource: Identifiable, Hashable {
    package let id: String
    package let title: String
    /// Its color (`color` in views).
    package let tint: RGBAColor
    /// The account's display name ("iCloud", "On My Mac") — always
    /// human-readable, see `SourceDisplayName`.
    package var sourceTitle: String = ""
    /// Stable account identity for grouping; two accounts can share a title.
    package var sourceID: String = ""
    package var sourceKind: SourceKind = .other
    /// False for read-only calendars/lists (subscribed, shared without edit
    /// rights); the UI disables editing for things that live there.
    package var allowsModifications: Bool = true

    package init(
        id: String,
        title: String,
        tint: RGBAColor,
        sourceTitle: String = "",
        sourceID: String = "",
        sourceKind: SourceKind = .other,
        allowsModifications: Bool = true
    ) {
        self.id = id
        self.title = title
        self.tint = tint
        self.sourceTitle = sourceTitle
        self.sourceID = sourceID
        self.sourceKind = sourceKind
        self.allowsModifications = allowsModifications
    }
}
