import SwiftUI
import Domain

package enum SelectionIndicator: Equatable {
    case color(Color)
    case smart(TaskSmartSection)
}

package enum SelectionKind {
    case calendar, reminderList, smart

    package var accessibilityName: String {
        switch self {
        case .calendar: return "calendar"
        case .reminderList: return L10n.tr("selectiongroups.reminders.list", "reminders list")
        case .smart: return L10n.tr("selectiongroups.smart.section", "smart section")
        }
    }
}

package struct SelectionItem: Identifiable, Equatable {
    package let id: String
    package let title: String
    package let indicator: SelectionIndicator
    package let kind: SelectionKind
    package let isSelected: Bool

    /// "Work, calendar, selected" — meaning in words, never color values.
    package var accessibilityLabel: String {
        "\(title), \(kind.accessibilityName), \(isSelected ? "selected" : "not selected")"
    }

    package static func == (lhs: SelectionItem, rhs: SelectionItem) -> Bool {
        lhs.id == rhs.id && lhs.title == rhs.title && lhs.indicator == rhs.indicator
            && lhs.isSelected == rhs.isSelected
    }
}

package struct SelectionGroup: Identifiable, Equatable {
    package let id: String
    package let title: String
    package let items: [SelectionItem]
}

/// Pure builders for the selector's view-ready groups.
package enum SelectionGroups {
    /// Sources grouped by account (`sourceID`), groups and items in
    /// alphabetical order. Duplicate titles stay apart because their
    /// accounts differ.
    package static func bySource(
        _ sources: [CalendarSource], kind: SelectionKind, isSelected: (String) -> Bool
    ) -> [SelectionGroup] {
        let grouped = Dictionary(grouping: sources) { $0.sourceID.isEmpty ? $0.sourceTitle : $0.sourceID }
        return grouped
            .map { key, items -> SelectionGroup in
                let title = items.first?.sourceTitle ?? ""
                return SelectionGroup(
                    id: key,
                    title: title.isEmpty ? SourceDisplayName.fallback(for: .other) : title,
                    items: items
                        .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
                        .map { SelectionItem(id: $0.id, title: $0.title, indicator: .color($0.color), kind: kind, isSelected: isSelected($0.id)) }
                )
            }
            .sorted {
                let order = $0.title.localizedStandardCompare($1.title)
                return order != .orderedSame ? order == .orderedAscending : $0.id < $1.id
            }
    }

    /// The Tasks-only group of the app smart sections.
    package static func smart(isSelected: (TaskSmartSection) -> Bool) -> SelectionGroup {
        SelectionGroup(
            id: "smart", title: L10n.tr("selectiongroups.smart", "Smart"),
            items: TaskSmartSection.allCases.map {
                SelectionItem(id: $0.visibilityID, title: $0.title, indicator: .smart($0), kind: .smart, isSelected: isSelected($0))
            }
        )
    }
}
