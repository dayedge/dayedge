import SwiftUI
import Domain

extension RGBAColor {
    package var color: Color { Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha) }
}

extension CalendarSource {
    package var color: Color { tint.color }
}

extension WritableCalendar {
    package var color: Color { tint.color }
}

extension DotStyle {
    package var color: Color { tint.color }
}

extension AgendaEventModel {
    /// The owning calendar's color.
    package var color: Color { tint.color }
}
