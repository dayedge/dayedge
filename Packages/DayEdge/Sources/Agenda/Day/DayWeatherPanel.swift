import SwiftUI
import Domain
import UI

/// The selected day's weather, under the Command Window's mini-month: the
/// Day bar's strip (`WeatherStripView`) stacked for a narrow column, its
/// curve drawn larger. That day's forecast only — never today's standing in
/// for another day; nothing when weather is off or no place is set.
package struct DayWeatherPanel: View {
    @Environment(\.themePalette) private var theme
    @Environment(\.timeFormat) private var timeFormat
    @Environment(\.weatherProvider) private var weatherProvider
    @AppStorage(GeneralSettings.showsWeatherKey) private var showsWeather = true
    @AppStorage(GeneralSettings.weatherLocationKey) private var weatherLocation = ""

    package let date: Date
    /// The column's inner width — the curve's.
    package let width: CGFloat
    package var isActive = true

    @State private var weather: WeatherSummary?

    private var location: WeatherLocationChoice { WeatherLocationChoice(storageValue: weatherLocation) }
    private var isShown: Bool { showsWeather && location != .unset }

    package var body: some View {
        // Always something on screen: an empty view never runs its `.task`,
        // so the forecast would never load.
        ZStack(alignment: .topLeading) {
            Color.clear.frame(height: 0)
            if isShown {
                if let weather {
                    summary(weather)
                } else if !WeatherForecastWindow.contains(date) {
                    Text(L10n.tr("dayweatherpanel.no.forecast", "No forecast for this day"))
                        .font(AppTheme.TextStyle.eventSubtitle)
                        .foregroundStyle(theme.secondaryText)
                }
            }
        }
        .task(id: isActive && isShown ? "\(date.timeIntervalSince1970)-\(weatherLocation)" : nil) {
            // The day's own forecast, or nothing while it loads.
            weather = nil
            guard isActive, isShown, WeatherForecastWindow.contains(date) else { return }
            // Cached by the provider: the same request as the Day bar's.
            let fetched = try? await weatherProvider.fetchWeather(for: date, at: location)
            guard !Task.isCancelled else { return }
            weather = fetched
        }
    }

    private func summary(_ weather: WeatherSummary) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: weather.symbolName)
                    .font(.system(size: 24))
                    .foregroundStyle(theme.warningYellow)
                Text("\(weather.currentTemperature)°")
                    .font(.system(size: 30, weight: .medium))
                    .tracking(-0.6)
                    .foregroundStyle(theme.primaryText)
                VStack(alignment: .leading, spacing: 2) {
                    Text(weather.condition)
                        .font(AppTheme.TextStyle.eventSubtitle)
                        .foregroundStyle(theme.primaryText)
                        .lineLimit(1)
                    HStack(spacing: 8) {
                        stat(icon: "arrow.up", value: "\(weather.highTemperature)°")
                        stat(icon: "arrow.down", value: "\(weather.lowTemperature)°")
                    }
                }
            }

            DayWeatherGraphView(hourly: weather.hourly, currentHour: weather.currentHour,
                                sunriseHour: weather.sunriseHour, sunsetHour: weather.sunsetHour,
                                size: CGSize(width: width, height: 56))

            HStack {
                stat(icon: "sunrise.fill", value: weather.sunriseText(timeFormat))
                Spacer(minLength: 8)
                stat(icon: "sunset.fill", value: weather.sunsetText(timeFormat))
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func stat(icon: String, value: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(theme.secondaryText)
            Text(value)
                .font(.system(size: 12, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(theme.primaryText)
        }
    }

    package init(date: Date, width: CGFloat, isActive: Bool = true) {
        self.date = date
        self.width = width
        self.isActive = isActive
    }
}
