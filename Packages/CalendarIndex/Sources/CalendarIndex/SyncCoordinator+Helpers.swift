import Foundation
import os

extension SyncCoordinator {
    // MARK: - Helpers

    func keys(for months: [Date]) -> [WorkKey] {
        calendars.flatMap { calendar in months.map { WorkKey(calendarIdentifier: calendar, month: $0) } }
    }

    func markDue(_ scope: DeferredScope) {
        guard !calendars.isEmpty else {
            deferred.append(scope)
            return
        }
        let now = clock.now()
        switch scope {
        case .near:
            markDue(keys(for: planner.nearMonths(now: now, focus: focus)), urgent: false)
        case .all:
            markDue(keys(for: planner.bandMonths(now: now, focus: focus).map(\.month)), urgent: false)
        case .months(let months, let urgent):
            markDue(keys(for: months), urgent: urgent)
        }
    }

    func markDue(_ keys: [WorkKey], urgent: Bool) {
        guard !keys.isEmpty else { return }
        seq += 1
        for key in keys {
            pending[key] = Pending(seq: seq, isUrgent: urgent || (pending[key]?.isUrgent ?? false))
        }
    }

    func block(_ keys: [WorkKey], now: Date) {
        for key in keys {
            let failures = (blocked[key]?.failures ?? 0) + 1
            let delay = min(policy.retryBase.timeInterval * pow(2, Double(failures - 1)), policy.retryMax.timeInterval)
            blocked[key] = Block(until: now.addingTimeInterval(delay), failures: failures)
        }
        resolveWaiters(failing: Set(keys))
    }

    func adaptBatchSize(after duration: TimeInterval) {
        if duration < policy.batchGrowBelow.timeInterval {
            monthsPerQuery = min(policy.maxMonthsPerQuery, monthsPerQuery + 1)
        } else if duration > policy.batchShrinkAbove.timeInterval {
            monthsPerQuery = max(1, monthsPerQuery / 2)
        }
    }

    func resolveWaiters(force: Bool = false, failing: Set<WorkKey> = []) {
        for (id, waiter) in waiters {
            if force || !waiter.keys.isDisjoint(with: failing) {
                waiters[id] = nil
                waiter.continuation.resume(returning: false)
            } else if waiter.keys.allSatisfy({ pending[$0] == nil }) {
                waiters[id] = nil
                waiter.continuation.resume(returning: true)
            }
        }
    }

    func expireWaiter(_ id: UUID) {
        guard let waiter = waiters.removeValue(forKey: id) else { return }
        waiter.continuation.resume(returning: waiter.keys.allSatisfy { pending[$0] == nil })
    }

    func kick() {
        if let idle {
            self.idle = nil
            idle.resume()
        } else {
            kickPending = true
        }
    }

    /// Until new work arrives (`kick`) or, when given, `until` passes.
    func waitForKick(until: Date?) async {
        if kickPending {
            kickPending = false
            return
        }
        wakeTimer?.cancel()
        if let until {
            let delay = max(0, until.timeIntervalSince(clock.now()))
            let clock = clock
            wakeTimer = Task { [weak self] in
                do { try await clock.sleep(for: .seconds(delay)) } catch { return }
                await self?.kick()
            }
        }
        await withCheckedContinuation { idle = $0 }
        wakeTimer?.cancel()
        wakeTimer = nil
    }

    func acquireStep() async {
        guard stepBusy else {
            stepBusy = true
            return
        }
        await withCheckedContinuation { stepQueue.append($0) }
    }

    func releaseStep() {
        if stepQueue.isEmpty {
            stepBusy = false
        } else {
            stepQueue.removeFirst().resume()
        }
    }
}
