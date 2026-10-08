import Foundation

/// Static placeholder data — the app has no weather source yet. Shaped so
/// swapping in a real provider later only touches this one model, not the
/// view.
package struct WeatherSummary: Sendable, Equatable {
    package let currentTemperature: Int
    package let condition: String
    package let symbolName: String
    package let highTemperature: Int
    package let lowTemperature: Int
    package let sunrise: String
    package let sunset: String
    /// Fractional hour-of-day (e.g. 6.2 for 6:12am) — lets the mini graph
    /// place a sunrise/sunset marker and shade night precisely, rather
    /// than only having the rounded display strings above.
    package let sunriseHour: Double
    package let sunsetHour: Double
    /// One point per hour of the day, for the mini temperature/rain graph.
    package let hourly: [HourlyWeatherPoint]
    /// The current hour, for the graph's "now" marker — nil for a day
    /// other than today, or once it's off the end of the array.
    package let currentHour: Int?

    package init(
        currentTemperature: Int,
        condition: String,
        symbolName: String,
        highTemperature: Int,
        lowTemperature: Int,
        sunrise: String,
        sunset: String,
        sunriseHour: Double,
        sunsetHour: Double,
        hourly: [HourlyWeatherPoint],
        currentHour: Int?
    ) {
        self.currentTemperature = currentTemperature
        self.condition = condition
        self.symbolName = symbolName
        self.highTemperature = highTemperature
        self.lowTemperature = lowTemperature
        self.sunrise = sunrise
        self.sunset = sunset
        self.sunriseHour = sunriseHour
        self.sunsetHour = sunsetHour
        self.hourly = hourly
        self.currentHour = currentHour
    }
}

extension WeatherSummary {
    /// Sunrise and sunset in the user's time format, from the exact hours
    /// ("–" when the forecast had none).
    package func sunriseText(_ format: TimeFormat) -> String { clock(sunriseHour, fallback: sunrise, format) }
    package func sunsetText(_ format: TimeFormat) -> String { clock(sunsetHour, fallback: sunset, format) }

    private func clock(_ hour: Double, fallback: String, _ format: TimeFormat) -> String {
        guard fallback != "–" else { return fallback }
        return format.time(minutesSinceMidnight: Int((hour * 60).rounded()))
    }
}

package struct HourlyWeatherPoint: Sendable, Equatable {
    package let hour: Int
    package let temperature: Double
    package let precipitationProbability: Double

    package init(hour: Int, temperature: Double, precipitationProbability: Double) {
        self.hour = hour
        self.temperature = temperature
        self.precipitationProbability = precipitationProbability
    }
}
