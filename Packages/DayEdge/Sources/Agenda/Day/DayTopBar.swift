import SwiftUI
import Domain
import UI

/// The Day view's bar above the timeline: weather, then the all-day lane.
/// A panel fades in or out and what remains slides into place — only when
/// the bar's shape changes, never when just its values do (two days that
/// both have weather swap numbers without moving).
struct DayTopBar: View {
    let date: Date
    /// nil: no strip.
    let weather: WeatherSummary?
    let allDayEvents: [AgendaEventModel]
    /// nil: changes are instant.
    var animation: Animation?
    var selectedEventID: String?
    var detailPresentationRequest: EventDetailPresentationRequest?
    var onDetailPresentationChange: (String, Bool) -> Void = { _, _ in }

    var body: some View {
        VStack(spacing: 0) {
            if let weather {
                WeatherStripView(summary: weather)
                    .padding(.top, AppTheme.Metrics.dayWeatherTopGap)
                    .padding(.bottom, AppTheme.Metrics.dayWeatherContentGap)
                    .transition(.opacity)
            }

            AllDayRowView(
                date: date,
                events: allDayEvents,
                topPadding: weather == nil ? 10 : 0,
                selectedEventID: selectedEventID,
                detailPresentationRequest: detailPresentationRequest,
                onDetailPresentationChange: onDetailPresentationChange
            )
        }
        .animation(animation, value: weather != nil)
        .animation(animation, value: allDayEvents.count)
    }
}
