import SwiftUI
import Domain

/// Which side of the weather glyph the hover tooltip should pop out on.
/// The agenda scrolls inside a real `NSScrollView` clip region, so a
/// tooltip that always pops upward gets clipped whenever its header is
/// near the top of the visible viewport (the default, most common state)
/// — the caller decides per-header which side has room.
package enum WeatherTooltipPlacement {
    case above
    case below
}

package struct AgendaDayHeaderView: View {
    @Environment(\.themePalette) private var theme
    @Environment(\.displayScale) private var displayScale
    @Environment(\.dateFormatter) private var dateFormatter

    /// The day; nil for search's undated tasks ("NO DATE").
    package let date: Date?
    package let isToday: Bool
    /// Count of the day's events, excluding cancelled ones. 0 hides the
    /// count (an empty day already says "No events" in its body).
    package var eventCount: Int = 0
    package var taskCount: Int = 0
    package var weather: WeatherSummary?
    package var tooltipPlacement: WeatherTooltipPlacement = .above
    package var style: AgendaHeaderStyle = .inlineAgenda

    @State private var isHoveringWeather = false

    package var body: some View {
        HStack(spacing: 6) {
            Text(title)
                .font(AppTheme.TextStyle.sectionHeader)
                .foregroundStyle(isToday ? theme.todayAccent : theme.secondaryText)

            if let countLabel = DayCountLabel.text(events: eventCount, tasks: taskCount) {
                Text("· \(countLabel)")
                    .font(.system(size: 11))
                    .foregroundStyle(theme.content.quietMetadata)
            }

            Spacer(minLength: 8)

            if let weather {
                HStack(spacing: 5) {
                    Text("\(weather.highTemperature)°/\(weather.lowTemperature)°")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(theme.secondaryText)
                    Image(systemName: weather.symbolName)
                        .font(.system(size: 12))
                        .foregroundStyle(theme.warningYellow)
                }
                .onHover { isHoveringWeather = $0 }
                // A native popover (see `TooltipOverlay.swift`) rather
                // than a local `.overlay` — a local overlay both risks
                // overflowing past the window's edge (no way to know the
                // window's actual bounds) and, since this header can be
                // the `Section`'s *pinned* one, an anchor-based approach
                // silently failed to resolve a position at all.
                .hoverTooltip(
                    isPresented: isHoveringWeather,
                    edge: tooltipPlacement == .above ? .top : .bottom
                ) {
                    WeatherDetailTooltip(weather: weather)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, AppTheme.horizontalPadding)
        .padding(.top, 16)
        .padding(.bottom, 6)
        .background(theme.agendaHeaderFill(for: style))
        // One physical pixel of plain color, only where the theme asks.
        .overlay(alignment: .bottom) {
            if theme.showsAgendaSectionSeparator {
                Rectangle()
                    .fill(theme.agendaSectionSeparatorColor)
                    .frame(height: 1 / max(displayScale, 1))
                    .padding(.horizontal, AppTheme.horizontalPadding)
            }
        }
    }

    package init(
        date: Date?,
        isToday: Bool,
        eventCount: Int = 0,
        taskCount: Int = 0,
        weather: WeatherSummary? = nil,
        tooltipPlacement: WeatherTooltipPlacement = .above,
        style: AgendaHeaderStyle = .inlineAgenda
    ) {
        self.date = date
        self.isToday = isToday
        self.eventCount = eventCount
        self.taskCount = taskCount
        self.weather = weather
        self.tooltipPlacement = tooltipPlacement
        self.style = style
    }
}

extension AgendaDayHeaderView {
    /// "WEDNESDAY 7 OCT" / "WEDNESDAY OCT 7" (the region's order), "TODAY
    /// 7 OCT", the year only outside the current one.
    package var title: String {
        guard let date else { return L10n.tr("agendadayheaderview.no.date", "NO DATE") }
        guard isToday else { return dateFormatter.format(date, .compact).uppercased() }
        let today = dateFormatter.relativeDay(date) ?? L10n.tr("agendadayheaderview.today", "Today")
        return "\(today) \(dateFormatter.format(date, .short))".uppercased()
    }
}

/// The richer hover tooltip for a day's weather glyph: a hero icon+temp
/// (matching the day view's own weather strip), then high/low and
/// sunrise/sunset as a compact 2x2 grid below.
private struct WeatherDetailTooltip: View {
    @Environment(\.themePalette) private var theme
    @Environment(\.timeFormat) private var timeFormat

    let weather: WeatherSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: weather.symbolName)
                    .font(.system(size: 22))
                    .foregroundStyle(theme.warningYellow)
                VStack(alignment: .leading, spacing: 0) {
                    Text("\(weather.currentTemperature)°")
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(theme.primaryText)
                    Text(weather.condition)
                        .font(.system(size: 11))
                        .foregroundStyle(theme.secondaryText)
                }
            }

            Rectangle()
                .fill(theme.chrome.badgeFill)
                .frame(height: 1)

            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 5) {
                GridRow {
                    statCell(icon: "arrow.up", value: "\(weather.highTemperature)°")
                    statCell(icon: "sunrise.fill", value: weather.sunriseText(timeFormat))
                }
                GridRow {
                    statCell(icon: "arrow.down", value: "\(weather.lowTemperature)°")
                    statCell(icon: "sunset.fill", value: weather.sunsetText(timeFormat))
                }
            }
        }
        .padding(11)
        // Same background color as `DayGlanceView`'s popover, so the
        // system-drawn chrome (rounding, arrow, shadow) matches too.
        .background(theme.background)
        .fixedSize()
    }

    private func statCell(icon: String, value: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundStyle(theme.secondaryText)
            Text(value)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(theme.primaryText)
                .monospacedDigit()
        }
    }
}
