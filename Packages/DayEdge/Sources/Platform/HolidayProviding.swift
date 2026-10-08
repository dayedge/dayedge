import Foundation
import Domain

/// OpenHolidays API (https://openholidaysapi.org), the default source.
/// Only nationwide public holidays are used.
package struct OpenHolidaysProvider: HolidayProviding {
    package var session: URLSession = .shared
    package var baseURL = URL(string: "https://openholidaysapi.org")!
    package var languageCode: String = Locale.current.language.languageCode?.identifier ?? "en"

    private struct LocalizedText: Decodable {
        let language: String
        let text: String
    }

    private struct RawHoliday: Decodable {
        let startDate: String
        let endDate: String
        let type: String
        let nationwide: Bool
        let name: [LocalizedText]
    }

    private struct RawCountry: Decodable {
        let isoCode: String
    }

    package func holidays(region: String, year: Int) async throws -> [PublicHoliday] {
        var components = URLComponents(url: baseURL.appendingPathComponent("PublicHolidays"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "countryIsoCode", value: region),
            URLQueryItem(name: "validFrom", value: "\(year)-01-01"),
            URLQueryItem(name: "validTo", value: "\(year)-12-31"),
            URLQueryItem(name: "languageIsoCode", value: languageCode.uppercased())
        ]
        let raw = try JSONDecoder().decode([RawHoliday].self, from: try await fetch(components.url!))
        return Self.holidays(from: raw, languageCode: languageCode)
    }

    package func supportedRegions() async throws -> Set<String> {
        let url = baseURL.appendingPathComponent("Countries")
        let raw = try JSONDecoder().decode([RawCountry].self, from: try await fetch(url))
        return Set(raw.map { $0.isoCode.uppercased() })
    }

    private func fetch(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }
        return data
    }

    private static func holidays(from raw: [RawHoliday], languageCode: String) -> [PublicHoliday] {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let parser = DateFormatter()
        parser.calendar = utc
        parser.timeZone = utc.timeZone
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.dateFormat = "yyyy-MM-dd"

        var result: [PublicHoliday] = []
        for item in raw where item.type == "Public" && item.nationwide {
            let name = item.name.first { $0.language.caseInsensitiveCompare(languageCode) == .orderedSame }?.text
                ?? item.name.first { $0.language.caseInsensitiveCompare("EN") == .orderedSame }?.text
                ?? item.name.first?.text
                ?? L10n.tr("holidayproviding.public.holiday", "Public holiday")
            guard let start = parser.date(from: item.startDate),
                  let end = parser.date(from: item.endDate), start <= end else { continue }
            var day = start
            while day <= end {
                result.append(PublicHoliday(dateKey: parser.string(from: day), name: name))
                guard let next = utc.date(byAdding: .day, value: 1, to: day) else { break }
                day = next
            }
        }
        return result
    }
}

/// Adds an offline-first disk cache (Application Support) and in-flight
/// de-duplication. After the first successful fetch a region/year works
/// offline and deterministically; on failure the stale copy (or nothing)
/// is used and the workday count simply falls back to weekends only.
package actor CachingHolidayProvider: HolidayProviding {
    package static let shared = CachingHolidayProvider(
        upstream: OpenHolidaysProvider(),
        directory: defaultDirectory
    )

    package static var defaultDirectory: URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DayEdge/holidays", isDirectory: true)
    }

    private struct Entry<Value: Codable>: Codable {
        let fetchedAt: Date
        let value: Value
    }

    private let upstream: HolidayProviding
    private let directory: URL
    private let languageCode: String
    private let maxAge: TimeInterval
    private let now: @Sendable () -> Date
    private var inFlight: [String: Task<[PublicHoliday], Error>] = [:]

    package init(upstream: HolidayProviding,
                 directory: URL,
                 languageCode: String = Locale.current.language.languageCode?.identifier ?? "en",
                 maxAge: TimeInterval = 30 * 24 * 3600,
                 now: @escaping @Sendable () -> Date = { Date() }) {
        self.upstream = upstream
        self.directory = directory
        self.languageCode = languageCode
        self.maxAge = maxAge
        self.now = now
    }

    package func holidays(region: String, year: Int) async throws -> [PublicHoliday] {
        let file = directory.appendingPathComponent("\(region.uppercased())-\(year)-\(languageCode).json")
        let cached: Entry<[PublicHoliday]>? = read(file)
        if let cached, now().timeIntervalSince(cached.fetchedAt) < maxAge {
            return cached.value
        }
        let key = file.lastPathComponent
        let task = inFlight[key] ?? Task { [upstream] in
            try await upstream.holidays(region: region, year: year)
        }
        inFlight[key] = task
        defer { inFlight[key] = nil }
        do {
            let fresh = try await task.value
            write(Entry(fetchedAt: now(), value: fresh), to: file)
            return fresh
        } catch {
            if let cached { return cached.value }
            throw error
        }
    }

    package func supportedRegions() async throws -> Set<String> {
        let file = directory.appendingPathComponent("regions.json")
        let cached: Entry<[String]>? = read(file)
        if let cached, now().timeIntervalSince(cached.fetchedAt) < maxAge {
            return Set(cached.value)
        }
        do {
            let fresh = try await upstream.supportedRegions()
            write(Entry(fetchedAt: now(), value: fresh.sorted()), to: file)
            return fresh
        } catch {
            if let cached { return Set(cached.value) }
            throw error
        }
    }

    private func read<Value: Codable>(_ url: URL) -> Entry<Value>? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Entry<Value>.self, from: data)
    }

    private func write<Value: Codable>(_ entry: Entry<Value>, to url: URL) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(entry) {
            try? data.write(to: url, options: .atomic)
        }
    }
}
