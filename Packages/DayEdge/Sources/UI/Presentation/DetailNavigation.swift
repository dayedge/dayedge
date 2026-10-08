import Foundation

/// A details card's keyboard order: its editable rows top to bottom.
/// ↑ / ↓ move (no wrap); nothing selected yet starts at the first / last.
package struct DetailNavigation: Equatable {
    package var rows: [String]

    package func move(from current: String?, by step: Int) -> String? {
        guard !rows.isEmpty else { return nil }
        guard let current, let index = rows.firstIndex(of: current) else {
            return step >= 0 ? rows.first : rows.last
        }
        return rows[min(max(index + step, 0), rows.count - 1)]
    }
}
