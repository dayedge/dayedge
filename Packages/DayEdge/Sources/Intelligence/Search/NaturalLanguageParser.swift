import Foundation
import os
import Domain
import TimeWhisper

/// One library instance serves Quick Add, search and assistant tools.
package actor NaturalLanguageParser {
    package static let live = NaturalLanguageParser()
    private static let logger = Logger(subsystem: "com.dayedge.parser", category: "TimeWhisper")
    private let language: String
    private let spellCheckerFactory: (@Sendable () -> any SpellChecker)?
    private var parser: TimeWhisper?
    private var firstWeekday: Int?
    private var idleRelease: Task<Void, Never>?
    private var generation = 0

    package init(language: String = "en", spellCheckerFactory: (@Sendable () -> any SpellChecker)? = nil) {
        self.language = language
        self.spellCheckerFactory = spellCheckerFactory
    }

    deinit { idleRelease?.cancel() }

    private func instance(calendar: Calendar) throws -> TimeWhisper {
        if firstWeekday != calendar.firstWeekday {
            parser = nil
        }
        if parser == nil {
            let weekday = Weekday(rawValue: (calendar.firstWeekday + 5) % 7 + 1) ?? .monday
            parser = try TimeWhisper(configuration: Configuration(weekStartsOn: weekday, language: language),
                                     spellCheckerFactory: spellCheckerFactory)
            firstWeekday = calendar.firstWeekday
        }
        generation += 1
        let current = generation
        idleRelease?.cancel()
        idleRelease = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(120))
                await self?.releaseResources(ifCurrent: current)
            } catch { /* A new request postpones release. */ }
        }
        guard let parser else { throw TimeWhisperError.backend("Parser unavailable") }
        return parser
    }

    private func releaseResources(ifCurrent current: Int) async {
        guard current == generation else { return }
        await releaseResources()
    }

    package func releaseResources() async {
        idleRelease?.cancel()
        idleRelease = nil
        do {
            try await parser?.releaseResources()
        } catch is CancellationError {
            return
        } catch {
            Self.logger.error("Could not release parser resources: \(String(describing: error), privacy: .public)")
        }
    }

    package func parse(_ text: String, referenceDate: Date, calendar: Calendar,
                       lists: [CalendarSource], calendars: [CalendarSource]) async -> [QuickAddCandidate] {
        do {
            let parser = try instance(calendar: calendar)
            let destinations = lists.map { Destination(id: $0.id, name: $0.title, kind: .taskList) }
                + calendars.map { Destination(id: $0.id, name: $0.title, kind: .calendar) }
            let context = ParseContext(referenceDate: referenceDate, timeZone: calendar.timeZone, destinations: destinations)
            return try await parser.parse(text, context: context).map { try QuickAddCandidate($0, calendar: calendar) }
        } catch is CancellationError {
            return []
        } catch {
            Self.logger.error("Could not parse creation request: \(String(describing: error), privacy: .public)")
            return []
        }
    }

    package func findTemporal(_ text: String, referenceDate: Date, calendar: Calendar) async -> FoundTemporal? {
        do {
            let parser = try instance(calendar: calendar)
            return try await parser.findTemporal(text, context: ParseContext(referenceDate: referenceDate, timeZone: calendar.timeZone))
        } catch is CancellationError {
            return nil
        } catch {
            Self.logger.error("Could not parse temporal request: \(String(describing: error), privacy: .public)")
            return nil
        }
    }
}
