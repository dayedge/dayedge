import AppKit
import XCTest
@testable import Domain
@testable import Platform
@testable import UI
@testable import Agenda
@testable import Tasks
@testable import Intelligence
@testable import Shell

final class PolishLocalizationTests: XCTestCase {
    private let polish = Locale(identifier: "pl_PL")

    func testEveryModuleResolvesProductionPolishResources() {
        XCTAssertEqual(Domain.L10n.tr("date.today", "MISSING", locale: polish), "Dzisiaj")
        XCTAssertEqual(Platform.L10n.tr("calendareventmapper.unknown", "MISSING", locale: polish), "Nieznane")
        XCTAssertEqual(UI.L10n.tr("agendadayheaderview.today", "MISSING", locale: polish), "Dzisiaj")
        XCTAssertEqual(Agenda.L10n.tr("agendalistview.rows.loading", "MISSING", locale: polish), "Wczytywanie…")
        XCTAssertEqual(Tasks.L10n.tr("tasksortmenuview.sort.tasks", "MISSING", locale: polish), "Sortuj zadania")
        XCTAssertEqual(Intelligence.L10n.tr("chip.agenda.label", "MISSING", locale: polish), "Dzisiejsza agenda")
        XCTAssertEqual(Shell.L10n.tr("onboarding.hero", "MISSING", locale: polish), "Twój dzień,\nbliżej.")
    }

    func testProductionPluralFormsAtPolishBoundaries() {
        let expected = [0: "0 wyników", 1: "1 wynik", 2: "2 wyniki", 5: "5 wyników", 12: "12 wyników", 22: "22 wyniki"]
        for (count, text) in expected {
            XCTAssertEqual(Intelligence.L10n.tr("search.results.count", "\(count) results", locale: polish), text)
        }
        XCTAssertEqual(RecurrencePresentation.interval(.monthly, count: 2, locale: polish), "Co 2 miesiące")
        XCTAssertEqual(RecurrencePresentation.interval(.monthly, count: 12, locale: polish), "Co 12 miesięcy")
        XCTAssertEqual(Shell.L10n.tr("meeting.reminder.minutes", "In \(1) minutes", locale: polish), "Za 1 minutę")
        XCTAssertEqual(Shell.L10n.tr("meeting.reminder.minutes", "In \(22) minutes", locale: polish), "Za 22 minuty")
    }

    func testRecurrenceWeekdayCaseAndOrdinalGrammar() {
        XCTAssertEqual(RecurrencePresentation.weeklyWeekday(1, locale: polish), "Co niedzielę")
        XCTAssertEqual(RecurrencePresentation.weeklyWeekday(4, locale: polish), "Co środę")
        XCTAssertEqual(RecurrencePresentation.weeklyWeekday(7, locale: polish), "Co sobotę")
        let dates = DatePresentationFormatter(displayLocale: polish)
        XCTAssertEqual(RecurrencePresentation.summary(.init(frequency: .weekly, weekdays: [.init(weekday: 4)]), dates: dates), "Co środę")
        XCTAssertEqual(RecurrencePresentation.summary(.init(frequency: .monthly, interval: 2, daysOfMonth: [2]), dates: dates), "Co 2 miesiące, 2. dzień")
    }

    func testEventAlertOffsetsUsePolishPluralForms() {
        let dates = DatePresentationFormatter(displayLocale: polish)
        let units: [(Int, [String])] = [
            (1, ["minutę", "minuty", "minut", "minut", "minuty"]),
            (60, ["godzinę", "godziny", "godzin", "godzin", "godziny"]),
            (1440, ["dzień", "dni", "dni", "dni", "dni"]),
            (10080, ["tydzień", "tygodnie", "tygodni", "tygodni", "tygodnie"])
        ]
        for (multiplier, forms) in units {
            for (count, form) in zip([1, 2, 5, 12, 22], forms) {
                XCTAssertEqual(EventAlert.before(minutes: count * multiplier).title(isAllDay: false, dates: dates),
                               "\(count) \(form) przed")
                XCTAssertEqual(EventAlert.before(minutes: -count * multiplier).title(isAllDay: false, dates: dates),
                               "\(count) \(form) po")
            }
        }
        XCTAssertEqual(EventAlert.before(minutes: 2340).title(isAllDay: true, dates: dates), "2 dni przed (09:00)")
        XCTAssertEqual(EventAlert.before(minutes: 0).title(isAllDay: false, dates: dates), "W chwili wydarzenia")
    }

    func testSharedDayCountsAndCompactLabels() {
        for (count, event, task) in [(1, "wydarzenie", "zadanie"), (2, "wydarzenia", "zadania"),
                                     (5, "wydarzeń", "zadań"), (12, "wydarzeń", "zadań"), (22, "wydarzenia", "zadania")] {
            XCTAssertEqual(DayCountLabel.text(events: count, tasks: count, locale: polish),
                           "\(count) \(event) · \(count) \(task)")
            XCTAssertEqual(DayCountLabel.text(events: 0, tasks: count, locale: polish), "\(count) \(task)")
        }
        XCTAssertNil(DayCountLabel.text(events: 0, tasks: 0, locale: polish))
        XCTAssertEqual(Intelligence.L10n.tr("paletteaction.more", "MISSING", locale: polish), "Więcej")
        for (key, expected) in [("weather.sunrise", "wschód"), ("weather.sunset", "zachód")] {
            let text = Agenda.L10n.tr(key == "weather.sunrise" ? "weather.sunrise" : "weather.sunset", "MISSING", locale: polish)
            XCTAssertEqual(text, expected)
            XCTAssertLessThanOrEqual((text as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 11)]).width, 44)
        }
        let allDay = Agenda.L10n.tr("agenda.all.day", "MISSING", locale: polish)
        XCTAssertEqual(allDay, "całodn.")
        XCTAssertLessThanOrEqual((allDay as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 12, weight: .medium)]).width,
                                 AppTheme.Metrics.timelineLabelGutterWidth)
    }

    func testMachineWordingIsIndependentOfPolishDisplay() {
        XCTAssertEqual(EventEditError.notFound.message(locale: polish), "Nie można już znaleźć tego wydarzenia.")
        XCTAssertEqual(EventEditError.notFound.message(locale: Locale(identifier: "en")), "That event can't be found any more.")
        XCTAssertEqual(TaskPriority.high.assistantValue, "high")
        XCTAssertEqual(TaskChangeTools.priority(named: "high"), .high)
        XCTAssertNil(TaskChangeTools.priority(named: "wysoki"))
        XCTAssertEqual(TaskRecurrenceRule(frequency: .weekly, weekdays: [.init(weekday: 4)]).assistantSummary, "Every Wednesday")
    }
}
