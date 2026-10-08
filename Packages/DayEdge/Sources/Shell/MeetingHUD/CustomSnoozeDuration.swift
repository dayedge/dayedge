import Foundation

/// Custom meeting reminders are deliberately just whole minutes.
enum CustomSnoozeDuration {
    static let range = 1...120

    static func display(_ minutes: Int) -> String {
        L10n.tr("snooze.minutes", "\(minutes) minutes")
    }

    static func parse(_ input: String) -> Int? {
        let digits = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !digits.isEmpty, digits.allSatisfy(\.isNumber),
              let minutes = Int(digits), range.contains(minutes) else { return nil }
        return minutes
    }
}
