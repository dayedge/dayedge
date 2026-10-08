import Foundation

/// A color as plain sRGB components, so values outside the UI (events,
/// calendars) carry one without SwiftUI. Views read it as `color`.
package struct RGBAColor: Hashable, Sendable {
    package var red: Double
    package var green: Double
    package var blue: Double
    package var alpha: Double

    package init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    /// Neutral, for a calendar with no color of its own.
    package static let gray = RGBAColor(red: 0.557, green: 0.557, blue: 0.576)

    /// The default theme's dot orange — for values with no real calendar.
    package static let placeholder = RGBAColor(red: 0.95, green: 0.66, blue: 0.16)
}
