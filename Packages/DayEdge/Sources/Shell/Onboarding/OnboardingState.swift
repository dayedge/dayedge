import Foundation
import Domain

/// What onboarding shows as set up. The mock and the real actions fill the
/// same values.
struct OnboardingState: Equatable {
    var calendar = SourceAccessStatus.notDetermined
    var reminders = SourceAccessStatus.notDetermined
    var weather = WeatherLocationChoice.unset
    /// Location permission, for Current Location.
    var location = SourceAccessStatus.notDetermined
}
