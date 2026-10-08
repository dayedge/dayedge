import SwiftUI

/// Every view's large title: the title (in the large title font), an
/// optional trailing control (month/day chevrons), and a quiet subtitle
/// below — one layout for Month, Day, Tasks and Ask, spaced by the shared
/// `PeriodHeader` tokens.
package struct LargeTitleHeader<Title: View, Subtitle: View, Trailing: View>: View {
    @Environment(\.themePalette) private var theme

    package static var topPadding: CGFloat { 12 }

    /// How the trailing control sits against the title: centered on it
    /// (Month and Day's chevrons), or on its baseline.
    package var trailingAlignment: VerticalAlignment = .firstTextBaseline
    @ViewBuilder package var title: () -> Title
    @ViewBuilder package var subtitle: () -> Subtitle
    @ViewBuilder package var trailing: () -> Trailing

    package init(trailingAlignment: VerticalAlignment = .firstTextBaseline, @ViewBuilder title: @escaping () -> Title,
                 @ViewBuilder subtitle: @escaping () -> Subtitle, @ViewBuilder trailing: @escaping () -> Trailing) {
        self.trailingAlignment = trailingAlignment
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing
    }

    package var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.PeriodHeader.titleToSubtitle) {
            HStack(alignment: trailingAlignment) {
                title()
                    .font(AppTheme.TextStyle.monthTitle)
                    .foregroundStyle(theme.primaryText)
                    .lineLimit(1)
                Spacer(minLength: 0)
                trailing()
            }
            subtitle()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, AppTheme.horizontalPadding)
        .padding(.top, Self.topPadding)
    }
}

extension LargeTitleHeader where Trailing == EmptyView {
    package init(@ViewBuilder title: @escaping () -> Title, @ViewBuilder subtitle: @escaping () -> Subtitle) {
        self.init(title: title, subtitle: subtitle, trailing: { EmptyView() })
    }
}

/// The chevrons Month and Day put beside their title.
package struct PeriodStepper: View {
    @Environment(\.themePalette) private var theme

    package let onPrevious: () -> Void
    package let onNext: () -> Void

    package var body: some View {
        HStack(spacing: theme.navigationButtonSpacing) {
            Button(action: onPrevious) {
                Image(systemName: "chevron.left")
                    .frame(width: theme.navigationButtonSize?.width, height: theme.navigationButtonSize?.height)
                    .contentShape(Rectangle())
            }
            Button(action: onNext) {
                Image(systemName: "chevron.right")
                    .frame(width: theme.navigationButtonSize?.width, height: theme.navigationButtonSize?.height)
                    .contentShape(Rectangle())
            }
        }
        .themedSurface(.floatingControl, fill: .clear, in: Capsule())
        .surfaceElevation(.floatingControl)
        .buttonStyle(.plain)
        .foregroundStyle(theme.secondaryText)
        .font(.system(size: 15, weight: .semibold))
    }

    package init(onPrevious: @escaping () -> Void, onNext: @escaping () -> Void) {
        self.onPrevious = onPrevious
        self.onNext = onNext
    }
}
