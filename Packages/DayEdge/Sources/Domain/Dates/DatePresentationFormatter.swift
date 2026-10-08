import Foundation

/// A built-in way of writing a date, or the user's own pattern.
package enum DateStyle: Hashable {
    /// "Wednesday 7 October 2026" / "Wednesday October 7 2026".
    case standard
    /// "Wednesday 7 Oct" / "Wednesday Oct 7" — the year only outside the
    /// current one ("Wednesday 7 Oct 2027").
    case compact
    /// "7 Oct" / "Oct 7" — no weekday; the year as for compact.
    case short
    /// An ICU pattern ("EEE d MMM", "yyyy-MM-dd") — see `validate(_:)`.
    case custom(String)
}

package enum WeekdayWidth: Hashable {
    case full, abbreviated
}

package enum YearPolicy: Hashable {
    case outsideCurrentYear, always
}

/// The one place dates the user sees are written — headers, details,
/// editors, tasks, search, chat. Times are `TimeFormat`'s.
///
/// App language controls names; regional settings control date ordering.
/// English retains the app's existing space-separated patterns. Other
/// languages use ICU templates, including grammatical month forms.
/// Display only: parsing and stored dates never come through here.
package struct DatePresentationFormatter: Hashable {
    /// Selected from the app resource bundle at launch.
    package static var displayLanguage: Locale { AppLocalization.displayLocale }

    package var regionalLocale: Locale = .autoupdatingCurrent
    package var displayLocale: Locale = Self.displayLanguage
    package var calendar: Calendar = .autoupdatingCurrent
    /// The user's patterns for the standard and compact styles; nil is
    /// System Default.
    package var customStandard: String?
    package var customCompact: String?

    /// The stored setting — for code outside views (the menu bar, the Dock
    /// icon); views read `\.dateFormatter`.
    package static var current: DatePresentationFormatter { stored(defaults: .standard) }

    package static func stored(defaults: UserDefaults) -> DatePresentationFormatter {
        DatePresentationFormatter(
            customStandard: GeneralSettings.dateFormat(GeneralSettings.dateFormatStandardKey, defaults: defaults),
            customCompact: GeneralSettings.dateFormat(GeneralSettings.dateFormatCompactKey, defaults: defaults)
        )
    }

    /// The same format on another calendar (its time zone, first weekday).
    package func with(_ calendar: Calendar) -> DatePresentationFormatter {
        var copy = self
        copy.calendar = calendar
        return copy
    }

    // MARK: - Dates

    package func format(_ date: Date, _ style: DateStyle, weekday: WeekdayWidth = .full,
                        year: YearPolicy = .outsideCurrentYear, relativeTo now: Date = .now) -> String {
        let pattern: String
        switch style {
        case .custom(let custom):
            pattern = custom
        case .standard:
            pattern = customStandard ?? builtInPattern(weekday: weekday, month: "MMMM", showsYear: true)
        case .compact:
            pattern = customCompact ?? builtInPattern(weekday: weekday, month: "MMM",
                                                      showsYear: showsYear(date, year, now))
        case .short:
            pattern = builtInPattern(weekday: nil, month: "MMM", showsYear: showsYear(date, year, now))
        }
        return formatter(pattern).string(from: date)
    }

    /// "Wednesday" / "Wed".
    package func weekday(_ date: Date, _ width: WeekdayWidth) -> String {
        formatter(width == .full ? "EEEE" : "EEE").string(from: date)
    }

    /// A weekday by its number (1 is Sunday, as `Calendar` counts):
    /// "Friday" / "Fri".
    package func weekdayName(_ number: Int, _ width: WeekdayWidth) -> String {
        let probe = formatter("EEE")
        let symbols = (width == .full ? probe.standaloneWeekdaySymbols : probe.shortStandaloneWeekdaySymbols) ?? []
        return symbols.indices.contains(number - 1) ? symbols[number - 1] : "?"
    }

    /// "October" / "Oct" — standalone, as in a title.
    package func month(_ date: Date, abbreviated: Bool) -> String {
        formatter(abbreviated ? "LLL" : "LLLL").string(from: date)
    }

    /// The day of the month, "7".
    package func day(_ date: Date) -> String {
        formatter("d").string(from: date)
    }

    /// "7 October" / "October 7" (or "Oct") — day and month in the region's
    /// order, no year: the Day view's title.
    package func dayMonth(_ date: Date, abbreviated: Bool) -> String {
        if !usesEnglishPatterns {
            return formatter(localizedPattern(abbreviated ? "dMMM" : "dMMMM")).string(from: date)
        }
        let fields = Self.order(regionalLocale).filter { $0 != .year }
        return formatter(fields.map { $0 == .day ? "d" : (abbreviated ? "MMM" : "MMMM") }.joined(separator: " "))
            .string(from: date)
    }

    /// "2026".
    package func year(_ date: Date) -> String {
        formatter("y").string(from: date)
    }

    /// "October 2026" — in the region's order of month and year.
    package func monthYear(_ date: Date) -> String {
        if !usesEnglishPatterns {
            return formatter(localizedPattern("yLLLL")).string(from: date)
        }
        let fields = Self.order(regionalLocale).filter { $0 != .day }
        return formatter(fields.map { $0 == .month ? "LLLL" : "y" }.joined(separator: " ")).string(from: date)
    }

    /// The weekdays' names, starting on the calendar's first weekday.
    package func weekdaySymbols(_ width: WeekdayWidth) -> [String] {
        let probe = formatter("EEE")
        let symbols = (width == .full ? probe.standaloneWeekdaySymbols : probe.shortStandaloneWeekdaySymbols) ?? []
        guard symbols.count == 7 else { return symbols }
        let first = calendar.firstWeekday - 1
        return Array(symbols[first...] + symbols[..<first])
    }

    /// "Today", "Tomorrow", "Yesterday" — nil for any other day. In the
    /// display language, like the names.
    package func relativeDay(_ date: Date, relativeTo now: Date = .now) -> String? {
        let offset = calendar.dateComponents([.day], from: calendar.startOfDay(for: now),
                                             to: calendar.startOfDay(for: date)).day ?? 0
        switch offset {
        case 0: return localized("date.today", "Today")
        case 1: return localized("date.tomorrow", "Tomorrow")
        case -1: return localized("date.yesterday", "Yesterday")
        default: return nil
        }
    }

    // MARK: - Custom patterns

    package enum PatternCheck: Equatable {
        case valid(preview: String)
        case invalid(reason: String)

        package var isValid: Bool { if case .valid = self { true } else { false } }
    }

    /// Whether `pattern` can be saved as a display pattern: quotes
    /// balanced, only ICU field letters outside them, at least one date
    /// field, and it writes something. It needn't name a whole date — a
    /// display pattern may leave out the year or the month.
    package static func validate(_ pattern: String, sample: Date = .now,
                                 using formatter: DatePresentationFormatter = .init()) -> PatternCheck {
        guard !pattern.trimmingCharacters(in: .whitespaces).isEmpty else { return .invalid(reason: L10n.tr("datepresentationformatter.enter.a.pattern", "Enter a pattern")) }
        guard let fields = fieldLetters(pattern) else { return .invalid(reason: L10n.tr("datepresentationformatter.unclosed.quote", "Unclosed quote")) }
        if fields.contains(where: { !fieldSymbols.contains($0) }) {
            return .invalid(reason: L10n.tr("datepresentationformatter.unknown.pattern.symbol", "Unknown pattern symbol"))
        }
        guard fields.contains(where: dateFieldSymbols.contains) else {
            return .invalid(reason: L10n.tr("datepresentationformatter.pattern.must.contain.a.date.field", "Pattern must contain a date field"))
        }
        let preview = formatter.format(sample, .custom(pattern))
        guard !preview.trimmingCharacters(in: .whitespaces).isEmpty else { return .invalid(reason: L10n.tr(
            "datepresentationformatter.pattern.writes.nothing", "Pattern writes nothing"
        )) }
        return .valid(preview: preview)
    }

    /// The field letters outside quotes, in order; nil when a quote is left
    /// open. `''` is a literal quote.
    private static func fieldLetters(_ pattern: String) -> [Character]? {
        var letters: [Character] = []
        var inQuote = false
        var characters = Array(pattern)[...]
        while let character = characters.popFirst() {
            if character == "'" {
                if characters.first == "'" { characters.removeFirst(); continue }
                inQuote.toggle()
            } else if !inQuote, character.isASCII, character.isLetter {
                letters.append(character)
            }
        }
        return inQuote ? nil : letters
    }

    /// Every ICU date and time field letter.
    private static let fieldSymbols = Set("GyYuUrQqMLlwWdDFgEecabBhHKkjJCmsSAzZOvVXx")
    /// The ones that say something about the date.
    private static let dateFieldSymbols = Set("GyYuUrQqMLlwWdDFgEec")

    // MARK: - The built-in patterns

    private enum Field: Hashable { case day, month, year }

    private func showsYear(_ date: Date, _ policy: YearPolicy, _ now: Date) -> Bool {
        policy == .always || calendar.component(.year, from: date) != calendar.component(.year, from: now)
    }

    /// The weekday, then day, month and year in the region's order —
    /// joined by single spaces.
    private func builtInPattern(weekday: WeekdayWidth?, month: String, showsYear: Bool) -> String {
        if !usesEnglishPatterns {
            let template = (weekday.map { $0 == .full ? "EEEE" : "EEE" } ?? "") + "d" + month + (showsYear ? "y" : "")
            return localizedPattern(template)
        }
        var parts: [String] = []
        if let weekday { parts.append(weekday == .full ? "EEEE" : "EEE") }
        for field in Self.order(regionalLocale) {
            switch field {
            case .day: parts.append("d")
            case .month: parts.append(month)
            case .year: if showsYear { parts.append("y") }
            }
        }
        return parts.joined(separator: " ")
    }

    private var usesEnglishPatterns: Bool { displayLocale.language.languageCode?.identifier == "en" }

    private func localizedPattern(_ template: String) -> String {
        DateFormatter.dateFormat(fromTemplate: template, options: 0,
                                 locale: AppLocalization.formattingLocale(display: displayLocale, region: regionalLocale)) ?? template
    }

    /// The order of day, month and year in the region's own long date —
    /// only the order: its words and punctuation are dropped.
    private static func order(_ locale: Locale) -> [Field] {
        lock.lock()
        if let known = orders[locale.identifier] { lock.unlock(); return known }
        lock.unlock()
        let pattern = DateFormatter.dateFormat(fromTemplate: "dMMMMy", options: 0, locale: locale) ?? "d MMMM y"
        var found: [Field] = []
        for letter in fieldLetters(pattern) ?? [] {
            let field: Field? = switch letter {
            case "d": .day
            case "M", "L": .month
            case "y", "Y", "u": .year
            default: nil
            }
            if let field, !found.contains(field) { found.append(field) }
        }
        let order = found.count == 3 ? found : [.day, .month, .year]
        lock.lock(); orders[locale.identifier] = order; lock.unlock()
        return order
    }

    // MARK: - Shared formatters

    private static let lock = NSLock()
    nonisolated(unsafe) private static var orders: [String: [Field]] = [:]
    nonisolated(unsafe) private static var formatters: [String: DateFormatter] = [:]

    private func formatter(_ pattern: String) -> DateFormatter {
        let key = "\(pattern)|\(displayLocale.identifier)|\(calendar.identifier)|\(calendar.timeZone.identifier)"
        Self.lock.lock(); defer { Self.lock.unlock() }
        if let cached = Self.formatters[key] { return cached }
        let formatter = DateFormatter()
        formatter.locale = displayLocale
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = pattern
        Self.formatters[key] = formatter
        return formatter
    }

    /// A word from the display language's strings — not the Mac's
    /// language, so names and words stay in one language.
    private func localized(_ key: String, _ fallback: String) -> String {
        let language = Bundle.preferredLocalizations(from: Bundle.module.localizations,
                                                     forPreferences: [displayLocale.identifier]).first ?? "en"
        guard let path = Bundle.module.path(forResource: language, ofType: "lproj"),
              let bundle = Bundle(path: path) else { return fallback }
        return bundle.localizedString(forKey: key, value: fallback, table: nil)
    }

    package init(
        regionalLocale: Locale = .autoupdatingCurrent,
        displayLocale: Locale = Self.displayLanguage,
        calendar: Calendar = .autoupdatingCurrent,
        customStandard: String? = nil,
        customCompact: String? = nil
    ) {
        self.regionalLocale = regionalLocale
        self.displayLocale = displayLocale
        self.calendar = calendar
        self.customStandard = customStandard
        self.customCompact = customCompact
    }
}

extension GeneralSettings {
    /// The user's date patterns (Settings → General → Date format, coming);
    /// empty or missing is System Default.
    package static let dateFormatStandardKey = "com.dayedge.general.dateFormat.standard"
    package static let dateFormatCompactKey = "com.dayedge.general.dateFormat.compact"

    package static func dateFormat(_ key: String, defaults: UserDefaults = .standard) -> String? {
        guard let pattern = defaults.string(forKey: key),
              DatePresentationFormatter.validate(pattern).isValid else { return nil }
        return pattern
    }
}
