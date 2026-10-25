import Foundation
import Domain

extension SearchPaletteModel {
    // MARK: - #tag completion

    static var tagCompletionHints: [PaletteKeyHint] {
        [PaletteKeyHint(key: .tab, label: L10n.tr("palette.complete", "Complete"))]
    }

    /// As typed, at once (not after the typing pause): the `#tag` at the end of the query, if it names a list or a
    /// calendar. Only over the actions: not in the Search view, nor while Quick Add is open.
    func updateTagCompletion(for query: String, lists: [CalendarSource]) {
        let found = isResultsViewShown || isRefining ? nil
            : TagCompletion(query: query, lists: lists, calendars: writableCalendars)
        if found != tagCompletion { tagCompletion = found }
    }

    /// Tab or Return, or a click on `option`, while completing: the query with the tag written out. Nil when nothing is
    /// being completed, so the key does what it usually does.
    package func completeTag(with option: TagCompletion.Option? = nil) -> String? {
        guard let tagCompletion else { return nil }
        self.tagCompletion = nil
        return tagCompletion.completed(with: option)
    }

    /// Esc while completing: hides the options; typing on brings them back. Returns whether it did.
    @discardableResult
    package func dismissTagCompletion() -> Bool {
        guard tagCompletion != nil else { return false }
        tagCompletion = nil
        return true
    }
}
