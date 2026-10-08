import Foundation

/// A timed task card's height on the Day timeline — its content's, never a
/// duration: padding, the one-line title, and the second line (list,
/// repeat) when there is one. Exact, so stacking and collisions with events
/// can be laid out before anything is drawn.
package enum TimedTaskCardMetrics {
    package static let verticalPadding: CGFloat = 8
    /// One line of `AppTheme.TextStyle.eventTitle` (13 pt semibold).
    package static let titleLineHeight: CGFloat = 16
    /// One line of `AppTheme.TextStyle.eventSubtitle` (12 pt).
    package static let secondLineHeight: CGFloat = 15
    /// Title → second line, as in the Tasks view's rows.
    package static let lineSpacing: CGFloat = 2

    package static func height(hasSecondLine: Bool) -> CGFloat {
        verticalPadding * 2 + titleLineHeight + (hasSecondLine ? lineSpacing + secondLineHeight : 0)
    }
}
