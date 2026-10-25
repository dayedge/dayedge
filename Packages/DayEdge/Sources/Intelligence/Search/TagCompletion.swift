import Foundation
import Domain

/// A `#tag` being typed at the end of the query, and the lists and calendars it can name: `#tea` offers "Team Alpha".
/// Choosing one writes `#TeamAlpha ` in its place. Names match as the parser matches tags, ignoring case and spaces, so
/// the completed tag is the name without its spaces.
package struct TagCompletion: Equatable {
    package enum Kind: Equatable { case list, calendar }

    /// One tag, and what it names: a list and a calendar of the same name are one tag, which the parser reads as both.
    package struct Option: Equatable, Identifiable {
        /// The first list or calendar it names, for its name and color.
        package let source: CalendarSource
        package let kinds: [Kind]
        package var id: String { TagCompletion.key(source.title) }
        /// "#TeamAlpha" for "Team Alpha".
        package var tag: String { "#" + source.title.filter { !$0.isWhitespace } }
    }

    /// The most shown at once; more scroll, and typing narrows them.
    package static let visibleRows = 6
    /// What the parser trims from the ends of a word (time-whisper's `edgePunctuation`): a tag ending in one of these
    /// reads as another name, so it isn't offered.
    private static let edgePunctuation = Set(".,;:?()[]\"'")

    package let options: [Option]
    /// The highlighted option, which Tab or Return chooses.
    package private(set) var selected = 0
    /// The query before the tag being typed: what a completed tag follows.
    private let prefix: String

    /// A completion when the query ends in a `#tag` that names a list or calendar, by its start ("#tea") or anywhere in
    /// it ("#alpha"); nil otherwise, and once the tag is exactly the only name it can be.
    package init?(query: String, lists: [CalendarSource], calendars: [CalendarSource]) {
        guard let last = query.last, !last.isWhitespace,
              let tag = query.split(whereSeparator: \.isWhitespace).last, tag.first == "#" else { return nil }
        let typed = Self.key(tag.dropFirst())
        guard !typed.contains("#") else { return nil }
        var options: [Option] = []
        for (source, kind) in lists.map({ ($0, Kind.list) }) + calendars.map({ ($0, Kind.calendar) }) {
            let key = Self.key(source.title)
            guard typed.isEmpty || key.contains(typed),
                  let end = source.title.last, !Self.edgePunctuation.contains(end) else { continue }
            if let index = options.firstIndex(where: { $0.id == key }) {
                options[index] = Option(source: options[index].source, kinds: options[index].kinds + [kind])
            } else {
                options.append(Option(source: source, kinds: [kind]))
            }
        }
        // Names starting with it first, then those containing it.
        options = options.filter { $0.id.hasPrefix(typed) } + options.filter { !$0.id.hasPrefix(typed) }
        guard !options.isEmpty, !(options.count == 1 && options[0].id == typed) else { return nil }
        self.options = options
        self.prefix = String(query.dropLast(tag.count))
    }

    package var selectedOption: Option { options[selected] }

    /// ↑ / ↓, stopping at either end.
    package mutating func move(_ delta: Int) {
        selected = min(max(selected + delta, 0), options.count - 1)
    }

    /// The query with the typed tag replaced by `option`'s (the highlighted one by default), and a space to go on typing.
    package func completed(with option: Option? = nil) -> String {
        prefix + (option ?? selectedOption).tag + " "
    }

    fileprivate static func key(_ text: some StringProtocol) -> String {
        text.lowercased().filter { !$0.isWhitespace }
    }
}
