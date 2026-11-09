import Foundation

/// Tasks' Overview rows and their ⌥⌘1–4: Needs Attention (a jump to its
/// section) and the filters (Today, Next 7 Days, All Tasks). None moves or
/// changes a task.
package enum TaskSmartView: String, CaseIterable, Sendable {
    case attention
    case today
    case nextWeek
    case all

    package var title: String {
        switch self {
        case .attention: return L10n.tr("tasksmartview.attention", "Needs Attention")
        case .today: return L10n.tr("tasksmartview.today", "Today")
        case .nextWeek: return L10n.tr("tasksmartview.next.week", "Next 7 Days")
        case .all: return L10n.tr("tasksmartview.all", "All Tasks")
        }
    }

    /// Monochrome: only real lists wear a colour.
    package var symbolName: String {
        switch self {
        case .attention: return "exclamationmark.circle"
        case .today: return "sun.max"
        case .nextWeek: return "calendar"
        case .all: return "tray"
        }
    }
}
