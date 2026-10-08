import AppKit
import Foundation

package struct TemporalCorrection: Equatable {
    package enum Reason: Equatable {
        case alias
        case spelling
        case canonicalization
    }

    package let original: String
    package let replacement: String
    package let reason: Reason
}

package struct NormalizedTemporalQuery: Equatable {
    package let original: String
    package let normalized: String
    package let corrections: [TemporalCorrection]
}

/// Vocabulary cleanup only. It never decides whether a query is a date.
package struct TemporalQueryNormalizer: Sendable {
    package typealias Suggestions = @Sendable (String) -> [String]

    private let suggestions: Suggestions

    package init(suggestions: @escaping Suggestions = { Self.systemSuggestions($0) }) {
        self.suggestions = suggestions
    }

    package func normalize(_ query: String) -> NormalizedTemporalQuery {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: Self.edgePunctuation)
            .lowercased(with: TemporalLanguage.matchingLocale)
        let words = trimmed.split(whereSeparator: \.isWhitespace).map(String.init)
        var tokens: [String] = []
        var corrections: [TemporalCorrection] = []

        for word in words {
            let expansion = Self.aliases[word]
            if let expansion {
                corrections.append(.init(
                    original: word,
                    replacement: expansion.map(\.rawValue).joined(separator: " "),
                    reason: .alias
                ))
            }
            for expanded in expansion?.map(\.rawValue) ?? [word] {
                var token = expanded
                if token.count >= 4, TemporalWord(rawValue: token) == nil,
                   token.unicodeScalars.allSatisfy({ CharacterSet.letters.contains($0) }) {
                    let matches = Set(suggestions(token).compactMap {
                        TemporalWord(rawValue: $0.lowercased(with: TemporalLanguage.matchingLocale))
                    }.filter { TemporalWord.spellable.contains($0) })
                    if matches.count == 1, let replacement = matches.first {
                        corrections.append(.init(original: token, replacement: replacement.rawValue, reason: .spelling))
                        token = replacement.rawValue
                    }
                }

                if let word = TemporalWord(rawValue: token), let canonical = Self.canonicalWords[word] {
                    corrections.append(.init(original: token, replacement: canonical.rawValue, reason: .canonicalization))
                    token = canonical.rawValue
                }
                tokens.append(token)
            }
        }

        // Only these complete boundary fragments are rewritten. The parser
        // still has to recognize the *entire* resulting query afterward.
        let phraseStart = tokens.first == TemporalWord.the.rawValue ? 1 : 0
        if tokens.count >= phraseStart + 3,
           tokens[phraseStart + 1] == TemporalWord.day.rawValue,
           tokens[phraseStart + 2] == TemporalWord.of.rawValue,
           let firstWord = TemporalWord(rawValue: tokens[phraseStart]),
           let replacement = Self.boundaryPhrases[firstWord] {
            let original = tokens[phraseStart] + " " + TemporalWord.day.rawValue
            tokens.replaceSubrange(phraseStart...phraseStart + 1, with: [replacement.rawValue])
            corrections.append(.init(original: original, replacement: replacement.rawValue, reason: .canonicalization))
        }

        return .init(original: query, normalized: tokens.joined(separator: " "), corrections: corrections)
    }

    private static func systemSuggestions(_ word: String) -> [String] {
        NSSpellChecker.shared.guesses(
            forWordRange: NSRange(location: 0, length: (word as NSString).length),
            in: word, language: TemporalLanguage.spellingCode, inSpellDocumentWithTag: 0
        ) ?? []
    }

    private static let edgePunctuation = CharacterSet(charactersIn: ".,!?;:")

    private static let aliases: [String: [TemporalWord]] = [
        "prev": [.previous], "nxt": [.next], "cur": [.current],
        "wk": [.week], "wks": [.weeks],
        "mo": [.month], "mos": [.months], "mth": [.month], "mths": [.months],
        "yr": [.year], "yrs": [.years], "yer": [.year],
        "beg": [.beginning],
        "mon": [.monday], "tue": [.tuesday], "tues": [.tuesday],
        "wed": [.wednesday], "thu": [.thursday], "thur": [.thursday],
        "thurs": [.thursday], "fri": [.friday], "sat": [.saturday], "sun": [.sunday],
        "bom": [.beginning, .of, .month], "eom": [.end, .of, .month],
        "boy": [.beginning, .of, .year], "eoy": [.end, .of, .year]
    ]

    private static let canonicalWords: [TemporalWord: TemporalWord] = [
        .current: .this, .beginning: .start, .ending: .end
    ]

    private static let boundaryPhrases: [TemporalWord: TemporalWord] = [
        .first: .start, .last: .end
    ]
}
