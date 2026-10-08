import Foundation
import Domain

/// The word tables Quick Add recognizes. Plain data: extending v1 means
/// adding entries here, not writing new parsing code.
package enum QuickAddVocabulary {
    package static let edgePunctuation = CharacterSet(charactersIn: ".,;:?()\"'")

    // MARK: Explicit syntax

    package static let listPrefix: Character = "#"
    package static let forcePrefix = "+"

    /// Reminders' own convention: ! low, !! medium, !!! high.
    package static let bangPriority: [Int: TaskPriority] = [1: .low, 2: .medium, 3: .high]

    package static let priorityPhrases: [[String]: TaskPriority] = [
        ["high", "priority"]: .high, ["important"]: .high, ["urgent"]: .high,
        ["medium", "priority"]: .medium,
        ["low", "priority"]: .low
    ]

    // MARK: Recurrence

    package static let recurrenceWords: [String: TaskRecurrenceRule.Frequency] = [
        "daily": .daily, "weekly": .weekly, "monthly": .monthly, "yearly": .yearly, "annually": .yearly
    ]
    package static let every = "every"
    package static let other = "other"
    /// "every second Friday" = every 2 weeks.
    package static let everyNth: [String: Int] = ["other": 2, "second": 2, "third": 3, "fourth": 4]
    package static let weekdayWords: Set<String> = ["weekday", "weekdays"]

    package static let frequencyUnits: [String: TaskRecurrenceRule.Frequency] = [
        "day": .daily, "days": .daily, "week": .weekly, "weeks": .weekly,
        "month": .monthly, "months": .monthly, "year": .yearly, "years": .yearly
    ]

    /// "on the 1st" after a monthly repeat.
    package static let onThe: [String] = ["on", "the"]

    package static let ordinalWords: [String: Int] = [
        "first": 1, "second": 2, "third": 3, "fourth": 4, "fifth": 5, "last": -1
    ]
    package static let ordinalSuffixes = ["st", "nd", "rd", "th"]

    package static let numberWords: [String: Int] = [
        "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6,
        "seven": 7, "eight": 8, "nine": 9, "ten": 10, "eleven": 11, "twelve": 12, "a": 1, "an": 1
    ]

    // MARK: Alerts

    package static let alertVerbs: Set<String> = ["remind", "alert", "notify"]
    package static let alertFiller: Set<String> = ["me"]
    package static let atDueTime: [String] = ["at", "due", "time"]
    package static let before = "before"

    /// Minutes per unit.
    package static let durationUnits: [String: Int] = [
        "m": 1, "min": 1, "mins": 1, "minute": 1, "minutes": 1,
        "h": 60, "hr": 60, "hrs": 60, "hour": 60, "hours": 60,
        "d": 1440, "day": 1440, "days": 1440
    ]

    // MARK: Title

    /// Glue words that belong to a removed date ("… at 10 am", "on Friday"),
    /// dropped when they touch a removed piece.
    package static let connectors: Set<String> = ["at", "on", "by", "in", "for", "due", "from", "to", "until", "-", "–", "—", "@",
                                          "starting", "beginning", "starts", "begins"]

    /// Words that make a leftover read like something to do.
    /// A first word that says "this is a to-do".
    package static let todoWords: Set<String> = ["todo", "to-do", "task"]

    package static let taskVerbs: Set<String> = [
        "buy", "call", "send", "pay", "book", "submit", "renew", "email", "write", "review",
        "check", "fix", "finish", "prepare", "order", "pick", "return", "cancel", "schedule",
        "water", "clean", "read", "plan", "update", "file", "reply", "ask", "remind", "text"
    ]
}

extension QuickAddVocabulary {
    /// "15m", "15", "fifteen"… → (number, attached unit suffix).
    package static func number(_ key: String) -> (value: Int, suffix: String)? {
        if let word = numberWords[key] { return (word, "") }
        let digits = key.prefix { $0.isNumber }
        guard !digits.isEmpty, let value = Int(digits) else { return nil }
        return (value, String(key.dropFirst(digits.count)))
    }

    /// "1st", "15th", "first", "last" → day of month (-1 = last).
    package static func ordinal(_ key: String) -> Int? {
        if let word = ordinalWords[key] { return word }
        guard let (value, suffix) = number(key), (1...31).contains(value),
              suffix.isEmpty || ordinalSuffixes.contains(suffix) else { return nil }
        return value
    }

    /// `Calendar` weekday number for a weekday word, incl. short forms.
    package static func weekday(_ key: String) -> Int? {
        if let word = TemporalWord(rawValue: key), let number = word.calendarWeekday { return number }
        let short = ["sun": 1, "mon": 2, "tue": 3, "tues": 3, "wed": 4, "thu": 5, "thur": 5, "thurs": 5, "fri": 6, "sat": 7]
        let singular = key.hasSuffix("s") ? String(key.dropLast()) : key
        if singular != key, let word = TemporalWord(rawValue: singular), let number = word.calendarWeekday { return number }
        return short[key]
    }
}

extension QuickAddVocabulary {
    private static let months: [String: Int] = [
        "jan": 1, "january": 1, "feb": 2, "february": 2, "mar": 3, "march": 3, "apr": 4, "april": 4,
        "may": 5, "jun": 6, "june": 6, "jul": 7, "july": 7, "aug": 8, "august": 8,
        "sep": 9, "sept": 9, "september": 9, "oct": 10, "october": 10, "nov": 11, "november": 11,
        "dec": 12, "december": 12
    ]

    /// Month number for a month name or short form — only where a day
    /// number sits next to it ("3 oct"), so "may" in a title stays a word.
    package static func month(_ key: String) -> Int? { months[key] }
}
