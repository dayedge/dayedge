import Foundation

/// Settings → General → Time format.
package enum TimeFormatPreference: String, CaseIterable, Identifiable {
    /// Whatever the Mac's region uses.
    case system
    case twentyFourHour
    case twelveHour

    package var id: String { rawValue }
}

/// How every time the user sees is written — the one formatter for the
/// agenda, the Day timeline, tasks, details, the menu bar and chat.
///
/// The setting picks the hour cycle; the locale writes it:
/// - 24-hour: the locale's own clock ("17:14", Finnish "17.14", Arabic
///   digits in Arabic), zero-padded; ranges "10:30 – 10:55".
/// - 12-hour where the locale writes it in plain Latin ("5:14 PM",
///   Spanish "5:14 p. m."): compact — "5:14pm", minutes always ("5:00pm");
///   a range in one half of the day names it once ("3:00–4:00pm"), across
///   noon twice ("11:30am–12:15pm").
/// - 12-hour elsewhere (Japanese, Chinese, Korean, Arabic…): the locale's
///   own form, its marker where it belongs ("午後5:14"), and its own
///   interval style for ranges.
///
/// Display only: data handed to the assistant's model stays 24-hour.
package struct TimeFormat: Hashable {
    package let uses12Hour: Bool
    package let locale: Locale

    package init(uses12Hour: Bool, locale: Locale = .autoupdatingCurrent) {
        self.uses12Hour = uses12Hour
        self.locale = locale
    }

    /// English: the forms the tests and the defaults spell out.
    package static let twentyFourHour = TimeFormat(uses12Hour: false, locale: Locale(identifier: "en_US"))
    package static let twelveHour = TimeFormat(uses12Hour: true, locale: Locale(identifier: "en_US"))

    /// The preference resolved; `.system` follows `locale`'s hour cycle.
    package static func resolve(_ preference: TimeFormatPreference, locale: Locale = .autoupdatingCurrent) -> TimeFormat {
        switch preference {
        case .twentyFourHour: return TimeFormat(uses12Hour: false, locale: locale)
        case .twelveHour: return TimeFormat(uses12Hour: true, locale: locale)
        case .system:
            let pattern = DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: locale) ?? "H"
            return TimeFormat(uses12Hour: pattern.contains("h") || pattern.contains("K"), locale: locale)
        }
    }

    /// The setting as stored, resolved — for code outside views (the menu
    /// bar, the meeting HUD); views read `\.timeFormat`.
    package static var current: TimeFormat { presentation(GeneralSettings.timeFormat()) }

    package static func presentation(_ preference: TimeFormatPreference,
                                     region: Locale = .autoupdatingCurrent,
                                     language: Locale = AppLocalization.displayLocale) -> TimeFormat {
        let regional = resolve(preference, locale: region)
        return TimeFormat(uses12Hour: regional.uses12Hour,
                          locale: AppLocalization.formattingLocale(display: language, region: region))
    }

    // MARK: - Times

    package func time(_ date: Date, calendar: Calendar = .autoupdatingCurrent) -> String {
        if usesCompactTwelveHour {
            let parts = calendar.dateComponents([.hour, .minute], from: date)
            return compact(hour: parts.hour ?? 0, minute: parts.minute ?? 0)
        }
        return Self.formatter(template: uses12Hour ? "hmma" : "HHmm", locale: locale, timeZone: calendar.timeZone)
            .string(from: date)
    }

    package func time(hour: Int, minute: Int) -> String {
        if usesCompactTwelveHour { return compact(hour: hour, minute: minute) }
        return time(Self.reference(hour: hour, minute: minute), calendar: Self.referenceCalendar)
    }

    /// A time of day from minutes since midnight (the now-lines).
    package func time(minutesSinceMidnight minutes: Int) -> String {
        time(hour: minutes / 60 % 24, minute: minutes % 60)
    }

    /// An hour on its own: the Day timeline's gutter, "Day starts at".
    package func hour(_ hour: Int) -> String {
        if usesCompactTwelveHour { return compact(hour: hour, minute: 0) }
        return Self.formatter(template: uses12Hour ? "ha" : "HHmm", locale: locale,
                              timeZone: Self.referenceCalendar.timeZone)
            .string(from: Self.reference(hour: hour, minute: 0))
    }

    // MARK: - Ranges

    package func range(_ start: Date, _ end: Date, calendar: Calendar = .autoupdatingCurrent) -> String {
        if usesCompactTwelveHour {
            let from = calendar.dateComponents([.hour, .minute], from: start)
            let to = calendar.dateComponents([.hour, .minute], from: end)
            return compactRange(fromHour: from.hour ?? 0, fromMinute: from.minute ?? 0,
                                toHour: to.hour ?? 0, toMinute: to.minute ?? 0)
        }
        if uses12Hour {
            // The locale's own interval: its marker once or twice, in place.
            let formatter = DateIntervalFormatter()
            formatter.locale = locale
            formatter.calendar = calendar
            formatter.timeZone = calendar.timeZone
            formatter.dateTemplate = "hmma"
            return formatter.string(from: start, to: end)
        }
        return "\(time(start, calendar: calendar)) – \(time(end, calendar: calendar))"
    }

    package func range(fromHour: Int, fromMinute: Int, toHour: Int, toMinute: Int) -> String {
        if usesCompactTwelveHour {
            return compactRange(fromHour: fromHour, fromMinute: fromMinute, toHour: toHour, toMinute: toMinute)
        }
        return range(Self.reference(hour: fromHour, minute: fromMinute), Self.reference(hour: toHour, minute: toMinute),
                     calendar: Self.referenceCalendar)
    }

    // MARK: - The compact 12-hour form

    /// Whether this locale writes 12-hour time in plain Latin — then it's
    /// written compactly; otherwise in the locale's own way.
    private var usesCompactTwelveHour: Bool {
        uses12Hour && Self.writesLatinTwelveHour(locale)
    }

    private func compact(hour: Int, minute: Int) -> String {
        twelveHourClock(hour: hour, minute: minute) + period(hour)
    }

    private func compactRange(fromHour: Int, fromMinute: Int, toHour: Int, toMinute: Int) -> String {
        let end = compact(hour: toHour, minute: toMinute)
        let sameHalf = (fromHour < 12) == (toHour < 12)
        let start = sameHalf ? twelveHourClock(hour: fromHour, minute: fromMinute) : compact(hour: fromHour, minute: fromMinute)
        return "\(start)–\(end)"
    }

    /// "5:00" / "5:14" — 12-hour digits, minutes always, no period.
    private func twelveHourClock(hour: Int, minute: Int) -> String {
        let twelve = hour % 12 == 0 ? 12 : hour % 12
        return String(format: "%d:%02d", twelve, minute)
    }

    /// "am" / "pm" — the locale's markers, compact: lowercased, without
    /// dots or spaces ("p. m." → "pm").
    private func period(_ hour: Int) -> String {
        let symbols = Self.periodSymbols(locale)
        let symbol = hour < 12 ? symbols.am : symbols.pm
        return symbol.lowercased().filter { $0.isLetter }
    }

    // MARK: - Shared formatters

    private static let lock = NSLock()
    nonisolated(unsafe) private static var formatters: [String: DateFormatter] = [:]
    nonisolated(unsafe) private static var latinLocales: [String: Bool] = [:]

    private static func formatter(template: String, locale: Locale, timeZone: TimeZone) -> DateFormatter {
        let key = "\(template)|\(locale.identifier)|\(timeZone.identifier)"
        lock.lock(); defer { lock.unlock() }
        if let cached = formatters[key] { return cached }
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.setLocalizedDateFormatFromTemplate(template)
        formatters[key] = formatter
        return formatter
    }

    /// The locale's 12-hour time is all ASCII ("5:14 PM", "5:14 p. m.").
    private static func writesLatinTwelveHour(_ locale: Locale) -> Bool {
        lock.lock()
        if let known = latinLocales[locale.identifier] { lock.unlock(); return known }
        lock.unlock()
        let sample = formatter(template: "hmma", locale: locale, timeZone: referenceCalendar.timeZone)
            .string(from: reference(hour: 17, minute: 14))
        let isLatin = sample.unicodeScalars.allSatisfy { $0.isASCII || $0.properties.isWhitespace }
        lock.lock(); latinLocales[locale.identifier] = isLatin; lock.unlock()
        return isLatin
    }

    private static func periodSymbols(_ locale: Locale) -> (am: String, pm: String) {
        let formatter = formatter(template: "hmma", locale: locale, timeZone: referenceCalendar.timeZone)
        return (formatter.amSymbol ?? "AM", formatter.pmSymbol ?? "PM")
    }

    /// A fixed day in UTC to write bare hours and minutes from.
    private static let referenceCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private static func reference(hour: Int, minute: Int) -> Date {
        referenceCalendar.date(from: DateComponents(year: 2001, month: 1, day: 1, hour: hour, minute: minute)) ?? Date()
    }
}

extension GeneralSettings {
    package static let timeFormatKey = "com.dayedge.general.timeFormat"

    package static func timeFormat(defaults: UserDefaults = .standard) -> TimeFormatPreference {
        defaults.string(forKey: timeFormatKey).flatMap(TimeFormatPreference.init(rawValue:)) ?? .system
    }
}
