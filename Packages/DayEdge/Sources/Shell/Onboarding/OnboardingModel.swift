import Foundation
import Observation
import Domain

/// Onboarding's state and what its buttons do. Each step has one primary
/// action (always the footer's right button) and at most one secondary;
/// both go through `OnboardingActions`.
@MainActor
@Observable
final class OnboardingModel {
    private(set) var flow = OnboardingFlow()
    private(set) var state: OnboardingState
    /// An action is running: buttons wait.
    private(set) var isWorking = false
    /// The weather location sheet is up (Choose City).
    var isChoosingCity = false
    @ObservationIgnored let actions: any OnboardingActions

    init(actions: any OnboardingActions, state: OnboardingState = OnboardingState()) {
        self.actions = actions
        self.state = state
    }

    var step: OnboardingStep { flow.step }

    var primaryTitle: String {
        switch step {
        case .welcome: L10n.tr("onboardingmodel.continue", "Continue")
        // swiftlint:disable:next void_function_in_ternary - both localization calls return String
        case .calendar: state.calendar == .notDetermined ? L10n.tr(
            "onboardingmodel.allow.calendar.access",
            "Allow Calendar Access"
        ) : L10n.tr(
            "onboardingmodel.continue",
            "Continue"
        )
        // swiftlint:disable:next void_function_in_ternary - both localization calls return String
        case .reminders: state.reminders == .notDetermined ? L10n.tr(
            "onboardingmodel.allow.reminders.access",
            "Allow Reminders Access"
        ) : L10n.tr(
            "onboardingmodel.continue",
            "Continue"
        )
        // swiftlint:disable:next void_function_in_ternary - both localization calls return String
        case .weather: state.weather == .unset ? L10n.tr("onboardingmodel.use.my.location", "Use My Location") : L10n.tr("onboardingmodel.continue", "Continue")
        case .ready: L10n.tr("onboardingmodel.open.dayedge", "Open DayEdge")
        }
    }

    /// Replayed (Settings › About), steps show what's already set: a
    /// denied permission offers its System Settings pane, a chosen city
    /// can be changed.
    var secondaryTitle: String? {
        switch step {
        case .calendar: state.calendar == .denied ? L10n.tr("onboardingmodel.open.system.settings", "Open System Settings") : nil
        case .reminders:
            switch state.reminders {
            case .notDetermined: L10n.tr("onboardingmodel.not.now", "Not now")
            case .denied: L10n.tr("onboardingmodel.open.system.settings", "Open System Settings")
            case .granted: nil
            }
        case .weather:
            if case .city = state.weather { L10n.tr("onboardingmodel.change.city", "Change City") } else { L10n.tr("onboardingmodel.choose.city", "Choose City") }
        default: nil
        }
    }

    func primary() async {
        await run {
            switch step {
            case .welcome:
                break
            case .calendar where state.calendar == .notDetermined:
                state.calendar = await actions.requestCalendar()
            case .reminders where state.reminders == .notDetermined:
                state.reminders = await actions.requestReminders()
            case .weather where state.weather == .unset:
                state.weather = await actions.useCurrentLocation()
            case .ready:
                actions.finish()
                return
            default:
                break
            }
            flow.next()
        }
    }

    func secondary() async {
        await run {
            switch step {
            case .calendar where state.calendar == .denied:
                actions.openPrivacySettings(for: .calendar)
            case .reminders where state.reminders == .denied:
                actions.openPrivacySettings(for: .reminders)
            case .reminders:
                flow.next()
            case .weather:
                isChoosingCity = true
            default:
                break
            }
        }
    }

    /// The city sheet closed: a saved city moves on; Cancel stays here.
    func cityChoiceClosed() {
        let saved = actions.savedWeatherLocation()
        guard case .city = saved else { return }
        state.weather = saved
        flow.next()
    }

    func back() {
        guard !isWorking else { return }
        flow.back()
    }

    func open(_ url: URL) { actions.openURL(url) }

    private func run(_ body: () async -> Void) async {
        guard !isWorking else { return }
        isWorking = true
        await body()
        isWorking = false
    }
}
