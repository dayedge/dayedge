import Foundation
import Observation

extension Notification.Name {
    /// Posted (object: the store) whenever which sources the app uses or
    /// shows changes, so every consumer can reload.
    package static let sourceVisibilityDidChange = Notification.Name("DayEdgeSourceVisibilityDidChange")
}

/// Which sources (calendars, or Reminders lists) are in play — two levels,
/// both persisted, both stored as "off" sets so new sources start on:
/// - **Excluded** (Settings): ignored everywhere.
/// - **Hidden** (the footer selector): a day-to-day quick filter among the
///   sources that aren't excluded.
/// One store type serves both; each instance has its own keys.
@Observable
package final class SourceVisibilityStore {
    package struct Kind: Equatable {
        package let excludedKey: String
        package let hiddenKey: String
        /// Stable source kind for complete, localized selector summaries.
        package let selectionKind: SelectionSummary.Kind

        package static let calendars = Kind(
            excludedKey: "com.dayedge.calendars.excluded",
            hiddenKey: "com.dayedge.calendars.hidden",
            selectionKind: .calendars
        )
        package static let taskLists = Kind(
            excludedKey: "com.dayedge.tasks.lists.excluded",
            hiddenKey: "com.dayedge.tasks.lists.hidden",
            selectionKind: .lists
        )
    }

    package let kind: Kind
    /// Everything the source system offers, for Settings.
    package private(set) var allItems: [CalendarSource] = []
    package private(set) var excludedIDs: Set<String>
    /// Unknown ids are kept, not pruned: a temporarily missing account keeps
    /// its choices. Task smart sections also live here under reserved ids.
    package private(set) var hiddenIDs: Set<String>

    @ObservationIgnored private let defaults: UserDefaults

    package init(kind: Kind, defaults: UserDefaults = .standard) {
        self.kind = kind
        self.defaults = defaults
        excludedIDs = Set(defaults.stringArray(forKey: kind.excludedKey) ?? [])
        hiddenIDs = Set(defaults.stringArray(forKey: kind.hiddenKey) ?? [])
    }

    // MARK: - Catalogue

    package func update(_ items: [CalendarSource]) {
        allItems = items.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    /// Items the app uses at all (not excluded in Settings).
    package var availableItems: [CalendarSource] {
        allItems.filter { !excludedIDs.contains($0.id) }
    }

    // MARK: - Settings level

    package func isEnabled(_ id: String) -> Bool { !excludedIDs.contains(id) }

    package func setEnabled(_ enabled: Bool, id: String) {
        if enabled { excludedIDs.remove(id) } else { excludedIDs.insert(id) }
        persist()
    }

    // MARK: - Selector level

    package func isVisible(_ id: String) -> Bool { !excludedIDs.contains(id) && !hiddenIDs.contains(id) }

    package func toggle(_ id: String) {
        if hiddenIDs.contains(id) { hiddenIDs.remove(id) } else { hiddenIDs.insert(id) }
        persist()
    }

    /// Show only `id` among `ids`; anything outside `ids` (e.g. smart
    /// sections next to lists) is left as it is.
    package func solo(_ id: String, among ids: [String]) {
        hiddenIDs.subtract([id])
        hiddenIDs.formUnion(ids.filter { $0 != id })
        persist()
    }

    package func showAll() {
        hiddenIDs = []
        persist()
    }

    /// True when nothing the selector offers is hidden.
    package var isEverythingVisible: Bool {
        hiddenIDs.isDisjoint(with: availableItems.map(\.id) + TaskSmartSection.allCases.map(\.visibilityID))
    }

    package var visibleItems: [CalendarSource] { availableItems.filter { !hiddenIDs.contains($0.id) } }

    package var summaryLabel: String {
        SelectionSummary.label(visibleTitles: visibleItems.map(\.title), total: availableItems.count, kind: kind.selectionKind)
    }

    private func persist() {
        defaults.set(excludedIDs.sorted(), forKey: kind.excludedKey)
        defaults.set(hiddenIDs.sorted(), forKey: kind.hiddenKey)
        NotificationCenter.default.post(name: .sourceVisibilityDidChange, object: self)
    }
}
