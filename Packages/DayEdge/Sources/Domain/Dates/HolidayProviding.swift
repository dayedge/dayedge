import Foundation

/// Source of public-holiday metadata. Deliberately unrelated to EventKit:
/// holidays are never events and need no permission.
package protocol HolidayProviding: Sendable {
    func holidays(region: String, year: Int) async throws -> [PublicHoliday]
    /// ISO 3166-1 alpha-2 codes the source can serve.
    func supportedRegions() async throws -> Set<String>
}
