import SwiftUI

/// Done: where DayEdge lives now, and — quietly, below — how to support it.
struct OnboardingReadyStep: View {
    let onOpenLink: (URL) -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            Text(L10n.tr("onboardingreadystep.you.re.ready", "You're ready."))
                .font(OnboardingStyle.title)
                .tracking(OnboardingStyle.titleTracking)
                .foregroundStyle(OnboardingStyle.text)
            Text(L10n.tr("onboardingreadystep.dayedge.now.lives.in.your.menu.bar", "DayEdge now lives in your menu bar."))
                .font(OnboardingStyle.lede)
                .foregroundStyle(OnboardingStyle.muted)
                .padding(.top, 8)
            Spacer(minLength: 0)
            support
                .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity)
    }

    /// Optional support, separate from finishing onboarding.
    private var support: some View {
        VStack(spacing: 6) {
            Rectangle()
                .fill(OnboardingStyle.line)
                .frame(width: 200, height: 1)
                .padding(.bottom, 10)
            Text(L10n.tr("onboardingreadystep.support.dayedge", "Support DayEdge"))
                .font(OnboardingStyle.lede.weight(.medium))
                .foregroundStyle(OnboardingStyle.text)
            Text(L10n.tr(
                "onboardingreadystep.dayedge.is.free.and.open.e5e7cf", "DayEdge is free and open source.\nOptional support helps continued development."
            ))
                .font(OnboardingStyle.small)
                .foregroundStyle(OnboardingStyle.quiet)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
            Button { onOpenLink(AppLinks.kofi) } label: {
                Label(L10n.tr("onboardingreadystep.support.on.ko.fi", "Support on Ko-fi"), systemImage: "cup.and.saucer")
                    .font(OnboardingStyle.lede.weight(.medium))
            }
            .buttonStyle(.bordered)
            .padding(.top, 4)
        }
    }

}
