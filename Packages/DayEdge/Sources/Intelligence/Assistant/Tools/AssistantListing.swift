import Foundation

/// Counts every logical line while formatting only the returned prefix.
/// Formatting mints references, so omitted items never grow the registry.
package struct AssistantListing {
    private let limit: Int
    private var lines: [String] = []
    package private(set) var count = 0

    package init(maxLines: Int) { limit = max(0, maxLines) }

    package mutating func append(_ line: @autoclosure () -> String) {
        count += 1
        if lines.count < limit { lines.append(line()) }
    }

    package var text: String {
        let omitted = count - lines.count
        return (lines + (omitted > 0 ? ["…and \(omitted) more"] : [])).joined(separator: "\n")
    }
}

extension AssistantToolContext {
    package func listing(_ listing: AssistantListing) -> String {
        showsReferences ? listing.text + "\n" + AssistantFormat.referenceHint : listing.text
    }
}
