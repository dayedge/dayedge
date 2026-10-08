import Foundation

/// Assistant prose as styled text: inline Markdown (bold, italic, code,
/// links) with line breaks kept; a `#` heading line becomes a bold line.
/// Block Markdown beyond that isn't rendered — prose is kept short, and
/// events and tasks are never Markdown (they're `ChatContentPart`s).
package enum ChatProse {
    package static func attributed(_ text: String) -> AttributedString {
        let markdown = text
            .components(separatedBy: "\n")
            .map(headingAsBold)
            .joined(separator: "\n")
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: markdown, options: options)) ?? AttributedString(text)
    }

    private static func headingAsBold(_ line: String) -> String {
        let trimmed = line.drop(while: \.isWhitespace)
        guard trimmed.hasPrefix("#") else { return line }
        let title = trimmed.drop { $0 == "#" }.trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: "*"))
        return title.isEmpty ? "" : "**\(title)**"
    }
}
