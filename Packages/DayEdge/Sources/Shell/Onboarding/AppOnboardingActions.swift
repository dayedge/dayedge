import AppKit
import EventKit
import Domain
import Platform

/// Onboarding's actions over what the app already has: EventKit's Calendar
/// request (then the permission monitor applies it, as at launch), the task
/// repository's Reminders request (as the Tasks view does), Current
/// Location and the weather setting.
@MainActor
final class AppOnboardingActions: OnboardingActions {
    private let eventStore: EKEventStore
    private let calendarAccess: CalendarPermissionMonitor
    private let tasks: TaskRepository
    /// Brings the onboarding window back after a system prompt.
    private let bringBack: () -> Void
    private let onFinish: () -> Void

    init(eventStore: EKEventStore, calendarAccess: CalendarPermissionMonitor, tasks: TaskRepository,
         bringBack: @escaping () -> Void, onFinish: @escaping () -> Void) {
        self.eventStore = eventStore
        self.calendarAccess = calendarAccess
        self.tasks = tasks
        self.bringBack = bringBack
        self.onFinish = onFinish
    }

    /// What's already decided, so finished steps show it.
    var currentState: OnboardingState {
        OnboardingState(calendar: calendarAccess.status, reminders: tasks.accessStatus,
                        weather: GeneralSettings.weatherLocation(), location: CurrentLocation.shared.status)
    }

    func requestCalendar() async -> SourceAccessStatus {
        _ = await EventKitAccess.requestAccessIfNeeded(eventStore: eventStore)
        calendarAccess.check()
        bringBack()
        return calendarAccess.status
    }

    func requestReminders() async -> SourceAccessStatus {
        await tasks.requestAccess()
        bringBack()
        return tasks.accessStatus
    }

    /// Saves Current Location and asks for permission — only now, because
    /// the user chose it — then waits for the answer (the prompt returns
    /// at once) before bringing the window back.
    func useCurrentLocation() async -> WeatherLocationChoice {
        GeneralSettings.setWeatherLocation(.current)
        let location = CurrentLocation.shared
        guard location.status == .notDetermined else { return .current }
        location.requestAccess()
        for _ in 0..<600 where location.status == .notDetermined {
            try? await Task.sleep(for: .milliseconds(200))
        }
        bringBack()
        return .current
    }

    func savedWeatherLocation() -> WeatherLocationChoice { GeneralSettings.weatherLocation() }

    func openPrivacySettings(for step: OnboardingStep) {
        switch step {
        case .calendar: EventKitAccess.openPrivacySettings(for: .event)
        case .reminders: EventKitAccess.openPrivacySettings(for: .reminder)
        case .weather: CurrentLocation.shared.openPrivacySettings()
        case .welcome, .ready: break
        }
    }

    func openURL(_ url: URL) { NSWorkspace.shared.open(url) }

    func finish() {
        GeneralSettings.setCompletedOnboarding()
        onFinish()
    }
}
