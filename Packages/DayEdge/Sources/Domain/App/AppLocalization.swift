import Foundation

/// Presentation language follows the bundled localizations and macOS's app
/// language selection. Region, calendar, and parsing remain independent.
package enum AppLocalization {
    package static var displayLocale: Locale {
        Locale(identifier: DayEdgeStrings.bundle.preferredLocalizations.first ?? "en")
    }

    package static func preferredLocale(supported: [String], preferences: [String]) -> Locale {
        Locale(identifier: Bundle.preferredLocalizations(from: supported, forPreferences: preferences).first ?? "en")
    }

    package static func formattingLocale(display: Locale, region: Locale) -> Locale {
        let language = display.language.languageCode?.identifier ?? "en"
        let script = display.language.script.map { "_\($0.identifier)" } ?? ""
        let country = region.region.map { "_\($0.identifier)" } ?? ""
        return Locale(identifier: language + script + country)
    }
}
