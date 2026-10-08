import Foundation

/// Free-text matching for tasks (searched in memory — the reminders source
/// has no index): every word of the query must appear in the title or the
/// notes, ignoring case and accents ("spotk" finds "Spotkanie", "cafe"
/// finds "Café").
package enum TaskSearch {
    package static func words(in query: String) -> [String] {
        query.components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .map(fold)
    }

    package static func matches(_ task: TaskItem, words: [String]) -> Bool {
        guard !words.isEmpty else { return false }
        let haystack = fold([task.title, task.notes ?? ""].joined(separator: " "))
        return words.allSatisfy { haystack.contains($0) }
    }

    package static func matches(_ task: TaskItem, query: String) -> Bool {
        matches(task, words: words(in: query))
    }

    private static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }
}
