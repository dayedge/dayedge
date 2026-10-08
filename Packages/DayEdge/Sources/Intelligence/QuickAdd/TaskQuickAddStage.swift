import Foundation

/// Decides whether search-field text means "create this task" and, if so,
/// returns the pre-filled draft.
///
/// Not part of `SearchIntentPipeline.live` yet. Next step: a
/// `SearchIntent.createTask(QuickAddDraft)` case, this stage placed *before*
/// the navigation stages (it declines pure dates — "next week" stays a
/// jump), and the search bar offering "Create task …" from the draft. A
/// future AI parser returns the same `QuickAddDraft`, so that UI is shared.
package struct TaskQuickAddStage: Sendable {
    package let name = "quickAddTask"
    package static let threshold = 0.6

    package let parser: QuickAddParser
    package let lists: @Sendable () -> [QuickAddList]
    /// Event calendars, for "#name".
    package let calendars: @Sendable () -> [QuickAddList]

    package init(parser: QuickAddParser = .init(), lists: @escaping @Sendable () -> [QuickAddList],
                 calendars: @escaping @Sendable () -> [QuickAddList] = { [] }) {
        self.parser = parser
        self.lists = lists
        self.calendars = calendars
    }

    package func resolve(_ text: String, referenceDate: Date, calendar: Calendar) async -> QuickAddDraft? {
        let draft = await parser.parse(text, lists: lists(), calendars: calendars(), referenceDate: referenceDate,
                                       calendar: calendar)
        return draft.confidence >= Self.threshold ? draft : nil
    }
}
