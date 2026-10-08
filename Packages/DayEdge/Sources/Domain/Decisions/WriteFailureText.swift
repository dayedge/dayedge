import Foundation

/// What a failed calendar or Reminders write says to the user.
package enum WriteFailureText {
    package static func message(_ error: Error, locale: Locale = AppLocalization.displayLocale) -> String {
        switch error {
        case let error as EventEditError: return error.message(locale: locale)
        case let error as TaskSourceError: return error.message(locale: locale) ?? error.title(locale: locale)
        default: return error.localizedDescription
        }
    }
}
