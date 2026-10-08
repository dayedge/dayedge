import Foundation

/// The first-run steps, in order.
enum OnboardingStep: Int, CaseIterable {
    case welcome, calendar, reminders, weather, ready
}

/// Where onboarding is: one step at a time, Back from every step but the
/// first.
struct OnboardingFlow: Equatable {
    static let count = OnboardingStep.allCases.count

    private(set) var step = OnboardingStep.welcome

    var canGoBack: Bool { step != .welcome }
    /// 1-based, for "2 of 5".
    var position: Int { step.rawValue + 1 }

    mutating func next() {
        if let following = OnboardingStep(rawValue: step.rawValue + 1) { step = following }
    }

    mutating func back() {
        if let previous = OnboardingStep(rawValue: step.rawValue - 1) { step = previous }
    }
}
