import Foundation

/// Abstraction over "where weather data comes from" — same pattern as
/// `CalendarDataProviding`. Today's implementation calls the free,
/// keyless Open-Meteo API; a `MockWeatherProvider` could stand in for
/// previews/tests without touching the network.
package protocol WeatherProviding {
    /// Returns nil when `date` falls outside the provider's forecast
    /// window (Open-Meteo's free tier only covers today + the next 6
    /// days), when no location is chosen, or when the current location
    /// isn't available — callers just hide the weather UI then, never
    /// showing stale or fabricated data.
    func fetchWeather(for date: Date, at location: WeatherLocationChoice) async throws -> WeatherSummary?
}

/// Whether `date` falls within Open-Meteo's free forecast window (today
/// through the next 6 days) — shared by every view that decides whether
/// it's even worth asking for weather.
package enum WeatherForecastWindow {
    /// Today and the next 6 days: Open-Meteo's free tier.
    package static let dayCount = 7

    package static func contains(_ date: Date, calendar: Calendar = .autoupdatingCurrent) -> Bool {
        guard let daysFromToday = calendar.dateComponents(
            [.day], from: calendar.startOfDay(for: Date()), to: calendar.startOfDay(for: date)
        ).day else { return false }
        return (0..<dayCount).contains(daysFromToday)
    }
}

/// No weather: where nothing has been provided (previews, tests, a view
/// outside the panel).
package struct NoWeatherProvider: WeatherProviding {
    package init() {}

    package func fetchWeather(for date: Date, at location: WeatherLocationChoice) async throws -> WeatherSummary? { nil }
}
