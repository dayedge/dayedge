import SwiftUI
import Domain
import UI

extension EventQuickAddEditorView {
    // MARK: Values

    var dateText: String {
        let first = dateFormatter.format(edit.day, .short, year: .always)
        guard edit.isAllDay, edit.lastDay > edit.day else { return first }
        return first + " – " + dateFormatter.format(edit.lastDay, .short, year: .always)
    }

    /// "12:00" ("12pm"), or "01:00 +1" when it ends the next day.
    var endText: String {
        let text = timeFormat.time(edit.end)
        return calendar.isDate(edit.end, inSameDayAs: edit.start) ? text : text + " +1"
    }

    var calendarOptions: [(String?, String)] {
        [(nil, L10n.tr("eventquickaddeditorview.values.default", "Default"))] + calendars.map { (Optional($0.id), $0.title) }
    }

    var calendarTitle: String {
        calendars.first { $0.id == edit.calendarID }?.title ?? L10n.tr("eventquickaddeditorview.values.default", "Default")
    }

    var calendarColor: Color {
        calendars.first { $0.id == edit.calendarID }?.color ?? theme.secondaryText
    }

    var repeatOptions: [TaskRecurrence] {
        var options = TaskRecurrence.standard
        if edit.recurrence.isCustom { options.append(edit.recurrence) }
        return options
    }

    func accessibilityName(_ field: QuickAddField) -> String {
        switch field {
        case .calendar: return L10n.tr("eventquickaddeditorview.values.calendar", "Calendar")
        case .date: return L10n.tr("eventquickaddeditorview.values.date", "Date")
        case .time: return L10n.tr("eventquickaddeditorview.values.starts", "Starts")
        case .endTime: return L10n.tr("eventquickaddeditorview.values.ends", "Ends")
        case .recurrence: return L10n.tr("eventquickaddeditorview.values.repeat", "Repeat")
        default: return ""
        }
    }
}
