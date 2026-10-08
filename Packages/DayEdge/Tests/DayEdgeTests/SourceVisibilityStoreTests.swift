import SwiftUI
import XCTest
@testable import Shell
@testable import Domain

final class SourceVisibilityStoreTests: XCTestCase {
    private func defaults() -> UserDefaults {
        UserDefaults(suiteName: "SourceVisibilityStoreTests-\(UUID().uuidString)")!
    }

    private let sources = [
        CalendarSource(id: "a", title: "Work", tint: .blue, sourceTitle: "iCloud", sourceID: "icloud", sourceKind: .iCloud),
        CalendarSource(id: "b", title: "Home", tint: .red, sourceTitle: "iCloud", sourceID: "icloud", sourceKind: .iCloud),
        CalendarSource(id: "c", title: "Team", tint: .green, sourceTitle: "Google", sourceID: "google", sourceKind: .google)
    ]

    private func store(_ kind: SourceVisibilityStore.Kind = .calendars, _ d: UserDefaults? = nil) -> SourceVisibilityStore {
        let store = SourceVisibilityStore(kind: kind, defaults: d ?? defaults())
        store.update(sources)
        return store
    }

    func testNewSourcesStartVisibleAndSummaryIsAll() {
        let s = store()
        XCTAssertEqual(s.availableItems.count, 3)
        XCTAssertTrue(s.isEverythingVisible)
        XCTAssertEqual(s.summaryLabel, "All Calendars")
    }

    func testToggleKeepsThingsOpenSemanticsAndSummaries() {
        let s = store()
        s.toggle("a")
        XCTAssertFalse(s.isVisible("a"))
        XCTAssertFalse(s.isEverythingVisible)
        XCTAssertEqual(s.summaryLabel, "Home + Team")
        s.toggle("b")
        XCTAssertEqual(s.summaryLabel, "Team")
        s.toggle("c")
        XCTAssertEqual(s.summaryLabel, "No Calendars")
        s.showAll()
        XCTAssertEqual(s.summaryLabel, "All Calendars")
    }

    func testSoloShowsOnlyOneAmongTheGivenIDs() {
        let s = store()
        s.solo("b", among: ["a", "b", "c"])
        XCTAssertTrue(s.isVisible("b"))
        XCTAssertFalse(s.isVisible("a"))
        XCTAssertFalse(s.isVisible("c"))
        XCTAssertEqual(s.summaryLabel, "Home")
    }

    func testSoloLeavesIDsOutsideItsScopeAlone() {
        let s = SourceVisibilityStore(kind: .taskLists, defaults: defaults())
        s.update(sources)
        s.toggle(TaskSmartSection.completed.visibilityID) // a smart section hidden
        s.solo("a", among: ["a", "b", "c"]) // lists only
        XCTAssertTrue(s.hiddenIDs.contains(TaskSmartSection.completed.visibilityID))
        XCTAssertFalse(s.hiddenIDs.contains(TaskSmartSection.attention.visibilityID))
        XCTAssertFalse(s.isEverythingVisible) // a hidden smart section counts
    }

    func testExcludedIsIgnoredEverywhereAndNotOffered() {
        let s = store()
        s.setEnabled(false, id: "a")
        XCTAssertFalse(s.isVisible("a"))
        XCTAssertEqual(s.availableItems.map(\.id).sorted(), ["b", "c"])
        XCTAssertTrue(s.isEverythingVisible) // among what's available
        XCTAssertEqual(s.allItems.count, 3) // Settings still lists it
    }

    func testPersistsPerKindWithoutCollision() {
        let d = defaults()
        let calendars = store(.calendars, d)
        let lists = store(.taskLists, d)
        calendars.toggle("a")
        lists.setEnabled(false, id: "b")

        let reloadedCalendars = SourceVisibilityStore(kind: .calendars, defaults: d)
        let reloadedLists = SourceVisibilityStore(kind: .taskLists, defaults: d)
        XCTAssertEqual(reloadedCalendars.hiddenIDs, ["a"])
        XCTAssertTrue(reloadedCalendars.excludedIDs.isEmpty)
        XCTAssertEqual(reloadedLists.excludedIDs, ["b"])
        XCTAssertTrue(reloadedLists.hiddenIDs.isEmpty)
    }

    func testStaleIDsAreKeptWhenACatalogueShrinks() {
        let d = defaults()
        let s = store(.calendars, d)
        s.toggle("c")
        s.update(Array(sources.prefix(2))) // the Google account disappears for a while
        XCTAssertEqual(s.hiddenIDs, ["c"]) // its choice survives
        s.update(sources)
        XCTAssertFalse(s.isVisible("c"))
    }

    func testPostsAChangeNotificationForItsInstance() {
        let s = store()
        let expectation = expectation(forNotification: .sourceVisibilityDidChange, object: s)
        s.toggle("a")
        wait(for: [expectation], timeout: 1)
    }
}
