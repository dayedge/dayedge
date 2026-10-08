import SwiftUI
import Domain

/// The plain steps (Calendar, Reminders, Weather): a symbol, one idea, one
/// line — the actions are the footer's. Once done, a quiet note says so.
struct OnboardingPromptStep: View {
    let symbol: String
    let title: String
    let message: String
    /// "Calendar connected", "Poznań"…; nil until done.
    var done: String?
    /// The note's symbol: a check, or a slash for access that's off.
    var doneSymbol = "checkmark"

    var body: some View {
        VStack(spacing: 0) {
            Image(systemName: symbol)
                .font(.system(size: 34, weight: .regular))
                .foregroundStyle(OnboardingStyle.muted)
                .accessibilityHidden(true)
            Text(title)
                .font(OnboardingStyle.title)
                .tracking(OnboardingStyle.titleTracking)
                .foregroundStyle(OnboardingStyle.text)
                .padding(.top, 18)
            Text(message)
                .font(OnboardingStyle.lede)
                .foregroundStyle(OnboardingStyle.muted)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)
            Label(done ?? " ", systemImage: doneSymbol)
                .font(OnboardingStyle.small.weight(.medium))
                .foregroundStyle(OnboardingStyle.muted)
                .padding(.top, 16)
                .opacity(done == nil ? 0 : 1)
                .accessibilityHidden(done == nil)
        }
        .frame(maxWidth: 340)
    }
}

extension OnboardingPromptStep {
    static func calendar(_ state: OnboardingState) -> Self {
        Self(symbol: "calendar", title: L10n.tr("onboardingpromptstep.your.calendar.at.a.glance", "Your calendar, at a glance"),
             message: L10n.tr("onboardingpromptstep.see.your.agenda.upcoming.c0cf9f", "See your agenda, upcoming meetings and what's left in your day."),
             done: note(state.calendar, .calendar), doneSymbol: state.calendar == .denied ? "nosign" : "checkmark")
    }

    static func reminders(_ state: OnboardingState) -> Self {
        Self(symbol: "checklist", title: L10n.tr("onboardingpromptstep.tasks.alongside.your.day", "Tasks alongside your day"),
             message: L10n.tr("onboardingpromptstep.bring.apple.reminders.into.d63a33", "Bring Apple Reminders into the same view as your calendar."),
             done: note(state.reminders, .reminders), doneSymbol: state.reminders == .denied ? "nosign" : "checkmark")
    }

    /// "Calendar connected" / "Calendar access is off"; nil before asking.
    private enum Subject { case calendar, reminders }

    private static func note(_ status: SourceAccessStatus, _ subject: Subject) -> String? {
        switch (status, subject) {
        case (.notDetermined, _): nil
        case (.granted, .calendar): L10n.tr("onboarding.calendar.connected", "Calendar connected")
        case (.granted, .reminders): L10n.tr("onboarding.reminders.connected", "Reminders connected")
        case (.denied, .calendar): L10n.tr("onboarding.calendar.access.off", "Calendar access is off")
        case (.denied, .reminders): L10n.tr("onboarding.reminders.access.off", "Reminders access is off")
        }
    }

    static func weather(_ state: OnboardingState) -> Self {
        let locationOff = state.weather == .current && state.location == .denied
        let done: String? = switch state.weather {
        case .unset: nil
        // swiftlint:disable:next void_function_in_ternary - both localization calls return String
        case .current: locationOff ? L10n.tr(
            "onboardingpromptstep.location.access.is.off",
            "Location access is off"
        ) : L10n.tr(
            "onboardingpromptstep.current.location",
            "Current Location"
        )
        case .city(let place): place.title
        }
        return Self(symbol: "location", title: L10n.tr("onboardingpromptstep.weather.where.it.matters", "Weather where it matters"),
                    message: L10n.tr("onboardingpromptstep.use.your.current.location.or.c07652", "Use your current location or choose a city for local weather."), done: done,
                    doneSymbol: locationOff ? "nosign" : "checkmark")
    }
}
