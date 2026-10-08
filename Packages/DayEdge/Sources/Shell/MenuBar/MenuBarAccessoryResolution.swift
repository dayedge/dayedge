import Foundation
import Domain

// swiftlint:disable function_parameter_count - every input the menu bar accessory depends on, labelled
/// What the status item's right-hand accessory should show, plus which
/// event (if any) clicking that accessory should join. Pure — testable
/// without any `NSStatusItem`/AppKit involved, the same way
/// `preferredNowTarget`/`MenuBarEventIndicatorResolver.resolve` already
/// are. Split out of `MenuBarStateController.refresh()`'s side-effecting
/// body so this decision can be tested directly.
func resolveMenuBarAccessory(
    events: [AgendaEventModel],
    on day: Date,
    now: Date,
    calendar: Calendar,
    indicatorConfiguration: MenuBarEventIndicatorConfiguration,
    callReadinessStrategy: CallReadinessStrategy,
    timeFormat: TimeFormat = .twentyFourHour
) -> (accessory: MenuBarAccessory?, readyCallEvent: AgendaEventModel?) {
    guard indicatorConfiguration.isEnabled else {
        let event = callReadinessStrategy.readyEvent(events: events, now: now, calendar: calendar)
        let accessory = event?.videoService.map(MenuBarAccessory.callIcon)
        return (accessory, event)
    }

    guard let indicatorState = MenuBarEventIndicatorResolver.resolve(
        events: events, on: day, now: now, calendar: calendar, configuration: indicatorConfiguration
    ) else {
        return (nil, nil)
    }

    let accessory = MenuBarAccessory.contextual(
        state: indicatorState,
        configuration: indicatorConfiguration,
        calendar: calendar,
        timeFormat: timeFormat
    )
    let readyCallEvent = indicatorState.event.flatMap { ($0.meetingLink?.canJoin ?? false) ? $0 : nil }
    return (accessory, readyCallEvent)
}
// swiftlint:enable function_parameter_count
