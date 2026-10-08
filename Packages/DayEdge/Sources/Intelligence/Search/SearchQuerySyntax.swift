import Foundation

/// The search field's few `key:value` operators. Plain words stay plain
/// search; a known key adds a constraint. Adding an operator = a case here
/// and its meaning in `SearchQueryResolver`.
package enum SearchOperator: String, CaseIterable, Sendable {
    /// Words in the title only.
    case subject
    /// Who organized (events; tasks have no creator in EventKit).
    case from
    /// Who took part (events).
    case with
    /// `event` or `task`.
    case type
    /// That day (or month).
    case day
    /// Before the start of that day.
    case before
    /// From the start of that day on.
    case after
    /// `A..B`, both days included.
    case between

    package enum ValueKind: Sendable {
        case text, person, kind, date, range
    }

    package var valueKind: ValueKind {
        switch self {
        case .subject: .text
        case .from, .with: .person
        case .type: .kind
        case .day, .before, .after: .date
        case .between: .range
        }
    }

    package var key: String { rawValue + ":" }
}

/// A query split into free words and operator values. Pure text work — no
/// dates are resolved here.
package struct ParsedSearchQuery: Equatable, Sendable {
    /// What's left for ordinary search, words in their order.
    package var freeText = ""
    /// Applied operators (a repeated one: the last wins). An operator with
    /// no value yet ("from:") isn't here — it applies nothing.
    package var values: [SearchOperator: String] = [:]
    /// The last token while it's still being typed (no space after it):
    /// what suggestions complete.
    package var editing: Editing?

    package struct Editing: Equatable, Sendable {
        /// The operator whose value is being typed, nil for a plain word.
        package var op: SearchOperator?
        /// The value (or word) typed so far, quotes removed.
        package var partial: String
        /// Where the token starts in the query (characters).
        package var tokenStart: Int
    }

    package var hasOperators: Bool { !values.isEmpty }
}

package enum SearchQuerySyntax {
    package static func parse(_ query: String) -> ParsedSearchQuery {
        var parsed = ParsedSearchQuery()
        var words: [String] = []
        let tokens = tokenize(query)
        let endsInSpace = query.last.map(\.isWhitespace) ?? true
        for (index, token) in tokens.enumerated() {
            let isLast = index == tokens.count - 1 && !endsInSpace
            if let (op, value) = operatorValue(token.text) {
                if !value.isEmpty { parsed.values[op] = value }
                if isLast { parsed.editing = .init(op: op, partial: value, tokenStart: token.start) }
            } else {
                words.append(token.text)
                if isLast { parsed.editing = .init(op: nil, partial: token.text, tokenStart: token.start) }
            }
        }
        parsed.freeText = words.joined(separator: " ")
        return parsed
    }

    /// `query` with the token at `tokenStart` replaced by `replacement`.
    package static func replacingToken(in query: String, from tokenStart: Int, with replacement: String) -> String {
        String(query.prefix(tokenStart)) + replacement
    }

    /// A value as it must be typed: quoted when it has a space.
    package static func quoted(_ value: String) -> String {
        value.contains(where: \.isWhitespace) ? "\"\(value)\"" : value
    }

    // MARK: - Tokens

    package struct Token: Equatable {
        package var text: String
        package var start: Int
    }

    /// Whitespace-separated, a quoted part (`from:"Jon Nest"`) kept whole.
    package static func tokenize(_ query: String) -> [Token] {
        var tokens: [Token] = []
        var current = ""
        var start = 0
        var isQuoted = false
        for (offset, character) in query.enumerated() {
            if character == "\"" { isQuoted.toggle() }
            if character.isWhitespace && !isQuoted {
                if !current.isEmpty { tokens.append(Token(text: current, start: start)) }
                current = ""
                continue
            }
            if current.isEmpty { start = offset }
            current.append(character)
        }
        if !current.isEmpty { tokens.append(Token(text: current, start: start)) }
        return tokens
    }

    /// `key:value` for a known key (any case); nil for anything else —
    /// unknown keys ("owner:anna") stay plain words.
    private static func operatorValue(_ token: String) -> (SearchOperator, String)? {
        guard let colon = token.firstIndex(of: ":") else { return nil }
        let name = token[..<colon].lowercased()
        // "t:" is short for "type:" (as in quick add's "t:e" / "t:t").
        guard let op = name == "t" ? .type : SearchOperator(rawValue: name) else { return nil }
        let value = token[token.index(after: colon)...].trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        return (op, value)
    }
}
