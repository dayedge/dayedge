import SwiftUI

/// The popover's toolbar row, the same in every view: a per-view leading
/// slot (the search field in Month, Day and Tasks; chat controls in Ask)
/// and the view switcher on the right. Rendered once, at the panel root, so
/// the switcher is one view that never moves or re-creates when the view
/// changes.
package struct PanelToolbar<Leading: View, Switcher: View>: View {
    /// Row height — the search field's row.
    package static var height: CGFloat { 42 }
    /// Panel top (below the pointer) → row top.
    package static var topInset: CGFloat { 6 }
    /// Leading slot → switcher.
    package static var spacing: CGFloat { 10 }

    @ViewBuilder package var leading: () -> Leading
    @ViewBuilder package var switcher: () -> Switcher

    package init(@ViewBuilder leading: @escaping () -> Leading, @ViewBuilder switcher: @escaping () -> Switcher) {
        self.leading = leading
        self.switcher = switcher
    }

    package var body: some View {
        HStack(spacing: Self.spacing) {
            leading()
                .frame(maxWidth: .infinity, alignment: .leading)
            switcher()
        }
        .padding(.horizontal, AppTheme.horizontalPadding)
        .frame(height: Self.height)
    }
}

/// The geometry every view shares, independent of the generic row.
package enum PanelToolbarMetrics {
    package static let height = PanelToolbar<EmptyView, EmptyView>.height
    package static let topInset = PanelToolbar<EmptyView, EmptyView>.topInset
    /// Room the switcher takes at the row's trailing edge, spacing included —
    /// what a full-width leading layer (the search field) leaves free.
    package static var trailingReserve: CGFloat { trailingReserve(folded: false) }

    /// The same, for a folded switcher (Ask): it unfolds over the row.
    package static func trailingReserve(folded: Bool) -> CGFloat {
        ViewModeSwitcherView.width(folded: folded) + PanelToolbar<EmptyView, EmptyView>.spacing
    }

    /// How far right of the row's padding the switcher sits: its last
    /// circle mirrors the search magnifier and Ask's send arrow — as far
    /// from the right edge as they are from the left. The arrow is centred
    /// on the magnifier's box (15.5pt wide at the default 13pt font,
    /// measured), `horizontalPadding` in from the edge.
    package static var switcherShift: CGFloat {
        ViewModeSwitcherView.width(folded: true) / 2 - 15.5 / 2
    }

    /// The panel's right chrome edge: the switcher's, and the footer's
    /// Settings button under it.
    package static var trailingChromeInset: CGFloat { AppTheme.horizontalPadding - switcherShift }
}
