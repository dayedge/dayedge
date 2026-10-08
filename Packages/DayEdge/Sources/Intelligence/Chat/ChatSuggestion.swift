import Foundation
import Domain

/// What the app suggests asking before anything has been asked. A chip
/// shows the short label; tapping sends the fuller prompt. Localized
/// (`Localization/*.lproj/Localizable.strings`).
package enum ChatSuggestion: String, CaseIterable, Identifiable {
    case agenda, free, overdue, prep

    package var id: String { rawValue }

    package var symbol: String {
        switch self {
        case .agenda: return "calendar"
        case .free: return "clock"
        case .overdue: return "exclamationmark.circle"
        case .prep: return "note.text"
        }
    }

    package var label: String { Self.localized("chip.\(rawValue).label") }
    package var prompt: String { Self.localized("chip.\(rawValue).prompt") }

    /// The bundle holding the translations.
    package static var strings: Bundle { .module }

    private static func localized(_ key: String) -> String {
        NSLocalizedString(key, bundle: strings, comment: "")
    }
}
