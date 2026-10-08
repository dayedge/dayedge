import Foundation
import JavaScriptCore

/// The `JSContext` is the expensive part to spin up (parsing ~155KB of
/// minified JS into a fresh JS heap) — created lazily on first actual
/// use, so an app session that never touches search never pays for it,
/// and kept while it's in use rather than repeating that parse on every
/// keystroke. Released after `idleRelease` without a parse: the engine
/// holds 11–16 MB, and creating it again costs ~10–20 ms (measured). A `JSContext` isn't
/// `Sendable`, so all access is confined to one private serial queue
/// instead of trying to cross actor boundaries with it.
/// One chrono match: where it is in the text and what it means. Only the
/// parts chrono is certain of should be trusted (`isDayCertain`,
/// `isTimeCertain`); the rest of `date` is chrono's own filling-in.
package struct ChronoSpan: Equatable, Sendable {
    package let utf16Offset: Int
    package let utf16Length: Int
    package let date: DateComponents
    package let isDayCertain: Bool
    package let isTimeCertain: Bool
    /// "March", "last March": the month is meant even without a day.
    package var isMonthCertain = false
    /// "March 2025": the year was said, not inferred.
    package var isYearCertain = false
    /// Present when a time range ("10am - 11am") ended at a certain time.
    package let end: DateComponents?
}

