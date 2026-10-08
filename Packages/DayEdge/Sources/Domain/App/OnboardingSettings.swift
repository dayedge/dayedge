import Foundation

extension GeneralSettings {
    /// Set when the user finishes onboarding (or, for someone who used
    /// DayEdge before it existed, on their first launch with it).
    package static let hasCompletedOnboardingKey = "com.dayedge.onboarding.completed"

    package static func hasCompletedOnboarding(defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: hasCompletedOnboardingKey)
    }

    package static func setCompletedOnboarding(defaults: UserDefaults = .standard) {
        defaults.set(true, forKey: hasCompletedOnboardingKey)
    }
}

/// Whether to show onboarding at launch: only to fresh installs. Calendar
/// access already decided means DayEdge was used before onboarding
/// existed — that counts as done.
package enum OnboardingLaunch {
    package enum Decision: Equatable {
        case show
        case skip
        /// Skip, and record it as done.
        case markDoneAndSkip
    }

    package static func decide(completed: Bool, calendar: SourceAccessStatus, forced: Bool) -> Decision {
        if forced { return .show }
        if completed { return .skip }
        return calendar == .notDetermined ? .show : .markDoneAndSkip
    }
}
