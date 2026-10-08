import SwiftUI

/// The landing page hero, compact: the month view in front, the daily
/// agenda and Tasks behind it, slightly turned. Screenshots only — no card.
struct OnboardingProductStage: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height
            ZStack(alignment: .topLeading) {
                shot("agenda-466", width: width * 0.43)
                    .rotationEffect(.degrees(-1.5))
                    .offset(x: width * -0.03, y: height * 0.21)
                shot("tasks-466", width: width * 0.43)
                    .rotationEffect(.degrees(1.5))
                    .offset(x: width * 0.6, y: height * 0.01)
                shot(colorScheme == .dark ? "graphite-pro-466" : "quartz-pro-466", width: width * 0.671)
                    .offset(x: width * 0.165, y: height * 0.06)
            }
        }
        .accessibilityElement()
        .accessibilityLabel(L10n.tr("onboardingproductstage.dayedge.s.month.calendar.d37e1c", "DayEdge's month calendar, daily agenda and tasks"))
    }

    /// One screenshot at the captured window's proportions (932 × 1510),
    /// with the site's hairline and soft shadow following its silhouette.
    @ViewBuilder
    private func shot(_ name: String, width: CGFloat) -> some View {
        if let image = OnboardingImage.named(name) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .aspectRatio(932 / 1510, contentMode: .fit)
                .frame(width: width)
                .shadow(color: OnboardingStyle.screenshotOutline, radius: 0.6)
                .shadow(color: OnboardingStyle.screenshotShadow, radius: 12, y: 10)
        }
    }
}
