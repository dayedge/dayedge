import Foundation
import os
import Domain
import TimeWhisper
import TimeWhisperModelAll

/// The app's one door to TimeWhisper, shared by Quick Add, search and the assistant's tools. It makes the library for the
/// user's calendar (first weekday, date order), turns its answers into the app's drafts, and lets the model go when
/// nothing has asked for a while.
package actor NaturalLanguageParser {
    /// The tagger model bundled with the app: it says what each part of a line is for (title, day, time, repeat, place…).
    /// The parser cannot work without it. Its compiled form is kept in the app's caches, so it is compiled once per model
    /// and system rather than on every launch.
    private static let bundledTagger = CoreMLTagger(folder: AllModel.folder, compiledModelCache: compiledModelCache)
    private static var compiledModelCache: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "com.dayedge.app", isDirectory: true)
            .appendingPathComponent("TimeWhisper", isDirectory: true)
    }
    /// The app's parser.
    package static let live = NaturalLanguageParser()
    private static let logger = Logger(subsystem: "com.dayedge.parser", category: "TimeWhisper")
    /// How long the model stays loaded after the last request.
    private static let idleTime: Duration = .seconds(120)

    /// The language to read in, asked on every request (`ParsingLanguage.current()` for the app).
    private let language: @Sendable () -> String
    /// The library, made for the settings in `key`. Made again when the language, first weekday or region changes.
    private var parser: (key: LibraryKey, library: TimeWhisper)?
    private var idleRelease: Task<Void, Never>?

    package init(language: @escaping @Sendable () -> String = { ParsingLanguage.current() }) {
        self.language = language
    }

    deinit { idleRelease?.cancel() }

    // MARK: Requests

    /// What `text` asks to create, as the app's drafts, best first. Empty when it asks for nothing.
    package func parse(_ text: String, referenceDate: Date, calendar: Calendar,
                       lists: [CalendarSource], calendars: [CalendarSource]) async -> [QuickAddCandidate] {
        let destinations = lists.map { Destination(id: $0.id, name: $0.title, kind: .taskList) }
            + calendars.map { Destination(id: $0.id, name: $0.title, kind: .calendar) }
        let context = ParseContext(referenceDate: referenceDate, timeZone: calendar.timeZone, destinations: destinations)
        return await run("creation request", calendar: calendar, otherwise: []) { library in
            try await library.parse(text, context: context).map { try QuickAddCandidate($0, calendar: calendar) }
        }
    }

    /// The first date inside longer text, and the text without it: "standup tomorrow" → tomorrow, "standup".
    package func findTemporal(_ text: String, referenceDate: Date, calendar: Calendar) async -> FoundDate? {
        let context = ParseContext(referenceDate: referenceDate, timeZone: calendar.timeZone)
        return await run("date in text", calendar: calendar, otherwise: nil) {
            try await $0.findTemporal(text, context: context).map { FoundDate(date: ParsedDate($0.temporal), remainingText: $0.remainingText) }
        }
    }

    /// What `text` means when all of it is one date or range: "next week", "friday 3pm", "2026-10-01..2026-10-07".
    package func parseTemporal(_ text: String, referenceDate: Date, calendar: Calendar) async -> ParsedDate? {
        let context = ParseContext(referenceDate: referenceDate, timeZone: calendar.timeZone)
        return await run("date", calendar: calendar, otherwise: nil) { try await $0.parseTemporal(text, context: context).map(ParsedDate.init) }
    }

    /// Loads the model ahead of the first request (when the palette opens), so typing does not wait for it. It is let go
    /// when idle, as after a request.
    package func prepare(calendar: Calendar) async {
        do {
            _ = try library(for: calendar)
            try await Self.bundledTagger.prepare()
        } catch is CancellationError {
            return
        } catch {
            Self.logger.error("Could not load the parser model: \(String(describing: error), privacy: .public)")
        }
    }

    /// Lets the model and the library's resources go; the next request loads them again.
    package func releaseResources() async {
        idleRelease?.cancel()
        idleRelease = nil
        // The model is let go here too: one loaded by `prepare` was never handed to the library.
        await Self.bundledTagger.close()
        do {
            try await parser?.library.releaseResources()
        } catch is CancellationError {
            return
        } catch {
            Self.logger.error("Could not release parser resources: \(String(describing: error), privacy: .public)")
        }
    }

    // MARK: Library

    /// Runs one request against the library for `calendar`. A cancelled request, or one that fails, gives `otherwise`; a
    /// failure is logged as `what`.
    private func run<Value: Sendable>(_ what: String, calendar: Calendar, otherwise: Value,
                                      _ request: (TimeWhisper) async throws -> Value) async -> Value {
        do {
            return try await request(library(for: calendar))
        } catch is CancellationError {
            return otherwise
        } catch {
            Self.logger.error("Could not parse \(what, privacy: .public): \(String(describing: error), privacy: .public)")
            return otherwise
        }
    }

    /// The library for the current language and `calendar`'s settings, made on first use. Every request postpones the
    /// idle release.
    private func library(for calendar: Calendar) throws -> TimeWhisper {
        defer { releaseWhenIdle() }
        let key = LibraryKey(language: language(), calendar: calendar)
        if let parser, parser.key == key { return parser.library }
        let library = try TimeWhisper(configuration: Configuration(calendar: calendar, language: key.language),
                                      taggerFactory: { Self.bundledTagger })
        parser = (key, library)
        return library
    }

    /// What the library's configuration is made from, cheap to compare on every request.
    private struct LibraryKey: Equatable {
        let language: String
        let firstWeekday: Int
        let locale: String?

        init(language: String, calendar: Calendar) {
            self.language = language
            firstWeekday = calendar.firstWeekday
            locale = calendar.locale?.identifier
        }
    }

    private func releaseWhenIdle() {
        idleRelease?.cancel()
        idleRelease = Task { [weak self] in
            try? await Task.sleep(for: Self.idleTime)
            await self?.releaseIfStillIdle()
        }
    }

    /// A request that came in meanwhile cancelled this release.
    private func releaseIfStillIdle() async {
        guard !Task.isCancelled else { return }
        await releaseResources()
    }
}

private extension ParsedDate {
    init(_ temporal: TemporalSpec) {
        let span: Span = switch temporal.granularity {
        case .day: .day
        case .week: .week
        case .month: .month
        case .year: .year
        }
        self.init(start: temporal.start.date, end: temporal.endExclusive.date, span: span, hasTime: temporal.hasExplicitTime)
    }
}
