import SwiftUI

/// The richest step: what DayEdge is, beside the product.
struct OnboardingWelcomeStep: View {
    var body: some View {
        HStack(alignment: .center, spacing: 28) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    appIcon
                    Text(L10n.tr("onboarding.eyebrow", "APPLE CALENDAR + REMINDERS, IN YOUR MENU BAR"))
                        .font(OnboardingStyle.eyebrow)
                        .tracking(OnboardingStyle.eyebrowTracking)
                        .foregroundStyle(OnboardingStyle.quiet)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(hero)
                    .font(OnboardingStyle.hero)
                    .tracking(OnboardingStyle.heroTracking)
                    .lineSpacing(-12)
                Text(L10n.tr(
                    "onboardingwelcomestep.dayedge.brings.the.486887",
                    "DayEdge brings the calendars and reminders already on your Mac into one quick menu-bar view. Nothing new to manage."
                ))
                    .font(OnboardingStyle.lede)
                    .foregroundStyle(OnboardingStyle.muted)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
                trust
            }
            .frame(width: 300, alignment: .leading)

            OnboardingProductStage()
                .frame(width: 300, height: 340)
        }
        .padding(.horizontal, 36)
    }

    private var hero: AttributedString {
        var text = AttributedString(L10n.tr("onboarding.hero", "Your day,\ncloser."))
        text.foregroundColor = OnboardingStyle.text
        if let lineBreak = text.range(of: "\n") {
            text[lineBreak.upperBound..<text.endIndex].foregroundColor = OnboardingStyle.muted
        }
        return text
    }

    @ViewBuilder
    private var appIcon: some View {
        if let icon = OnboardingImage.named("AppIcon", "png") {
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .frame(width: 52, height: 52)
                .accessibilityHidden(true)
        }
    }

    /// "Free · Open source · Private by design".
    private var trust: some View {
        HStack(spacing: 8) {
            Text(L10n.tr("onboardingwelcomestep.free", "Free"))
                .font(OnboardingStyle.small.weight(.medium))
                .foregroundStyle(OnboardingStyle.buttonLabel)
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .background(OnboardingStyle.button, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
            Text("·").foregroundStyle(OnboardingStyle.quiet)
            Text(L10n.tr("onboardingwelcomestep.open.source", "Open source"))
            Text("·").foregroundStyle(OnboardingStyle.quiet)
            Text(L10n.tr("onboardingwelcomestep.private.by.design", "Private by design"))
        }
        .font(OnboardingStyle.small)
        .foregroundStyle(OnboardingStyle.muted)
    }
}
