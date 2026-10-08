import SwiftUI

/// The Settings window's panes.
package enum SettingsDestination: String, CaseIterable, Identifiable {

    case general, calendars, tasks, menuBar, meetings, intelligence, shortcuts, about

    package var id: String { rawValue }

    package var title: String {
        switch self {
        case .general: return L10n.tr("settingsdestination.general", "General")
        case .calendars: return L10n.tr("settingsdestination.calendars", "Calendars")
        case .tasks: return L10n.tr("settingsdestination.tasks", "Tasks")
        case .menuBar: return L10n.tr("settingsdestination.menu.bar", "Menu Bar")
        case .meetings: return L10n.tr("settingsdestination.meetings", "Meetings")
        case .intelligence: return L10n.tr("settingsdestination.intelligence", "Intelligence")
        case .shortcuts: return L10n.tr("settingsdestination.shortcuts", "Shortcuts")
        case .about: return L10n.tr("settingsdestination.about", "About")
        }
    }

    package var symbolName: String {
        switch self {
        case .general: return "gearshape"
        case .calendars: return "calendar"
        case .tasks: return "checklist"
        case .menuBar: return "menubar.rectangle"
        case .meetings: return "video"
        case .intelligence: return "sparkles"
        case .shortcuts: return "keyboard"
        case .about: return "info.circle"
        }
    }

    /// System-Settings-style tile colors; darkened at the call site for
    /// the dark theme.
    package func iconColor(theme: ThemePalette) -> Color {
        switch self {
        case .general: return Color(nsColor: .systemGray)
        case .calendars: return theme.accentRed
        case .tasks: return Color(nsColor: .systemOrange)
        case .menuBar: return theme.controlAccent
        case .meetings: return Color(nsColor: .systemGreen)
        case .intelligence: return Color(nsColor: .systemTeal)
        case .shortcuts: return Color(nsColor: .systemIndigo)
        case .about: return Color(nsColor: .systemGray)
        }
    }
}
