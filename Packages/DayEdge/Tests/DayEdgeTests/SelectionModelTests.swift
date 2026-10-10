import SwiftUI
import XCTest
@testable import Shell
@testable import Domain
@testable import UI

final class SelectionModelTests: XCTestCase {
    // MARK: Source names

    func testTechnicalNamesNeverReachTheUI() {
        let uuid = "07AA7559-F0D4-4983-8EE0-BC9901EFAC39"
        XCTAssertEqual(SourceDisplayName.name(rawTitle: uuid, kind: .local), "On My Mac")
        XCTAssertEqual(SourceDisplayName.name(rawTitle: "  ", kind: .exchange), "Exchange")
        XCTAssertEqual(SourceDisplayName.name(rawTitle: nil, kind: .subscribed), "Subscribed")
        XCTAssertEqual(SourceDisplayName.name(rawTitle: "0123456789abcdef0123456789abcdef", kind: .other), "Other")
    }

    func testRealNamesAreKept() {
        XCTAssertEqual(SourceDisplayName.name(rawTitle: "iCloud", kind: .iCloud), "iCloud")
        XCTAssertEqual(SourceDisplayName.name(rawTitle: "Microsoft 365", kind: .exchange), "Microsoft 365")
        XCTAssertFalse(SourceDisplayName.isTechnical("Add Fee"))
    }

    // MARK: Grouping

    private let sources = [
        CalendarSource(id: "1", title: "Birthdays", tint: .gray, sourceTitle: "iCloud", sourceID: "icloud"),
        CalendarSource(id: "2", title: "Work", tint: .blue, sourceTitle: "iCloud", sourceID: "icloud"),
        CalendarSource(id: "3", title: "Birthdays", tint: .pink, sourceTitle: "Google", sourceID: "google"),
        CalendarSource(id: "4", title: "Holidays", tint: .purple, sourceTitle: "", sourceID: "")
    ]

    func testGroupsBySourceKeepDuplicateTitlesApart() {
        let groups = SelectionGroups.bySource(sources, kind: .calendar) { $0 != "2" }
        XCTAssertEqual(groups.map(\.title), ["Google", "iCloud", "Other"]) // sorted; missing name → Other
        let icloud = groups.first { $0.title == "iCloud" }
        XCTAssertEqual(icloud?.items.map(\.title), ["Birthdays", "Work"])
        XCTAssertEqual(icloud?.items.map(\.isSelected), [true, false])
        XCTAssertEqual(groups.first { $0.title == "Google" }?.items.map(\.title), ["Birthdays"]) // not merged
    }

    func testSmartGroupAndAccessibilityLabels() {
        let smart = SelectionGroups.smart { $0 == .attention }
        XCTAssertEqual(smart.title, "Smart")
        XCTAssertEqual(smart.items.map(\.id), ["smart.attention", "smart.completed"])
        XCTAssertEqual(smart.items[0].accessibilityLabel, "Attention, smart section, selected")
        XCTAssertEqual(smart.items[1].accessibilityLabel, "Completed, smart section, not selected")

        let list = SelectionGroups.bySource(sources, kind: .reminderList) { _ in false }.first!.items[0]
        XCTAssertTrue(list.accessibilityLabel.hasSuffix("task list, not selected"))
    }

    // MARK: Summary

    func testSummaryRules() {
        typealias S = SelectionSummary
        XCTAssertEqual(S.label(visibleTitles: ["A", "B", "C"], total: 3, kind: .lists), "All Lists")
        XCTAssertEqual(S.label(visibleTitles: [], total: 3, kind: .lists), "No Lists")
        XCTAssertEqual(S.label(visibleTitles: [], total: 0, kind: .lists), "No Lists")
        XCTAssertEqual(S.label(visibleTitles: ["Work"], total: 3, kind: .lists), "Work")
        XCTAssertEqual(S.label(visibleTitles: ["Work", "Home"], total: 3, kind: .lists), "Work + Home")
        XCTAssertEqual(S.label(visibleTitles: ["A very long calendar", "Another long one"], total: 3, kind: .calendars), "2 Calendars")
        XCTAssertEqual(S.label(visibleTitles: ["A", "B", "C"], total: 5, kind: .calendars), "3 Calendars")
    }
}
