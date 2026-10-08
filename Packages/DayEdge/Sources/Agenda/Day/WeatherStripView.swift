import SwiftUI
import Domain
import UI

package struct WeatherStripView: View {
    @Environment(\.themePalette) private var theme
    @Environment(\.timeFormat) private var timeFormat

    package let summary: WeatherSummary

    package var body: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center, spacing: 4) {
                    Image(systemName: summary.symbolName)
                        .font(.system(size: 16))
                        .foregroundStyle(theme.warningYellow)
                    Text("\(summary.currentTemperature)°")
                        .font(.system(size: 20, weight: .medium))
                        .tracking(-0.5)
                }
                Text(summary.condition)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(theme.secondaryText)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(width: 90, alignment: .leading)

            DayWeatherGraphView(
                hourly: summary.hourly,
                currentHour: summary.currentHour,
                sunriseHour: summary.sunriseHour,
                sunsetHour: summary.sunsetHour
            )

            VStack(alignment: .leading, spacing: 3) {
                statRow(
                    icon: "arrow.up", temperature: summary.highTemperature,
                    transition: L10n.tr("weather.sunrise", "sunrise"), time: summary.sunriseText(timeFormat)
                )
                statRow(
                    icon: "arrow.down", temperature: summary.lowTemperature,
                    transition: L10n.tr("weather.sunset", "sunset"), time: summary.sunsetText(timeFormat)
                )
            }
            .frame(width: 122, alignment: .leading)
        }
        .foregroundStyle(theme.primaryText)
        .padding(.horizontal, AppTheme.horizontalPadding)
        .frame(height: 44)
    }

    private func statRow(icon: String, temperature: Int, transition: String, time: String) -> some View {
        HStack(spacing: 0) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(theme.secondaryText)
                .frame(width: 10)
            Text("\(temperature)°")
                .font(.system(size: 11, weight: .semibold))
                .monospacedDigit()
                .frame(width: 24, alignment: .leading)
            Color.clear.frame(width: 8, height: 1)
            Text(transition)
                .font(.system(size: 11))
                .foregroundStyle(theme.secondaryText)
                .frame(width: 44, alignment: .leading)
            Text(time)
                .font(.system(size: 11, weight: .semibold))
                .monospacedDigit()
                .frame(width: 36, alignment: .trailing)
        }
    }
}
