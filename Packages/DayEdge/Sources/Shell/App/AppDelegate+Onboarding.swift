import AppKit
import Domain

extension AppDelegate {
    /// At launch: onboarding for a fresh install (its Calendar step asks),
    /// else the usual Calendar request.
    func startOnboardingOrAskForCalendar() {
        switch OnboardingLaunch.decide(completed: GeneralSettings.hasCompletedOnboarding(),
                                       calendar: calendarAccess.status,
                                       forced: AppConfiguration.showsOnboardingPreview) {
        case .show:
            showOnboarding()
        case .markDoneAndSkip:
            GeneralSettings.setCompletedOnboarding()
            requestCalendarAccessIfNeeded()
        case .skip:
            requestCalendarAccessIfNeeded()
        }
    }

    /// First run: Calendar, Reminders, weather location, then the popover.
    /// Closing the window early leaves it to show again next launch.
    func showOnboarding() {
        let actions = AppOnboardingActions(
            eventStore: eventStore, calendarAccess: calendarAccess, tasks: taskRepository,
            bringBack: { [weak self] in self?.onboardingWindow.bringToFront() },
            onFinish: { [weak self] in
                self?.onboardingWindow.close()
                self?.openPopover(then: nil)
            }
        )
        onboardingWindow.show(model: OnboardingModel(actions: actions, state: actions.currentState), appearance: appearance)
    }
}
