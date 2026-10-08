import Foundation

/// The selector trigger's summary ("All Calendars", "Work + Home", "3 Lists").
package enum SelectionSummary {
    package enum Kind: Equatable { case calendars, lists }

    package static let pairLimit = 22

    package static func label(visibleTitles: [String], total: Int, kind: Kind) -> String {
        if total == 0 || visibleTitles.isEmpty {
            return kind == .calendars ? L10n.tr("selection.calendars.none", "No Calendars") : L10n.tr("selection.lists.none", "No Lists")
        }
        if visibleTitles.count >= total {
            return kind == .calendars ? L10n.tr("selection.calendars.all", "All Calendars") : L10n.tr("selection.lists.all", "All Lists")
        }
        switch visibleTitles.count {
        case 1: return visibleTitles[0]
        case 2:
            let pair = "\(visibleTitles[0]) + \(visibleTitles[1])"
            return pair.count <= pairLimit ? pair : countLabel(visibleTitles.count, kind: kind)
        default: return countLabel(visibleTitles.count, kind: kind)
        }
    }

    private static func countLabel(_ count: Int, kind: Kind) -> String {
        if kind == .calendars { return L10n.tr("selection.calendars.count", "\(count) Calendars") }
        return L10n.tr("selection.lists.count", "\(count) Lists")
    }

}
