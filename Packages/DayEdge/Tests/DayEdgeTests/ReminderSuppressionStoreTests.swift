import Foundation
import XCTest
@testable import Shell
@testable import Domain

@MainActor
final class ReminderSuppressionStoreTests: XCTestCase {
    private final class Clock {
        var date: Date
        init(_ date: Date) { self.date = date }
        func now() -> Date { date }
    }

    private let monday = Date(timeIntervalSince1970: 2_000_000_000)

    private func key(start: Date, original: Date?) -> ReminderOccurrenceKey {
        ReminderOccurrenceKey.eventKit(
            calendarIdentifier: "work", isRecurring: true,
            seriesIdentifier: "daily-meeting", calendarItemIdentifier: "item",
            eventIdentifier: "event", startDate: start, occurrenceDate: original
        )!
    }

    private func event(_ id: String, key: ReminderOccurrenceKey, start: Date, end: Date) -> AgendaEventModel {
        AgendaEventModel(
            id: id, startTime: "10:00", endTime: "10:30",
            startDate: start, endDate: end, title: id,
            reminderOccurrenceKey: key
        )
    }

    func testRecurringOccurrencesStayIndependentAndMovedOccurrenceKeepsKey() {
        let tuesday = monday.addingTimeInterval(24 * 60 * 60)
        let movedMonday = monday.addingTimeInterval(2 * 60 * 60)
        XCTAssertEqual(key(start: monday, original: monday), key(start: movedMonday, original: monday))
        XCTAssertNotEqual(key(start: monday, original: monday), key(start: tuesday, original: tuesday))

        let fallback = key(start: monday, original: nil)
        XCTAssertNotEqual(fallback, key(start: movedMonday, original: nil))
    }

    func testNonrecurringTimeEditKeepsKeyAndDifferentCalendarDoesNot() {
        func single(calendar: String, start: Date) -> ReminderOccurrenceKey {
            ReminderOccurrenceKey.eventKit(
                calendarIdentifier: calendar, isRecurring: false,
                seriesIdentifier: nil, calendarItemIdentifier: "item",
                eventIdentifier: "event", startDate: start, occurrenceDate: nil
            )!
        }
        XCTAssertEqual(single(calendar: "work", start: monday),
                       single(calendar: "work", start: monday.addingTimeInterval(3600)))
        XCTAssertNotEqual(single(calendar: "work", start: monday),
                          single(calendar: "personal", start: monday))
    }

    func testPersistenceRestorationAndExpiry() {
        let suite = "ReminderSuppressionStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let clock = Clock(monday.addingTimeInterval(-60))
        let first = event("Monday", key: key(start: monday, original: monday),
                          start: monday, end: monday.addingTimeInterval(1800))
        let nextStart = monday.addingTimeInterval(24 * 60 * 60)
        let second = event("Tuesday", key: key(start: nextStart, original: nextStart),
                           start: nextStart, end: nextStart.addingTimeInterval(1800))

        let store = ReminderSuppressionStore(defaults: defaults, now: clock.now)
        XCTAssertTrue(store.setMuted(true, for: first))
        XCTAssertTrue(store.isMuted(first))
        XCTAssertFalse(store.isMuted(second))

        let reloaded = ReminderSuppressionStore(defaults: defaults, now: clock.now)
        XCTAssertTrue(reloaded.isMuted(first))
        XCTAssertFalse(reloaded.isMuted(second))
        XCTAssertTrue(reloaded.setMuted(false, for: first))
        XCTAssertFalse(ReminderSuppressionStore(defaults: defaults, now: clock.now).isMuted(first))

        XCTAssertTrue(reloaded.setMuted(true, for: first))
        clock.date = monday.addingTimeInterval(1800 + ReminderSuppressionStore.gracePeriod + 1)
        XCTAssertFalse(reloaded.isMuted(first))
        reloaded.pruneExpired()
        XCTAssertTrue(reloaded.expiryByKey.isEmpty)
        XCTAssertTrue(ReminderSuppressionStore(defaults: defaults, now: clock.now).expiryByKey.isEmpty)
    }

    func testGlobalMutePersistsExpiresAndClears() {
        let suite = "ReminderSuppressionStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let clock = Clock(monday)
        let store = ReminderSuppressionStore(defaults: defaults, now: clock.now)
        var notified = 0
        store.onGlobalMutation = { notified += 1 }
        XCTAssertFalse(store.isGloballyMuted)

        store.muteAll(until: monday.addingTimeInterval(3600), chosen: .evening)
        XCTAssertTrue(store.isGloballyMuted)
        XCTAssertEqual(notified, 1)
        let reloaded = ReminderSuppressionStore(defaults: defaults, now: clock.now)
        XCTAssertEqual(reloaded.activeGlobalMute, .init(until: monday.addingTimeInterval(3600), chosen: .evening))

        clock.date = monday.addingTimeInterval(3601)
        XCTAssertFalse(reloaded.isGloballyMuted)
        XCTAssertNil(reloaded.activeGlobalMute)
        reloaded.pruneExpired()
        XCTAssertNil(ReminderSuppressionStore(defaults: defaults, now: clock.now).globalMute)

        store.muteAll(until: monday.addingTimeInterval(7200), chosen: nil)
        store.unmuteAll()
        XCTAssertFalse(store.isGloballyMuted)
        XCTAssertNil(ReminderSuppressionStore(defaults: defaults, now: clock.now).globalMute)
    }

    func testReconcileExtendsMutedMovedOccurrenceOnly() {
        let suite = "ReminderSuppressionStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let clock = Clock(monday)
        let original = event("Monday", key: key(start: monday, original: monday),
                             start: monday, end: monday.addingTimeInterval(1800))
        let store = ReminderSuppressionStore(defaults: defaults, now: clock.now)
        store.setMuted(true, for: original)
        let firstExpiry = store.expiryByKey[original.reminderOccurrenceKey!.storageKey]!

        let moved = event("Monday moved", key: key(start: monday.addingTimeInterval(3600), original: monday),
                          start: monday.addingTimeInterval(3600), end: monday.addingTimeInterval(5400))
        store.reconcile([moved])
        XCTAssertTrue(store.isMuted(moved))
        XCTAssertGreaterThan(store.expiryByKey[moved.reminderOccurrenceKey!.storageKey]!, firstExpiry)
    }
}
