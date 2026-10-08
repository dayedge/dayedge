import XCTest
@testable import Domain
@testable import Platform
@testable import UI
@testable import Agenda
@testable import Tasks
@testable import Intelligence
@testable import Shell

final class LocalizationTests: XCTestCase {
    private func fixture(_ language: String) throws -> Bundle {
        let path = try XCTUnwrap(Bundle.module.path(forResource: language, ofType: "lproj", inDirectory: "Localization"))
        return try XCTUnwrap(Bundle(path: path))
    }

    func testEveryModuleResolvesItsOwnResourceInsteadOfFallback() {
        XCTAssertEqual(Domain.L10n.tr("date.today", "MISSING"), "Today")
        XCTAssertEqual(Platform.L10n.tr("calendareventmapper.unknown", "MISSING"), "Unknown")
        XCTAssertEqual(UI.L10n.tr("agendadayheaderview.today", "MISSING"), "Today")
        XCTAssertEqual(Agenda.L10n.tr("agendalistview.rows.loading", "MISSING"), "Loading…")
        XCTAssertEqual(Tasks.L10n.tr("tasksortmenuview.sort.tasks", "MISSING"), "Sort tasks")
        XCTAssertEqual(Intelligence.L10n.tr("chip.agenda.label", "MISSING"), "Today's agenda")
        XCTAssertEqual(Shell.L10n.tr("aboutsettingsview.acknowledgements", "MISSING"), "Acknowledgements…")
    }

    func testEnglishPluralCountsAndMultipleArguments() {
        for count in [1, 2, 5, 12, 22] {
            XCTAssertEqual(RecurrencePresentation.interval(.weekly, count: count), count == 1 ? "Every week" : "Every \(count) weeks")
            let rule = TaskRecurrenceRule(frequency: .monthly, interval: count, daysOfMonth: [2])
            XCTAssertEqual(rule.summary, count == 1 ? "Every month on the 2nd" : "Every \(count) months on the 2nd")
        }
        XCTAssertEqual(CustomSnoozeDuration.display(1), "1 minute")
        XCTAssertEqual(CustomSnoozeDuration.display(22), "22 minutes")
    }

    func testPolishPluralCategoriesUseIntegerArgument() throws {
        let bundle = try fixture("pl")
        let expected = [1: "Co tydzień", 2: "Co 2 tygodnie", 5: "Co 5 tygodni", 12: "Co 12 tygodni", 22: "Co 22 tygodnie"]
        for (count, text) in expected {
            XCTAssertEqual(RecurrencePresentation.interval(.weekly, count: count, locale: Locale(identifier: "pl"), bundle: bundle), text)
        }
    }

    func testInterpolationCanBeReorderedAndUserTextStaysVerbatim() throws {
        let userTitle = "chip.agenda.label %@ {name} مرحبا"
        XCTAssertEqual(Domain.L10n.tr("fixture.reordered", "\(userTitle) then \("Calendar")", bundle: try fixture("pl")),
                       "Calendar przed \u{2068}\(userTitle)\u{2069} — 100%")
        XCTAssertEqual(Domain.L10n.tr("fixture.missing", "Fallback \(userTitle)", bundle: try fixture("pl")), "Fallback \u{2068}\(userTitle)\u{2069}")
    }

    func testLanguageSelectionFallsBackToCompleteEnglish() {
        XCTAssertEqual(AppLocalization.preferredLocale(supported: ["en"], preferences: ["pl-PL", "ar"]).language.languageCode?.identifier, "en")
        XCTAssertEqual(AppLocalization.preferredLocale(supported: ["en", "pl"], preferences: ["pl-PL", "en"]).language.languageCode?.identifier, "pl")
        XCTAssertEqual(AppLocalization.formattingLocale(display: Locale(identifier: "pl"), region: Locale(identifier: "en_US")).region?.identifier, "US")
    }

    func testDateGrammarAndCustomPatternsAreSeparateFromParsing() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let date = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 7)))
        let polish = DatePresentationFormatter(regionalLocale: Locale(identifier: "pl_PL"), displayLocale: Locale(identifier: "pl"), calendar: calendar)
        XCTAssertTrue(polish.dayMonth(date, abbreviated: false).contains("października"))
        XCTAssertTrue(polish.month(date, abbreviated: false).contains("październik"))
        XCTAssertEqual(polish.format(date, .custom("yyyy-MM-dd")), "2026-10-07")
        let japanese = DatePresentationFormatter(regionalLocale: Locale(identifier: "ja_JP"), displayLocale: Locale(identifier: "ja"), calendar: calendar)
        XCTAssertTrue(japanese.dayMonth(date, abbreviated: false).contains("月"))
        XCTAssertEqual(TaskPriority.high.assistantValue, "high")
        XCTAssertEqual(TaskRecurrenceRule(frequency: .weekly, interval: 2).assistantSummary, "Every 2 weeks")
    }

    func testFixturesAreSeparateFromTheBundledPolishTranslation() throws {
        XCTAssertTrue(Domain.L10n.tr("fixture.expanded", "missing", bundle: try fixture("pl")).count > 70)
        XCTAssertTrue(Domain.L10n.tr("fixture.rtl", "missing", bundle: try fixture("ar")).contains("Calendar 10:30"))
        XCTAssertNotNil(DayEdgeStrings.bundle.path(forResource: "pl", ofType: "lproj"))
        XCTAssertEqual(DayEdgeStrings.bundle.localizedString(forKey: "fixture.expanded", value: nil, table: nil), "fixture.expanded")
        XCTAssertNil(ChatSuggestion.strings.path(forResource: "ar", ofType: "lproj"))
    }
}
