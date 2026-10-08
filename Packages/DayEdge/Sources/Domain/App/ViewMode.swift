import Foundation

/// The top-level "what am I looking at" switch — the app's four peer
/// views: the month calendar, a single day's agenda, tasks, and Ask
/// The app (the conversation).
package enum ViewMode: CaseIterable, Identifiable {
    case month
    case day
    case tasks
    case ask

    package var id: Self { self }

    package var symbolName: String {
        switch self {
        case .month: return "rectangle.grid.1x2"
        case .day: return "calendar.day.timeline.left"
        case .tasks: return "list.bullet"
        case .ask: return "sparkles"
        }
    }

    /// Small per-symbol compensation keeps dissimilar SF Symbols at the
    /// same perceived visual size inside identical slots.
    package var symbolSize: CGFloat {
        switch self {
        case .month: return 13
        case .day: return 14
        case .tasks: return 13.5
        case .ask: return 13
        }
    }

    package var accessibilityLabel: String {
        switch self {
        case .month: return L10n.tr("viewmode.month.view", "Month View")
        case .day: return L10n.tr("viewmode.agenda.view", "Agenda View")
        case .tasks: return L10n.tr("viewmode.tasks.view", "Tasks View")
        case .ask: return L10n.tr("viewmode.ask.dayedge", "Ask DayEdge")
        }
    }

    /// Short, tooltip-friendly name — "Agenda" reads better as a hover
    /// hint than the accessibility label's fuller "Agenda View".
    package var tooltipTitle: String {
        switch self {
        case .month: return L10n.tr("viewmode.month", "Month")
        case .day: return L10n.tr("viewmode.agenda", "Agenda")
        case .tasks: return L10n.tr("viewmode.tasks", "Tasks")
        case .ask: return L10n.tr("viewmode.ask.dayedge", "Ask DayEdge")
        }
    }
}
