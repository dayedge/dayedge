import SwiftUI
import Domain
import UI

extension EventQuickAddEditorView {
    // MARK: Values

    var calendarOptions: [(String?, String)] {
        [(nil, L10n.tr("eventquickaddeditorview.values.default", "Default"))] + calendars.map { (Optional($0.id), $0.title) }
    }

    var calendarTitle: String {
        calendars.first { $0.id == edit.calendarID }?.title ?? L10n.tr("eventquickaddeditorview.values.default", "Default")
    }

    var calendarColor: Color {
        calendars.first { $0.id == edit.calendarID }?.color ?? theme.secondaryText
    }

    /// None, Calendar's presets for a timed or an all-day event, and a parsed alert that is neither ("at 8:40").
    /// Several parsed alerts read "15 min before +1".
    var alertChoice: some View {
        let isAllDay = edit.timing.isAllDay
        let none = L10n.tr("eventquickaddeditorview.values.none", "None")
        let options = [(EventAlert?.none, none)] + EventAlert.choices(current: edit.firstAlert, isAllDay: isAllDay).map {
            (Optional($0), $0.title(isAllDay: isAllDay, format: timeFormat, dates: dateFormatter))
        }
        let value = edit.alerts.summary(isAllDay: isAllDay, format: timeFormat, dates: dateFormatter) ?? none
        return form.choice(.alert, value: value, options: options, selection: edit.firstAlert) { edit.firstAlert = $0 }
    }

    func accessibilityName(_ field: QuickAddField) -> String {
        switch field {
        case .calendar: return L10n.tr("eventquickaddeditorview.values.calendar", "Calendar")
        case .date: return L10n.tr("eventquickaddeditorview.values.start.date", "Start date")
        case .time: return L10n.tr("eventquickaddeditorview.values.start.time", "Start time")
        case .endDate: return L10n.tr("eventquickaddeditorview.values.end.date", "End date")
        case .endTime: return L10n.tr("eventquickaddeditorview.values.end.time", "End time")
        case .recurrence: return L10n.tr("eventquickaddeditorview.values.repeat", "Repeat")
        case .repeatEnd: return RepeatEndPopover.title
        case .alert: return L10n.tr("eventquickaddeditorview.values.alert", "Alert")
        default: return ""
        }
    }
}
