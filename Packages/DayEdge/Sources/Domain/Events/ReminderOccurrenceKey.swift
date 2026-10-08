import Foundation

/// A the app-only identity for one event occurrence. A recurring key always
/// includes an occurrence date, even when its source identifier names a
/// whole series. The original EventKit occurrence date survives a detached
/// occurrence being moved to a different start time.
package struct ReminderOccurrenceKey: Hashable, Sendable {
    package let storageKey: String

    // swiftlint:disable:next function_parameter_count - mirrors the EventKit identities a key is built from; labelled at every call
    package static func eventKit(
        calendarIdentifier: String,
        isRecurring: Bool,
        seriesIdentifier: String?,
        calendarItemIdentifier: String?,
        eventIdentifier: String?,
        startDate: Date,
        occurrenceDate: Date?
    ) -> Self? {
        guard !calendarIdentifier.isEmpty else { return nil }

        if isRecurring {
            let source: (kind: String, value: String)? =
                nonempty(seriesIdentifier).map { ("series", $0) }
                ?? nonempty(calendarItemIdentifier).map { ("item", $0) }
                ?? nonempty(eventIdentifier).map { ("event", $0) }
            guard let source else { return nil }
            let originalStart = occurrenceDate ?? startDate
            return Self(parts: [
                "v1", "recurring", calendarIdentifier, source.kind, source.value,
                timestamp(originalStart)
            ])
        }

        let source: (kind: String, value: String)? =
            nonempty(calendarItemIdentifier).map { ("item", $0) }
            ?? nonempty(eventIdentifier).map { ("event", $0) }
        guard let source else { return nil }
        return Self(parts: ["v1", "single", calendarIdentifier, source.kind, source.value])
    }

    private init(parts: [String]) {
        // Length prefixes avoid collisions if an EventKit identifier itself
        // contains punctuation used by the surrounding representation.
        storageKey = parts.map { "\($0.utf8.count):\($0)" }.joined()
    }

    private static func nonempty(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value
    }

    private static func timestamp(_ date: Date) -> String {
        String(Int64((date.timeIntervalSince1970 * 1_000).rounded()))
    }
}
