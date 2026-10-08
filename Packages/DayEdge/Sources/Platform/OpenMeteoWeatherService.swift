import Foundation
import Domain

/// Fetches current + daily/hourly weather from Open-Meteo (open-meteo.com)
/// — a free forecast API that needs no API key, account, or signing
/// entitlement (unlike WeatherKit), which makes it the right fit for a
/// plain, unsigned Phase 1 executable.
///
/// Split into a network fetch (`fetchRawForecast`) and a pure derivation
/// (`summary(from:for:)`) so `CachingWeatherService` can fetch the whole
/// multi-day payload once and derive any date's `WeatherSummary` from it
/// with no further network calls.
package struct OpenMeteoWeatherService {
    /// Matches the `forecast_days` we request below — today plus the next
    /// 6 days.
    package static let forecastDayCount = WeatherForecastWindow.dayCount

    package static let dayKeyFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    package func fetchRawForecast(latitude: Double, longitude: Double) async throws -> OpenMeteoForecast {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: "\(latitude)"),
            URLQueryItem(name: "longitude", value: "\(longitude)"),
            URLQueryItem(name: "current_weather", value: "true"),
            URLQueryItem(name: "daily", value: "weathercode,temperature_2m_max,temperature_2m_min,sunrise,sunset"),
            URLQueryItem(name: "hourly", value: "temperature_2m,precipitation_probability"),
            URLQueryItem(name: "forecast_days", value: "\(Self.forecastDayCount)"),
            URLQueryItem(name: "timezone", value: "auto")
        ]

        let (data, _) = try await URLSession.shared.data(from: components.url!)
        return try JSONDecoder().decode(OpenMeteoForecast.self, from: data)
    }

    package static func summary(from forecast: OpenMeteoForecast, for date: Date) -> WeatherSummary? {
        let targetKey = dayKeyFormatter.string(from: date)
        guard let index = forecast.daily.time.firstIndex(of: targetKey) else {
            return nil // Outside the forecast window — nothing to show.
        }

        let high = forecast.daily.temperature_2m_max[index]
        let low = forecast.daily.temperature_2m_min[index]
        let isToday = Calendar.autoupdatingCurrent.isDateInToday(date)

        let heroTemperature = isToday ? forecast.current_weather.temperature : (high + low) / 2
        let code = isToday ? forecast.current_weather.weathercode : forecast.daily.weathercode[index]

        let dayPrefix = targetKey + "T"
        var hourly: [HourlyWeatherPoint] = []
        for (i, timestamp) in forecast.hourly.time.enumerated() where timestamp.hasPrefix(dayPrefix) {
            guard let hourString = timestamp.split(separator: "T").last,
                  let hour = Int(hourString.prefix(2)) else { continue }
            hourly.append(HourlyWeatherPoint(
                hour: hour,
                temperature: forecast.hourly.temperature_2m[i],
                precipitationProbability: Double(forecast.hourly.precipitation_probability[i])
            ))
        }
        hourly.sort { $0.hour < $1.hour }

        let currentHourIndex = isToday
            ? hourly.firstIndex(where: { $0.hour == Calendar.autoupdatingCurrent.component(.hour, from: Date()) })
            : nil

        return WeatherSummary(
            currentTemperature: Int(heroTemperature.rounded()),
            condition: condition(for: code),
            symbolName: symbolName(for: code),
            highTemperature: Int(high.rounded()),
            lowTemperature: Int(low.rounded()),
            sunrise: formatTime(forecast.daily.sunrise[index]),
            sunset: formatTime(forecast.daily.sunset[index]),
            sunriseHour: fractionalHour(forecast.daily.sunrise[index]),
            sunsetHour: fractionalHour(forecast.daily.sunset[index]),
            hourly: hourly,
            currentHour: currentHourIndex
        )
    }

    private static func formatTime(_ isoLocalString: String) -> String {
        let parser = DateFormatter()
        parser.dateFormat = "yyyy-MM-dd'T'HH:mm"
        guard let date = parser.date(from: isoLocalString) else { return "–" }
        let formatter = DateFormatter()
        formatter.dateFormat = "H:mm"
        return formatter.string(from: date)
    }

    private static func fractionalHour(_ isoLocalString: String) -> Double {
        let parts = isoLocalString.split(separator: "T").last?.split(separator: ":") ?? []
        guard parts.count == 2, let hour = Double(parts[0]), let minute = Double(parts[1]) else { return 0 }
        return hour + minute / 60
    }

    /// Maps Open-Meteo's WMO weather codes to an SF Symbol. Grouped by the
    /// broad categories Open-Meteo documents rather than one case per code.
    private static func symbolName(for code: Int) -> String {
        switch code {
        case 0: return "sun.max.fill"
        case 1, 2: return "cloud.sun.fill"
        case 3: return "cloud.fill"
        case 45, 48: return "cloud.fog.fill"
        case 51, 53, 55, 56, 57: return "cloud.drizzle.fill"
        case 61, 63, 65, 66, 67: return "cloud.rain.fill"
        case 71, 73, 75, 77, 85, 86: return "cloud.snow.fill"
        case 80, 81, 82: return "cloud.heavyrain.fill"
        case 95, 96, 99: return "cloud.bolt.fill"
        default: return "cloud.fill"
        }
    }

    // swiftlint:disable:next cyclomatic_complexity - a lookup table, one case per WMO group
    private static func condition(for code: Int) -> String {
        switch code {
        case 0: return L10n.tr("openmeteoweatherservice.clear", "Clear")
        case 1, 2: return L10n.tr("openmeteoweatherservice.partly.cloudy", "Partly Cloudy")
        case 3: return L10n.tr("openmeteoweatherservice.overcast", "Overcast")
        case 45, 48: return L10n.tr("openmeteoweatherservice.foggy", "Foggy")
        case 51, 53, 55, 56, 57: return L10n.tr("openmeteoweatherservice.drizzle", "Drizzle")
        case 61, 63, 65, 66, 67: return L10n.tr("openmeteoweatherservice.rain", "Rain")
        case 71, 73, 75, 77: return L10n.tr("openmeteoweatherservice.snow", "Snow")
        case 80, 81, 82: return L10n.tr("openmeteoweatherservice.rain.showers", "Rain Showers")
        case 85, 86: return L10n.tr("openmeteoweatherservice.snow.showers", "Snow Showers")
        case 95, 96, 99: return L10n.tr("openmeteoweatherservice.thunderstorm", "Thunderstorm")
        default: return "—"
        }
    }
}

package struct OpenMeteoForecast: Decodable, Sendable {
    package struct CurrentWeather: Decodable, Sendable {
        package let temperature: Double
        package let weathercode: Int
    }
    package struct Daily: Decodable, Sendable {
        package let time: [String]
        package let weathercode: [Int]
        package let temperature_2m_max: [Double]
        package let temperature_2m_min: [Double]
        package let sunrise: [String]
        package let sunset: [String]
    }
    package struct Hourly: Decodable, Sendable {
        package let time: [String]
        package let temperature_2m: [Double]
        package let precipitation_probability: [Int]
    }

    package let current_weather: CurrentWeather
    package let daily: Daily
    package let hourly: Hourly
}
