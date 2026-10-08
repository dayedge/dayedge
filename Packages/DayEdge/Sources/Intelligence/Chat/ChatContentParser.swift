import Foundation

/// Raw assistant text → content parts. Only explicit reference tokens
/// (`[[E1]]` event, `[[T2]]` task, `[[D3]]` day) become objects; prose is
/// never mined for titles, times or dates.
///
/// - A line that *starts* with a token (after an optional list bullet or
///   `**`) is made of references: every token on it becomes a part, in
///   order (so `[[D1]] [[D2]] [[D3]]` is three days). Whatever else the
///   model wrote there — its copy of the time and title — is dropped: the
///   objects' own values are shown.
/// - A token inside a sentence reads as the object's title.
/// - Unknown handles vanish; a raw id is never shown.
/// - While streaming, an unfinished token at the end is held back.
package enum ChatContentParser {
    package static func parse(_ text: String, lookup: (String) -> ChatObjectReference?) -> [ChatContentPart] {
        var parts: [ChatContentPart] = []
        var prose: [String] = []

        func flushProse() {
            let joined = prose.joined(separator: "\n").trimmingCharacters(in: .newlines)
            if !joined.trimmingCharacters(in: .whitespaces).isEmpty { parts.append(.text(joined)) }
            prose = []
        }

        for line in withoutPartialToken(text).components(separatedBy: "\n") {
            if leadingHandle(of: line) != nil {
                let references = line.matches(of: token).compactMap { lookup(String($0.1)) }
                if !references.isEmpty {
                    flushProse()
                    parts += references.map(\.part)
                }
            } else {
                prose.append(replacingInlineTokens(in: line, lookup: lookup))
            }
        }
        flushProse()
        return parts
    }

    // MARK: - Tokens

    private static let token = #/\[\[([ETD]\d+)\]\]/#

    /// The handle a line opens with, ignoring list bullets and emphasis.
    private static func leadingHandle(of line: String) -> String? {
        var rest = Substring(line).drop(while: \.isWhitespace)
        // "-", "*", "•", "1." / "1)"
        if let first = rest.first, "-*•".contains(first), rest.dropFirst().first == " " {
            rest = rest.dropFirst(2)
        } else if let marker = rest.firstIndex(where: { !$0.isNumber }), marker > rest.startIndex,
                  ".)".contains(rest[marker]) {
            rest = rest[rest.index(after: marker)...]
        }
        rest = rest.drop { $0.isWhitespace || $0 == "*" || $0 == "_" }
        guard let match = rest.prefixMatch(of: token) else { return nil }
        return String(match.1)
    }

    private static func replacingInlineTokens(in line: String, lookup: (String) -> ChatObjectReference?) -> String {
        line.replacing(token) { match in lookup(String(match.1))?.title ?? "" }
    }

    /// Cuts a token still being streamed ("…[[E", "…[") off the end.
    private static func withoutPartialToken(_ text: String) -> String {
        if let open = text.range(of: "[[", options: .backwards), !text[open.upperBound...].contains("]]") {
            return String(text[..<open.lowerBound])
        }
        return text.hasSuffix("[") ? String(text.dropLast()) : text
    }
}
