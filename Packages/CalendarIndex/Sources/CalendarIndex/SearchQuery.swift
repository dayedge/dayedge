import Foundation

/// Turns what the user typed into a safe FTS5 expression: Unicode word
/// tokens, each a quoted literal with a prefix match, all required (AND).
/// Raw FTS syntax (`NEAR`, `OR`, `col:`, `^`, quotes) is never passed to
/// `MATCH` — it's split into plain words like any other punctuation.
public enum SearchQuery {
    static let maxTokens = 12

    /// Every term of a request: free words anywhere, then each field's
    /// words scoped to its column. Nil when there's nothing to match.
    public static func ftsExpression(for request: SearchRequest) -> String? {
        let parts = [
            ftsExpression(for: request.text).map { "(\($0))" },
            request.titleText.flatMap(ftsExpression(for:)).map { "title : (\($0))" },
            request.organizer.flatMap(ftsExpression(for:)).map { "organizer_text : (\($0))" },
            request.attendee.flatMap(ftsExpression(for:)).map { "attendees_text : (\($0))" }
        ].compactMap { $0 }
        // FTS5 needs an explicit AND before a column filter.
        return parts.isEmpty ? nil : parts.joined(separator: " AND ")
    }

    /// Nil when the input has no searchable word.
    public static func ftsExpression(for input: String) -> String? {
        let tokens = input
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .prefix(maxTokens)
        guard !tokens.isEmpty else { return nil }
        return tokens
            .map { "\"\($0.replacingOccurrences(of: "\"", with: "\"\""))\"*" }
            .joined(separator: " ")
    }

    /// Lowercased, diacritics removed — as the search index compares.
    public static func folded(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }
}
