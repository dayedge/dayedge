import Foundation

/// Why a read or write against the task source failed, in words a toast can
/// show. Providers translate their own errors into these.
package enum TaskSourceError: Error, Equatable, Sendable {
    case notFound
    case readOnlyList
    case accessDenied
    case unsupported
    case saveFailed(String)

    package var title: String { title(locale: AppLocalization.displayLocale) }

    package func title(locale: Locale) -> String {
        switch self {
        case .notFound: return L10n.tr("tasksourceerror.reminder.not.found", "Reminder not found", locale: locale)
        case .readOnlyList: return L10n.tr("tasksourceerror.this.list.is.read.only", "This list is read-only", locale: locale)
        case .accessDenied: return L10n.tr("tasksourceerror.no.access.to.reminders", "No access to Reminders", locale: locale)
        case .unsupported: return L10n.tr("tasksourceerror.not.supported.yet", "Not supported yet", locale: locale)
        case .saveFailed: return L10n.tr("tasksourceerror.couldn.t.update.reminder", "Couldn't update reminder", locale: locale)
        }
    }

    package var message: String? { message(locale: AppLocalization.displayLocale) }

    package func message(locale: Locale) -> String? {
        switch self {
        case .notFound: return L10n.tr("tasksourceerror.it.may.have.been.deleted.in.reminders", "It may have been deleted in Reminders.", locale: locale)
        case .readOnlyList: return L10n.tr("tasksourceerror.changes.to.reminders.in.this.list.can.t.be.saved", "Changes to reminders in this list can't be saved.", locale: locale)
        case .accessDenied: return L10n.tr(
            "tasksourceerror.allow.access.in.system.settings.0f2f4e",
            "Allow access in System Settings › Privacy & Security › Reminders.",
            locale: locale
        )
        case .unsupported: return nil
        case .saveFailed(let detail): return detail.isEmpty ? nil : detail
        }
    }
}
