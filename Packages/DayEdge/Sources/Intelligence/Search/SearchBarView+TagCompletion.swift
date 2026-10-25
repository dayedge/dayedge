import SwiftUI
import Domain
import UI

extension SearchBarView {
    /// The lists and calendars a `#tag` being typed can name, in place of the actions: ↑ / ↓ choose, Tab, Return or a
    /// click completes the tag, Esc hides them. Past `TagCompletion.visibleRows` they scroll, following the selection.
    func tagCompletionList(_ completion: TagCompletion) -> some View {
        let shown = CGFloat(min(completion.options.count, TagCompletion.visibleRows))
        return ScrollViewReader { proxy in
            ThemedScrollView {
                VStack(spacing: Self.rowSpacing) {
                    ForEach(completion.options) { option in
                        tagOptionRow(option, isSelected: option == completion.selectedOption)
                    }
                }
            }
            .frame(height: shown * Self.rowHeight + (shown - 1) * Self.rowSpacing)
            .onChange(of: completion.selectedOption.id) { _, id in proxy.scrollTo(id) }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.13), value: completion.options.map(\.id))
    }

    /// Tab or Return while a `#tag` is being completed: writes it out (`option`, or the highlighted one). Returns
    /// whether it did, so the key otherwise does what it usually does.
    @discardableResult
    func completeTag(with option: TagCompletion.Option? = nil) -> Bool {
        guard let completed = palette.completeTag(with: option) else { return false }
        query = completed
        return true
    }

    private func tagOptionRow(_ option: TagCompletion.Option, isSelected: Bool) -> some View {
        let kinds = option.kinds.map {
            $0 == .list ? L10n.tr("tagcompletion.list", "List") : L10n.tr("tagcompletion.calendar", "Calendar")
        }.joined(separator: " · ")
        // The name as written, when the tag had to drop its spaces.
        let named = option.source.title.contains(where: \.isWhitespace) ? "\(option.source.title) · " : ""
        return paletteRow(isSelected: isSelected, title: option.tag, metadata: named + kinds) {
            Circle()
                .fill(option.source.color)
                .frame(width: 8, height: 8)
        }
        .onTapGesture { completeTag(with: option) }
        .accessibilityLabel("\(option.source.title), \(kinds)")
    }
}
