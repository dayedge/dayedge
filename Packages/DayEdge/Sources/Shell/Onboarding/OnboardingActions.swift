import AppKit
import Domain

/// Everything onboarding asks of the app (`AppOnboardingActions`; tests use
/// the mock). Choose City is the Settings weather location sheet, shown by
/// the view; afterwards `savedWeatherLocation()` says what it saved.
@MainActor
protocol OnboardingActions: AnyObject {
    func requestCalendar() async -> SourceAccessStatus
    func requestReminders() async -> SourceAccessStatus
    func useCurrentLocation() async -> WeatherLocationChoice
    func savedWeatherLocation() -> WeatherLocationChoice
    /// Where a denied permission can be changed.
    func openPrivacySettings(for step: OnboardingStep)
    func openURL(_ url: URL)
    func finish()
}

/// Pretends: a short pause, then success. Requests no permission and
/// changes no setting (tests).
@MainActor
final class MockOnboardingActions: OnboardingActions {
    var pause: Duration
    var onFinish: () -> Void
    /// What the city sheet "saved".
    var savedLocation = WeatherLocationChoice.unset
    private(set) var didFinish = false

    init(pause: Duration = .milliseconds(350), onFinish: @escaping () -> Void = {}) {
        self.pause = pause
        self.onFinish = onFinish
    }

    func requestCalendar() async -> SourceAccessStatus {
        await wait()
        return .granted
    }

    func requestReminders() async -> SourceAccessStatus {
        await wait()
        return .granted
    }

    func useCurrentLocation() async -> WeatherLocationChoice {
        await wait()
        return .current
    }

    func savedWeatherLocation() -> WeatherLocationChoice { savedLocation }

    private(set) var openedSettings: [OnboardingStep] = []
    func openPrivacySettings(for step: OnboardingStep) { openedSettings.append(step) }

    func openURL(_ url: URL) { NSWorkspace.shared.open(url) }

    func finish() {
        didFinish = true
        onFinish()
    }

    private func wait() async { try? await Task.sleep(for: pause) }
}
