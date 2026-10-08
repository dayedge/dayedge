import XCTest
@testable import Shell
@testable import Domain
@testable import Agenda
@testable import Tasks
@testable import Intelligence

@MainActor
final class PanelRouterTests: XCTestCase {
    private struct Panel {
        let router: PanelRouter
        let navigation: AgendaNavigationCoordinator
        let viewModel: CalendarViewModel
        let palette: SearchPaletteModel
        let chat: ChatCoordinator
    }

    private func makePanel() -> Panel {
        let today = Calendar.current.startOfDay(for: .now)
        let provider = MockCalendarDataProvider()
        let viewModel = CalendarViewModel(dataProvider: provider, visibleMonth: today, selectedDate: today)
        let navigation = AgendaNavigationCoordinator(
            viewModel: viewModel,
            agendaStore: AgendaSectionStore(dataProvider: provider, calendar: .autoupdatingCurrent),
            presentationCoordinator: PopoverPresentationCoordinator(),
            onWillChangeDate: {}
        )
        let defaults = UserDefaults(suiteName: "PanelRouterTests-\(UUID().uuidString)")!
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("router-\(UUID().uuidString).json")
        addTeardownBlock { try? FileManager.default.removeItem(at: file) }
        let chat = ChatCoordinator(settings: AssistantSettingsStore(fileURL: file), toolContext: AssistantTestData.context(),
                                   events: { _ in [] }, resolve: { _, _ in PlaceholderChatResponder(delay: .zero) })
        let palette = SearchPaletteModel()
        let router = PanelRouter(agendaNavigation: navigation,
                                 taskStore: TaskStore(provider: MockTaskDataProvider(), defaults: defaults),
                                 searchPalette: palette, chat: chat)
        return Panel(router: router, navigation: navigation, viewModel: viewModel, palette: palette, chat: chat)
    }

    func testGoingToADateShowsItsMonthAndClearsTheQuery() throws {
        let panel = makePanel()
        panel.router.selectViewMode(.tasks)
        panel.router.searchQuery = "march 3"
        let calendar = Calendar.autoupdatingCurrent
        let date = try XCTUnwrap(calendar.date(byAdding: .day, value: 40, to: .now))

        panel.router.handle(.jumpToDate(date))

        XCTAssertEqual(panel.navigation.displayedViewMode, .month)
        XCTAssertEqual(panel.viewModel.selectedDate, calendar.startOfDay(for: date))
        XCTAssertEqual(panel.router.searchQuery, "")
    }

    func testGoingToAMonthShowsMonthAndClearsTheQuery() throws {
        let panel = makePanel()
        panel.router.selectViewMode(.day)
        panel.router.searchQuery = "june"
        let date = try XCTUnwrap(Calendar.autoupdatingCurrent.date(byAdding: .month, value: 3, to: .now))

        panel.router.handle(.jumpToMonth(date))

        XCTAssertEqual(panel.navigation.displayedViewMode, .month)
        XCTAssertEqual(panel.router.searchQuery, "")
    }

    func testAskGetsItsConversationBeforeItShows() {
        let panel = makePanel()
        XCTAssertNil(panel.chat.current)
        panel.router.selectViewMode(.ask)
        XCTAssertNotNil(panel.chat.current)
        XCTAssertTrue(panel.router.isAskShown)
    }

    func testPickingAViewLeavesTheSearchViewAndItsQuery() {
        let panel = makePanel()
        panel.router.searchQuery = "standup"
        panel.router.selectViewMode(.day)
        XCTAssertEqual(panel.router.searchQuery, "standup", "the palette keeps its query")

        panel.palette.isResultsViewShown = true
        panel.router.selectViewMode(.tasks)
        XCTAssertEqual(panel.router.searchQuery, "")
    }

    func testAskingFromSearchStartsANewSeededChat() {
        let panel = makePanel()
        panel.router.selectViewMode(.ask)
        let previous = panel.chat.current
        panel.router.searchQuery = "what's tomorrow?"

        panel.router.ask("what's tomorrow?")

        XCTAssertFalse(panel.chat.current === previous)
        XCTAssertEqual(panel.chat.current?.title, "what's tomorrow?")
        XCTAssertEqual(panel.router.searchQuery, "")
        XCTAssertEqual(panel.navigation.displayedViewMode, .ask)
    }

    func testStatusMenuSearchLeavesAskAndFocusesTheField() async {
        let panel = makePanel()
        panel.router.selectViewMode(.ask)
        var focused = false
        await panel.router.perform(.search) { focused = true }
        XCTAssertTrue(focused)
        XCTAssertFalse(panel.router.isAskShown)
    }
}
