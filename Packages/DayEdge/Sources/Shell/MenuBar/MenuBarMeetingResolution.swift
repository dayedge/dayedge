import Foundation
import Domain

// swiftlint:disable function_parameter_count - every input the meeting presentation depends on, labelled
/// Resolves the independent meeting item and the event its click joins.
func resolveMenuBarMeeting(
    events: [AgendaEventModel],
    on day: Date,
    now: Date,
    calendar: Calendar,
    indicatorConfiguration: MenuBarEventIndicatorConfiguration,
    callReadinessStrategy: CallReadinessStrategy,
    timeFormat: TimeFormat = .twentyFourHour
) -> (presentation: MenuBarMeetingPresentation?, readyCallEvent: AgendaEventModel?) {
    guard indicatorConfiguration.isEnabled else {
        let event = callReadinessStrategy.readyEvent(events: events, now: now)
        let presentation = event?.videoService.map(MenuBarMeetingPresentation.callIcon)
        return (presentation, event)
    }

    guard let indicatorState = MenuBarEventIndicatorResolver.resolve(
        events: events, on: day, now: now, calendar: calendar, configuration: indicatorConfiguration
    ) else {
        return (nil, nil)
    }

    let presentation = MenuBarMeetingPresentation.contextual(
        state: indicatorState,
        configuration: indicatorConfiguration,
        calendar: calendar,
        timeFormat: timeFormat
    )
    let readyCallEvent = indicatorState.event.flatMap { ($0.meetingLink?.canJoin ?? false) ? $0 : nil }
    return (presentation, readyCallEvent)
}
// swiftlint:enable function_parameter_count
