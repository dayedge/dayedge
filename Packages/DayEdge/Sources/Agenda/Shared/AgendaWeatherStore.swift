import Foundation
import Observation
import Domain

/// Fetches and caches weather for the agenda's currently visible day
/// sections — split out of `AgendaListView`, which used to call
/// `CachingWeatherService.shared` directly from a `.task(id:)` block.
/// Takes a `WeatherProviding` (the view passes the environment's
/// `weatherProvider`), so this is testable without a network call.
@MainActor
@Observable
package final class AgendaWeatherStore {
    package private(set) var weatherBySection: [Date: WeatherSummary] = [:]
    @ObservationIgnored package var provider: any WeatherProviding
    /// The location `weatherBySection` is for.
    @ObservationIgnored private var locationKey: String?

    package init(provider: any WeatherProviding = NoWeatherProvider()) {
        self.provider = provider
    }

    /// Best-effort per section: a network hiccup or an out-of-window date
    /// just means that section's weather glyph stays hidden, not a crash.
    /// Collected first and written once, and only when something changed:
    /// each write redraws the agenda, and this runs after every page load.
    /// A new location starts empty — never the previous place's weather.
    package func refresh(for sections: [AgendaDaySection], at location: WeatherLocationChoice) async {
        if locationKey != location.key {
            locationKey = location.key
            if !weatherBySection.isEmpty { weatherBySection = [:] }
        }
        var next = weatherBySection
        for section in sections where WeatherForecastWindow.contains(section.date) {
            if let summary = try? await provider.fetchWeather(for: section.date, at: location) {
                next[section.id] = summary
            }
        }
        guard !Task.isCancelled else { return }
        if next != weatherBySection { weatherBySection = next }
    }
}
