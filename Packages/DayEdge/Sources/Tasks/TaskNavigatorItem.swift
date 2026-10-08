import SwiftUI
import UI

/// One chip in the Tasks navigator, derived from a section so the chip and
/// the section header always show the same count (`TaskSection.totalCount`).
package struct TaskNavigatorItem: Identifiable, Equatable {
    package let id: String
    package let title: String
    package let count: Int
    package let color: Color?
    package let isAttention: Bool
    /// A neutral smart section (Completed) wears a symbol, not a dot.
    package let symbol: String?

    package init(section: TaskSection) {
        id = section.id
        title = section.navigatorTitle
        count = section.totalCount
        color = section.color
        isAttention = section.kind == .needsAttention
        symbol = section.kind == .completed ? "checkmark" : nil
    }

    /// Read as words, not as "Work dot 327".
    package var accessibilityLabel: String {
        "\(title), \(count) \(count == 1 ? "task" : "tasks")"
    }

    /// Landmarks only; sections are already omitted when they hold nothing.
    package static func items(from sections: [TaskSection]) -> [TaskNavigatorItem] {
        sections.filter { $0.isNavigable && $0.totalCount > 0 }.map(TaskNavigatorItem.init(section:))
    }
}
