import SwiftUI
import Domain

extension VideoConferenceService {
    package func tintColor(theme: ThemePalette) -> Color {
        switch self {
        case .zoom: return theme.semanticActionTint(Color(red: 0.16, green: 0.55, blue: 1.0))
        case .teams: return theme.semanticActionTint(Color(red: 0.34, green: 0.31, blue: 0.65))
        case .googleMeet: return theme.semanticActionTint(Color(red: 0.0, green: 0.62, blue: 0.38))
        case .other: return theme.secondaryText
        }
    }
}
