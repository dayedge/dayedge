import SwiftUI
import Domain

/// A small, quiet Apple-Weather-style graph: a smoothed temperature curve
/// with a soft gradient fill, plus faint precipitation-probability bars
/// beneath it. Deliberately unlabeled at rest (no axes/numbers) — it's
/// meant to read as an ambient shape — but hovering reveals the exact
/// hour's temperature and rain chance via a marker line and tooltip.
package struct DayWeatherGraphView: View {
    @Environment(\.themePalette) private var theme

    package let hourly: [HourlyWeatherPoint]
    package let currentHour: Int?
    /// Fractional hour-of-day (e.g. 6.2 for 6:12am) — where the night
    /// shading and the sun/moon markers sit along the strip.
    package var sunriseHour: Double?
    package var sunsetHour: Double?

    @State private var hoveredIndex: Int?

    private static let width: CGFloat = 150
    private static let height: CGFloat = 36

    package var body: some View {
        let plot = WeatherGraphPlot(hourly: hourly, size: CGSize(width: Self.width, height: Self.height))
        ZStack(alignment: .top) {
            // Shapes, not `Canvas`: every `Canvas` draw briefly allocated
            // ~130 MB of rendering buffers (measured), for this 150×36
            // strip — each time the Day view showed a day. The same paths
            // as shapes cost next to nothing and draw the same.
            PlotPathShape(path: plot.precipitationBars)
                .fill(theme.controlAccent.opacity(0.28))
                .frame(width: Self.width, height: Self.height)
                .mask(precipitationHorizontalMask)
                .mask(verticalMask)

            ZStack(alignment: .topLeading) {
                PlotPathShape(path: plot.temperatureCurve)
                    .stroke(theme.dotOrange, lineWidth: 1.5)

                if let currentHour, let now = plot.point(at: currentHour) {
                    PlotPathShape(path: Path(ellipseIn: CGRect(x: now.x - 2.5, y: now.y - 2.5, width: 5, height: 5)))
                        .fill(theme.primaryText)
                }

                if let hoveredIndex, let hovered = plot.point(at: hoveredIndex) {
                    PlotPathShape(path: Path { marker in
                        marker.move(to: CGPoint(x: hovered.x, y: 0))
                        marker.addLine(to: CGPoint(x: hovered.x, y: Self.height))
                    })
                    .stroke(theme.primaryText.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
                    PlotPathShape(path: Path(ellipseIn: CGRect(x: hovered.x - 3, y: hovered.y - 3, width: 6, height: 6)))
                        .fill(theme.dotOrange)
                }
            }
            .frame(width: Self.width, height: Self.height)
            .mask(chartHorizontalMask)
            .mask(verticalMask)

            if let hoveredIndex, let point = hourly[safe: hoveredIndex] {
                tooltip(for: point)
                    .offset(y: -22)
                    .transition(.opacity)
                    // Keeps the tooltip from stealing the hover it's
                    // reacting to, which would otherwise flicker it on/off.
                    .allowsHitTesting(false)
            }
        }
        .frame(width: Self.width, height: Self.height)
        .contentShape(Rectangle())
        .onContinuousHover { phase in
            switch phase {
            case .active(let location):
                hoveredIndex = index(forX: location.x)
            case .ended:
                hoveredIndex = nil
            }
        }
        .animation(.easeOut(duration: 0.12), value: hoveredIndex)
    }

    private var chartHorizontalMask: some View {
        LinearGradient(
            stops: [
                .init(color: .clear, location: 0),
                .init(color: .white.opacity(0.6), location: 0.12),
                .init(color: .white, location: 0.20),
                .init(color: .white, location: 0.80),
                .init(color: .white.opacity(0.6), location: 0.88),
                .init(color: .clear, location: 1)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    private var precipitationHorizontalMask: some View {
        LinearGradient(
            stops: [
                .init(color: .clear, location: 0),
                .init(color: .white.opacity(0.42), location: 0.16),
                .init(color: .white, location: 0.26),
                .init(color: .white, location: 0.74),
                .init(color: .white.opacity(0.42), location: 0.84),
                .init(color: .clear, location: 1)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    private var verticalMask: some View {
        LinearGradient(
            stops: [
                .init(color: .white.opacity(0.55), location: 0),
                .init(color: .white, location: 0.18),
                .init(color: .white, location: 0.82),
                .init(color: .white.opacity(0.55), location: 1)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private func index(forX x: CGFloat) -> Int? {
        guard hourly.count > 1 else { return nil }
        let fraction = min(max(x / Self.width, 0), 1)
        return Int((fraction * CGFloat(hourly.count - 1)).rounded())
    }

    /// Maps a fractional hour-of-day to an x position on the same scale
    /// `draw(context:size:)`'s `point(at:)` uses for the temperature curve
    /// (array index, not clock hour) — assumes `hourly` is the contiguous
    /// hour range it's built from (see `OpenMeteoWeatherService`).
    private func xForHour(_ hour: Double) -> CGFloat {
        guard hourly.count > 1, let firstHour = hourly.first?.hour, let lastHour = hourly.last?.hour,
              lastHour > firstHour else { return 0 }
        let fraction = (hour - Double(firstHour)) / Double(lastHour - firstHour)
        return Self.width * CGFloat(min(max(fraction, 0), 1))
    }

    private func tooltip(for point: HourlyWeatherPoint) -> some View {
        HStack(spacing: 5) {
            Text("\(point.hour):00")
                .foregroundStyle(theme.secondaryText)
            Text("\(Int(point.temperature.rounded()))°")
                .foregroundStyle(theme.primaryText)
            if point.precipitationProbability > 0 {
                Label("\(Int(point.precipitationProbability))%", systemImage: "drop.fill")
                    .foregroundStyle(theme.controlAccent)
            }
        }
        .font(.system(size: 10, weight: .medium))
        .labelStyle(.titleAndIcon)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(theme.weatherTooltipFill))
        .fixedSize()
    }

}

/// The graph's geometry — the temperature curve, its points and the rain
/// bars — for a strip of `size`.
private struct WeatherGraphPlot {
    let hourly: [HourlyWeatherPoint]
    let size: CGSize

    /// A temperature's point; nil outside the data.
    func point(at index: Int) -> CGPoint? {
        guard hourly.count > 1, hourly.indices.contains(index) else { return nil }
        let temperatures = hourly.map(\.temperature)
        let minTemperature = temperatures.min() ?? 0
        let temperatureRange = max((temperatures.max() ?? 1) - minTemperature, 1)
        // Leaves headroom top and bottom so the curve's peaks/valleys never
        // touch the strip's edges.
        let topInset: CGFloat = size.height * 0.12
        let plotHeight = size.height - topInset * 2
        let x = size.width * CGFloat(index) / CGFloat(hourly.count - 1)
        let normalized = (hourly[index].temperature - minTemperature) / temperatureRange
        return CGPoint(x: x, y: topInset + plotHeight * (1 - normalized))
    }

    var temperatureCurve: Path {
        guard hourly.count > 1 else { return Path() }
        return smoothedPath(through: hourly.indices.compactMap(point(at:)))
    }

    var precipitationBars: Path {
        var path = Path()
        guard !hourly.isEmpty else { return path }
        let barSlotWidth = size.width / CGFloat(hourly.count)
        for (index, point) in hourly.enumerated() where point.precipitationProbability > 0 {
            let barHeight = size.height * CGFloat(point.precipitationProbability / 100) * 0.55
            let rect = CGRect(
                x: CGFloat(index) * barSlotWidth,
                y: size.height - barHeight,
                width: barSlotWidth * 0.5,
                height: barHeight
            )
            path.addRoundedRect(in: rect, cornerSize: CGSize(width: 1, height: 1))
        }
        return path
    }

    /// Quadratic-through-midpoints smoothing: cheap, no external deps, and
    /// smooth enough for a glanceable sparkline at this size.
    private func smoothedPath(through points: [CGPoint]) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)

        for i in 1..<points.count {
            let previous = points[i - 1]
            let current = points[i]
            let midpoint = CGPoint(x: (previous.x + current.x) / 2, y: (previous.y + current.y) / 2)
            path.addQuadCurve(to: midpoint, control: previous)
        }
        path.addLine(to: points[points.count - 1])
        return path
    }
}

/// A precomputed path, drawn as a shape.
private struct PlotPathShape: Shape {
    let path: Path
    func path(in rect: CGRect) -> Path { path }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
