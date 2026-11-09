import XCTest
@testable import Domain

final class TaskNotesPreviewTests: XCTestCase {
    private func task(notes: String?) -> TaskItem {
        TaskItem(id: "t", title: "Task", notes: notes, listID: "work")
    }

    func testThePreviewIsTheFirstLineWithText() {
        XCTAssertEqual(task(notes: "\n  \nCheck the copy\nthen ship").notesPreview, "Check the copy")
    }

    func testThePreviewIsTrimmed() {
        XCTAssertEqual(task(notes: "  Call back  ").notesPreview, "Call back")
    }

    func testBlankNotesHaveNoPreview() {
        XCTAssertNil(task(notes: " \n\t\n").notesPreview)
    }

    func testNoNotesHaveNoPreview() {
        XCTAssertNil(task(notes: nil).notesPreview)
    }
}

final class TaskPriorityMarkTests: XCTestCase {
    func testEachPriorityHasRemindersMark() {
        XCTAssertEqual(TaskPriority.low.mark, "!")
        XCTAssertEqual(TaskPriority.medium.mark, "!!")
        XCTAssertEqual(TaskPriority.high.mark, "!!!")
    }

    func testNoPriorityHasNoMark() {
        XCTAssertNil(TaskPriority.none.mark)
    }
}
