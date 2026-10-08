import Foundation

/// The app's own reading of times and time spans — the cases chrono
/// misses or reads differently:
/// - ranges with any range word: "13-14", "1pm–2:30pm", "noon-1pm",
///   "from 9 till 11", "between 1 and 2pm", "9:30->9:45", "1pm~2pm";
/// - a start and a duration: "1pm for 1h", "13:00 90 min", "at 2 for 2 hours";
/// - "at 3" without am/pm: 1–7 o'clock means the afternoon (15:00); an
///   end earlier than its start is afternoon too ("11-1" → 11:00–13:00);
/// - "half past 2", "quarter past 3", "quarter to 4";
/// - parts of the day — "morning" (09:00), "afternoon" (13:00), "evening"
///   (18:00), "tonight" (20:00) — approximate: any stated time wins.
/// Times only; days are the other extractors' business.
package struct TimeSpanExtractor: QuickAddExtractor {
    package static let rangeWords: Set<String> = ["-", "–", "—", "->", "~", "to", "until", "till", "til", "untill", "thru", "through"]
    package static let partsOfDay: [String: Int] = ["morning": 9, "afternoon": 13, "evening": 18, "tonight": 20]
    /// Before a bare range these count things, not hours ("read pages 3-5 tomorrow").
    package static let countedNouns: Set<String> = [
        "page", "pages", "p", "pp", "chapter", "chapters", "ch", "section", "sections", "exercise", "exercises",
        "question", "questions", "slide", "slides", "lesson", "lessons", "episode", "episodes", "item", "items",
        "step", "steps", "verse", "verses", "row", "rows", "level", "levels", "set", "sets", "reps", "rounds"
    ]

    package func extract(_ context: QuickAddContext) async -> [ParsedSpan] {
        let keys = context.tokens.map(\.key)
        var spans: [ParsedSpan] = []
        var index = 0
        while index < keys.count {
            if let (length, fact) = Self.match(keys, at: index) {
                spans.append(ParsedSpan(range: context.range(index, index + length - 1), fact: .temporal(fact),
                                        source: .builtInGrammar))
                index += length
            } else {
                index += 1
            }
        }
        return spans
    }

    // swiftlint:disable cyclomatic_complexity - one branch per time-phrase shape
    /// The longest time phrase starting at `index`: its length in tokens and
    /// what it means.
    package static func match(_ keys: [String], at index: Int) -> (Int, TemporalFact)? {
        let key = keys[index]
        if let hour = partsOfDay[key] {
            var fact = TemporalFact(start: DateComponents(hour: hour, minute: 0))
            fact.isApproximate = true
            return (1, fact)
        }
        // "between 1 and 2pm"
        if key == "between", let (first, used1) = clock(keys, index + 1),
           index + 1 + used1 < keys.count, keys[index + 1 + used1] == "and",
           let (second, used2) = clock(keys, index + 2 + used1) {
            return withDuration(keys, index, 2 + used1 + used2, range(first, second))
        }
        // "from 9 till 11", "from 1pm" — not "from 3 oct" (days).
        if key == "from", let (first, used1) = clock(keys, index + 1), !isDayNumberWithMonth(keys, index + 1) {
            if let end = rangeAfter(first, keys, index + 1 + used1) {
                return withDuration(keys, index, 1 + used1 + end.length, end.fact)
            }
            guard !first.isBare || first.hour <= 12 else { return nil }
            return withDuration(keys, index, 1 + used1, TemporalFact(start: first.components(alone: true)))
        }
        // "at 3", "@ 10:30", "at noon", "at half past 2"
        if key == "at" || key == "@", let (time, used) = clock(keys, index + 1) {
            if let end = rangeAfter(time, keys, index + 1 + used) {
                return withDuration(keys, index, 1 + used + end.length, end.fact)
            }
            return withDuration(keys, index, 1 + used, TemporalFact(start: time.components(alone: true)))
        }
        // "@10", "@10:30", "@3pm" — glued, so never a place.
        if key.hasPrefix("@"), let time = parseClock(String(key.dropFirst())) {
            return withDuration(keys, index, 1, TemporalFact(start: time.components(alone: true)))
        }
        // "13-14" (one token), "1pm–2pm", "13:00 to 14:30"
        // Bare hours ("11-12") need a day or a repeat somewhere in the
        // phrase — and aren't pages ("pages 3-5") or days ("3-5 oct").
        let bareIsHours = phraseSaysWhen(keys) && !(index > 0 && countedNouns.contains(keys[index - 1]))
            && !(index > 0 && QuickAddVocabulary.month(keys[index - 1]) != nil)
        if let glued = gluedRange(key, bareIsHours: bareIsHours && !isDayNumberWithMonth(keys, index)) {
            return withDuration(keys, index, 1, glued)
        }
        if let (time, used) = clock(keys, index) {
            // Two plain numbers are a time only in 24-hour form ("13 to 14")
            // or beside a day ("tomorrow 10 to 11").
            if let end = rangeAfter(time, keys, index + used),
               !time.isBare || end.isBareTwentyFour
                || bareIsHours && !isDayNumberWithMonth(keys, index + used + end.length - 1) {
                return withDuration(keys, index, used + end.length, end.fact)
            }
            // A plain time (not bare) followed by a duration: "1pm for 1h".
            if !time.isBare, let (length, duration) = self.duration(keys, index + used) {
                return (used + length, timed(time.components(alone: true), plus: duration))
            }
            // A spoken time ("half past 2") stands on its own.
            if time.isSpoken { return (used, TemporalFact(start: time.components(alone: true))) }
        }
        return nil
    }
    // swiftlint:enable cyclomatic_complexity

    /// "3 oct", "3rd october": a day, not a time.
    package static func isDayNumberWithMonth(_ keys: [String], _ index: Int) -> Bool {
        index + 1 < keys.count && QuickAddVocabulary.month(keys[index + 1]) != nil
    }

    // MARK: - Pieces

    /// A time of day, as typed.
    package struct Clock {
        package var hour: Int
        package var minute: Int
        /// "am"/"pm" was given.
        package var meridiem: ClockMeridiem?
        /// Written with a leading zero or as a word ("09:00", "noon") —
        /// meant exactly as written.
        package var isExact = false
        /// Just a number ("3", "14") — a time only in a time phrase.
        package var isBare: Bool { meridiem == nil && !isExact && !hasMinutes && !isSpoken }
        package var hasMinutes = false
        package var isSpoken = false

        /// 24-hour, applying the afternoon rule to a lone 1–7 o'clock.
        package func components(alone: Bool) -> DateComponents {
            DateComponents(hour: hour24(pmFor1to7: alone), minute: minute)
        }

        package func hour24(pmFor1to7: Bool) -> Int {
            switch meridiem {
            case .am?: return hour % 12
            case .pm?: return hour % 12 + 12
            case nil:
                if isExact { return hour }
                return pmFor1to7 && (1...7).contains(hour) ? hour + 12 : hour
            }
        }
    }

    /// A time starting at `index` (one or two tokens: "1pm", "1 pm",
    /// "half past 2", "noon"), and how many tokens it used.
    package static func clock(_ keys: [String], _ index: Int) -> (Clock, Int)? {
        guard index < keys.count else { return nil }
        let key = keys[index]
        if key == "noon" { return (Clock(hour: 12, minute: 0, isExact: true), 1) }
        if key == "midnight" { return (Clock(hour: 0, minute: 0, isExact: true), 1) }
        if ["half", "quarter"].contains(key), index + 2 < keys.count, ["past", "to"].contains(keys[index + 1]),
           let (base, used) = clock(keys, index + 2), base.isBare || base.meridiem != nil {
            var time = base
            let offset = key == "half" ? 30 : 15
            if keys[index + 1] == "past" {
                time.minute = offset
            } else {
                // "quarter to 1" is 12:45.
                time.hour = time.hour == 1 ? 12 : time.hour == 0 ? 23 : time.hour - 1
                time.minute = 60 - offset
            }
            time.hasMinutes = true
            time.isSpoken = true
            return (time, 2 + used)
        }
        guard var time = parseClock(key) else { return nil }
        // "1 pm", "10 am"
        if time.meridiem == nil, !time.isExact, index + 1 < keys.count, let meridiem = meridiem(keys[index + 1]) {
            guard (1...12).contains(time.hour) else { return nil }
            time.meridiem = meridiem
            return (time, 2)
        }
        return (time, 1)
    }

    /// "13", "9:30", "14.30", "1pm", "2:30p", "09:00".
    package static func parseClock(_ token: String) -> Clock? {
        var text = Substring(token)
        var meridiem: ClockMeridiem?
        for (suffix, value) in [("a.m.", ClockMeridiem.am), ("p.m.", .pm), ("am", .am), ("pm", .pm), ("a", .am), ("p", .pm)]
        where text.hasSuffix(suffix) && text.count > suffix.count {
            meridiem = value
            text = text.dropLast(suffix.count)
            break
        }
        let parts = text.split(omittingEmptySubsequences: false, whereSeparator: { $0 == ":" || $0 == "." })
        guard (1...2).contains(parts.count), parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy { $0.isNumber } }),
              parts[0].count <= 2, let hour = Int(parts[0]) else { return nil }
        let minute = parts.count == 2 ? Int(parts[1]) : 0
        guard let minute, parts.count == 1 || parts[1].count == 2, (0...59).contains(minute) else { return nil }
        if meridiem != nil { guard (1...12).contains(hour) else { return nil } } else { guard (0...23).contains(hour) else { return nil } }
        var clock = Clock(hour: hour, minute: minute, meridiem: meridiem)
        clock.hasMinutes = parts.count == 2
        clock.isExact = meridiem == nil && (parts[0].count == 2 && parts[0].first == "0")
        return clock
    }

    package static func meridiem(_ key: String) -> ClockMeridiem? {
        switch key {
        case "am", "a.m.": .am
        case "pm", "p.m.": .pm
        default: nil
        }
    }

    /// "13-14", "1pm–2pm", "9:30->9:45", "noon-1pm", "1pm~2pm" as one token.
    /// A day or a repeat said anywhere ("today", "tue", "next week",
    /// "weekly", "every …"): with it, "11-12" can only be hours.
    package static func phraseSaysWhen(_ keys: [String]) -> Bool {
        keys.contains { key in
            ["today", "tomorrow", "tonight", "tmrw", "tmr", "week", QuickAddVocabulary.every].contains(key)
                || QuickAddVocabulary.weekday(key) != nil || QuickAddVocabulary.recurrenceWords[key] != nil
        }
    }

    package static func gluedRange(_ key: String, bareIsHours: Bool = false) -> TemporalFact? {
        for separator in ["->", "–", "—", "~", "-"] {
            let parts = key.components(separatedBy: separator)
            guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty,
                  let (first, used1) = clock([parts[0]], 0), used1 == 1,
                  let (second, used2) = clock([parts[1]], 0), used2 == 1 else { continue }
            // Two plain numbers are a time only in 24-hour form ("13-14") or
            // in a phrase that says when ("11-12 today").
            if first.isBare && second.isBare && max(first.hour, second.hour) < 13 && !bareIsHours { return nil }
            return range(first, second)
        }
        return nil
    }

    /// A range word and an end time after a start: "to 2pm", "- 14:30".
    /// Also says whether both were plain numbers in 24-hour form.
    package static func rangeAfter(_ start: Clock, _ keys: [String], _ index: Int) -> ClockRangeEnd? {
        guard index < keys.count, rangeWords.contains(keys[index]),
              let (end, used) = clock(keys, index + 1) else { return nil }
        return ClockRangeEnd(length: 1 + used, fact: range(start, end),
                             isBareTwentyFour: start.isBare && end.isBare && max(start.hour, end.hour) >= 13)
    }

    /// Start and end, sharing an am/pm written once ("1-2pm"), with the
    /// afternoon rule and an end earlier than the start read as afternoon
    /// ("9-5" → 9–17, "11-1" → 11–13).
    package static func range(_ first: Clock, _ second: Clock) -> TemporalFact {
        var first = first
        if first.meridiem == nil, !first.isExact, let shared = second.meridiem, (1...12).contains(first.hour) {
            var candidate = first
            candidate.meridiem = shared
            if candidate.hour24(pmFor1to7: false) <= second.hour24(pmFor1to7: false) { first = candidate }
        }
        let start = first.hour24(pmFor1to7: true)
        var end = second.hour24(pmFor1to7: false)
        if second.meridiem == nil, !second.isExact, end * 60 + second.minute <= start * 60 + first.minute, end < 12 {
            end += 12
        }
        return TemporalFact(start: DateComponents(hour: start, minute: first.minute), end: DateComponents(hour: end, minute: second.minute))
    }

    /// "for 1h", "1.5h", "90 min", "2 hours", "1h30" after a time: its
    /// minutes and how many tokens it used.
    package static func duration(_ keys: [String], _ index: Int) -> (Int, Int)? {
        var position = index
        if position < keys.count, keys[position] == "for" { position += 1 }
        guard position < keys.count else { return nil }
        let key = keys[position]
        // "1h30", "1h30m"
        if let h = key.firstIndex(of: "h"), let hours = Int(key[..<h]) {
            let rest = key[key.index(after: h)...].trimmingCharacters(in: CharacterSet(charactersIn: "m"))
            if !rest.isEmpty, let minutes = Int(rest) { return (position - index + 1, hours * 60 + minutes) }
        }
        // "1.5h", "90m", "2hours"
        let number = key.prefix { $0.isNumber || $0 == "." }
        let unit = String(key.dropFirst(number.count))
        guard let value = Double(number), value > 0 else { return nil }
        if let perUnit = QuickAddVocabulary.durationUnits[unit], perUnit < 1440 {
            return (position - index + 1, Int(value * Double(perUnit)))
        }
        if unit.isEmpty, position + 1 < keys.count, let perUnit = QuickAddVocabulary.durationUnits[keys[position + 1]], perUnit < 1440 {
            return (position - index + 2, Int(value * Double(perUnit)))
        }
        return nil
    }

    /// A start (and maybe end) followed by an optional duration.
    package static func withDuration(_ keys: [String], _ index: Int, _ length: Int, _ fact: TemporalFact) -> (Int, TemporalFact) {
        guard fact.end == nil, let start = fact.start, let (more, minutes) = duration(keys, index + length) else {
            return (length, fact)
        }
        return (length + more, timed(start, plus: minutes))
    }

    package static func timed(_ start: DateComponents, plus minutes: Int) -> TemporalFact {
        let total = (start.hour ?? 0) * 60 + (start.minute ?? 0) + minutes
        var fact = TemporalFact(start: start, end: DateComponents(hour: (total / 60) % 24, minute: total % 60))
        fact.duration = minutes
        return fact
    }
}

/// "am" or "pm", as typed.
package enum ClockMeridiem { case am, pm }

/// What a range word and end time add after a start ("to 2pm"): how many
/// keys they took, the range, and whether both were plain 24-hour numbers.
package struct ClockRangeEnd {
    package let length: Int
    package let fact: TemporalFact
    package let isBareTwentyFour: Bool
}