package final class ChronoEngine: @unchecked Sendable {
    package static let shared = ChronoEngine()

    /// How long the engine stays after its last parse.
    package static let idleRelease: TimeInterval = 120

    private let queue = DispatchQueue(label: "com.dayedge.chrono")
    private var context: JSContext?
    private var release: DispatchWorkItem?

    /// A genuine `await` suspension point (`queue.async` + a
    /// continuation), not `queue.sync` — a synchronous block here would
    /// run this whole call (JS evaluation included) to completion on
    /// whatever thread called it with no actual suspension, since
    /// calling a synchronous function from an `async` one doesn't
    /// yield. On the MainActor (where `SearchBarView`'s live-typing
    /// resolution runs), that blocks the very thread responsible for
    /// canceling/restarting the task on the next keystroke — this is
    /// what let a stale, in-flight resolution for an earlier partial
    /// query occasionally still land after a newer one, showing the
    /// wrong interpretation for a query that actually resolves fine on
    /// its own (confirmed via a direct, isolated call).
    package func resolve(_ text: String, referenceDate: Date) async -> SearchIntent? {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                continuation.resume(returning: resolveSync(text, referenceDate: referenceDate))
            }
        }
    }

    private func resolveSync(_ text: String, referenceDate: Date) -> SearchIntent? {
        let context = loadedContext()
        guard let resolveFn = context.objectForKeyedSubscript("dayedgeResolveIntent"),
              !resolveFn.isUndefined,
              let refDateValue = JSValue(object: referenceDate, in: context)
        else {
            return nil
        }

        guard let result = resolveFn.call(withArguments: [text, refDateValue]),
              !result.isNull, !result.isUndefined,
              let dict = result.toDictionary(),
              let year = dict["year"] as? Int,
              let month = dict["month"] as? Int,
              let day = dict["day"] as? Int,
              let hasDay = dict["hasDay"] as? Bool
        else {
            return nil
        }

        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = hasDay ? day : 1
        guard let date = Calendar(identifier: .gregorian).date(from: components) else { return nil }
        return hasDay ? .jumpToDate(date) : .jumpToMonth(date)
    }

    /// Every date/time chrono finds anywhere in `text`, with where it
    /// found it — for Quick Add, which removes recognized pieces from a
    /// sentence. `forwardDate`: an ambiguous date means the next one.
    package func spans(in text: String, referenceDate: Date) async -> [ChronoSpan] {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                continuation.resume(returning: spansSync(text, referenceDate: referenceDate))
            }
        }
    }

    private func spansSync(_ text: String, referenceDate: Date) -> [ChronoSpan] {
        let context = loadedContext()
        guard let extract = context.objectForKeyedSubscript("dayedgeExtractSpans"), !extract.isUndefined,
              let refDateValue = JSValue(object: referenceDate, in: context),
              let result = extract.call(withArguments: [text, refDateValue]),
              let items = result.toArray() as? [[String: Any]] else { return [] }
        return items.compactMap { item in
            func int(_ key: String) -> Int? { (item[key] as? NSNumber)?.intValue }
            guard let index = int("index"), let length = int("length"),
                  let year = int("year"), let month = int("month"), let day = int("day"),
                  let hour = int("hour"), let minute = int("minute") else { return nil }
            return ChronoSpan(
                utf16Offset: index, utf16Length: length,
                date: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute),
                isDayCertain: item["dayCertain"] as? Bool ?? false,
                isTimeCertain: item["hourCertain"] as? Bool ?? false,
                isMonthCertain: item["monthCertain"] as? Bool ?? false,
                isYearCertain: item["yearCertain"] as? Bool ?? false,
                end: (item["endHourCertain"] as? Bool ?? false)
                    ? DateComponents(hour: int("endHour"), minute: int("endMinute")) : nil
            )
        }
    }

    /// On `queue`, as every use is.
    private func loadedContext() -> JSContext {
        scheduleRelease()
        if let context { return context }

        let newContext = JSContext()!
        // Without chrono.js (a broken bundle) this stage simply never matches.
        if let url = Bundle.module.url(forResource: "chrono", withExtension: "js"),
           let library = try? String(contentsOf: url, encoding: .utf8) {
            newContext.evaluateScript(library)
        }
        newContext.evaluateScript(Self.glueScript)

        context = newContext
        return newContext
    }

    /// Drops the engine once nothing has parsed for `idleRelease`; each
    /// parse pushes that back. On `queue`.
    private func scheduleRelease() {
        release?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.context = nil
            self?.release = nil
        }
        release = work
        queue.asyncAfter(deadline: .now() + Self.idleRelease, execute: work)
    }

    /// Bridges chrono's rich `ParsingResult` — per-field certainty via
    /// `isCertain(component)`, not a single confidence score, see
    /// project notes on why chrono has no such score — down to exactly
    /// what this stage needs: an absolute date, and whether a specific
    /// day was actually intended versus the query being month-level
    /// only ("september 2025" implies day 1 without meaning it).
    /// Requires the match to span the *entire* query — a date-shaped
    /// fragment inside a longer phrase (e.g. "monday" inside "meeting
    /// with monday.com") is refused rather than guessed at.
    private static let glueScript = """
    function dayedgeExtractSpans(text, refDate) {
        return chrono.parse(text, refDate, { forwardDate: true }).map(function (r) {
            var s = r.start, e = r.end;
            return {
                index: r.index, length: r.text.length,
                year: s.get('year'), month: s.get('month'), day: s.get('day'),
                hour: s.get('hour'), minute: s.get('minute'),
                dayCertain: s.isCertain('day') || s.isCertain('weekday'),
                monthCertain: s.isCertain('month'),
                yearCertain: s.isCertain('year'),
                hourCertain: s.isCertain('hour'),
                endHourCertain: e ? e.isCertain('hour') : false,
                endHour: e ? e.get('hour') : 0, endMinute: e ? e.get('minute') : 0
            };
        });
    }
    function dayedgeResolveIntent(text, refDate) {
        var results = chrono.parse(text, refDate);
        if (results.length !== 1) return null;
        var r = results[0];
        if (r.index !== 0 || r.text.length !== text.length) return null;
        var date = r.start.date();
        var hasDay = r.start.isCertain('day') || r.start.isCertain('weekday');
        return {
            year: date.getFullYear(),
            month: date.getMonth() + 1,
            day: date.getDate(),
            hasDay: hasDay
        };
    }
    """
}
