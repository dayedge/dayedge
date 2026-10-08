import Foundation
import Domain

/// Native resource lookup in this target's bundle. Keep interpolated values
/// verbatim; plural messages pass their numeric argument without converting it.
enum L10n {
    static func tr(_ key: StaticString, _ value: String.LocalizationValue,
                   bundle: Bundle = .module, locale: Locale = AppLocalization.displayLocale) -> String {
        let language = Bundle.preferredLocalizations(from: bundle.localizations,
                                                     forPreferences: [locale.identifier]).first
        let resources = language.flatMap { bundle.path(forResource: $0, ofType: "lproj") }.flatMap(Bundle.init(path:)) ?? bundle
        return String(localized: key, defaultValue: value, bundle: resources, locale: locale)
    }
}
