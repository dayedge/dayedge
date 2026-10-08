import Foundation

/// Tasks' the app-owned smart sections. Not Reminders lists: they have no
/// list color, and their visibility is the app's setting.
package enum TaskSmartSection: String, CaseIterable, Sendable {
    case attention
    case completed

    /// Reserved id in the task-list visibility store's hidden set.
    package var visibilityID: String { "smart.\(rawValue)" }

    package var title: String {
        switch self {
        case .attention: return L10n.tr("tasksmartsection.attention", "Attention")
        case .completed: return L10n.tr("tasksmartsection.completed", "Completed")
        }
    }
}
