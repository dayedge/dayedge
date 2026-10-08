import Foundation

/// How far the index reaches, as priority bands — the one place to tune
/// coverage. P0 follows what the user is looking at; P1–P3 are measured
/// from today's month.
public enum SyncHorizons {
    /// P0: the visible range, padded by this many months each side (so an
    /// event that started before the range is owned and present).
    public static let visiblePaddingMonths = 1
    /// P1: today ± this many months.
    public static let nearMonths = 3
    /// P2: today ± this many months.
    public static let midMonths = 12
    /// P3: today ± this many months (EventKit's own query limit is 4 years).
    public static let farMonths = 48
}

/// Timing and budget knobs for `SyncCoordinator`.
public enum SyncTiming {
    /// `EKEventStoreChanged` arrives in bursts; one pass per burst.
    public static let changeDebounce: Duration = .milliseconds(250)
    /// Backstop refresh age for P0–P1.
    public static let nearMaxAge: Duration = .seconds(15 * 60)
    /// Backstop refresh age for P2–P3 (rolling, oldest first).
    public static let farMaxAge: Duration = .seconds(6 * 3600)
    /// After this many near chunks, one outer chunk runs — outer bands
    /// keep progressing under a notification storm.
    public static let outerEveryNChunks = 4
    /// Adaptive batching: grow the months-per-query while fetches stay
    /// under this, shrink above `batchShrinkAbove`.
    public static let batchGrowBelow: Duration = .milliseconds(50)
    public static let batchShrinkAbove: Duration = .milliseconds(400)
    public static let maxMonthsPerQuery = 6
    /// A soft-deleted row is purged after this even if not every month it
    /// could have moved to has been refetched.
    public static let tombstoneTTL: Duration = .seconds(24 * 3600)
    /// How long `ensure` waits for its months before returning.
    public static let ensureTimeout: Duration = .seconds(1)
    /// How often the idle worker wakes to check max ages and inventory.
    public static let backstopTick: Duration = .seconds(60)
    /// Outer-band pacing: after an outer chunk, the next one waits this
    /// multiple of the fetch time (at least the minimum gap). Never skipped
    /// — under Low Power Mode or thermal pressure the outer years still
    /// fill, just slower; `maxOuterGap` bounds how slow.
    public static let outerDutyCycle = 2.0
    public static let lowPowerDutyCycle = 10.0
    public static let lowPowerMinGap: Duration = .seconds(2)
    public static let thermalDutyCycle = 30.0
    public static let thermalMinGap: Duration = .seconds(15)
    public static let maxOuterGap: Duration = .seconds(60)
    /// A failed chunk is retried after this, doubling up to `retryMax`.
    public static let retryBase: Duration = .seconds(5)
    public static let retryMax: Duration = .seconds(10 * 60)
}

/// The values `SyncCoordinator` actually runs with — defaults from
/// `SyncHorizons`/`SyncTiming`; tests inject their own.
public struct SyncPolicy: Sendable {
    public var visiblePaddingMonths = SyncHorizons.visiblePaddingMonths
    public var nearMonths = SyncHorizons.nearMonths
    public var midMonths = SyncHorizons.midMonths
    public var farMonths = SyncHorizons.farMonths

    public var changeDebounce = SyncTiming.changeDebounce
    public var nearMaxAge = SyncTiming.nearMaxAge
    public var farMaxAge = SyncTiming.farMaxAge
    public var outerEveryNChunks = SyncTiming.outerEveryNChunks
    public var batchGrowBelow = SyncTiming.batchGrowBelow
    public var batchShrinkAbove = SyncTiming.batchShrinkAbove
    public var maxMonthsPerQuery = SyncTiming.maxMonthsPerQuery
    public var tombstoneTTL = SyncTiming.tombstoneTTL
    public var ensureTimeout = SyncTiming.ensureTimeout
    public var backstopTick = SyncTiming.backstopTick
    public var outerDutyCycle = SyncTiming.outerDutyCycle
    public var lowPowerDutyCycle = SyncTiming.lowPowerDutyCycle
    public var lowPowerMinGap = SyncTiming.lowPowerMinGap
    public var thermalDutyCycle = SyncTiming.thermalDutyCycle
    public var thermalMinGap = SyncTiming.thermalMinGap
    public var maxOuterGap = SyncTiming.maxOuterGap
    public var retryBase = SyncTiming.retryBase
    public var retryMax = SyncTiming.retryMax

    public init() {}

    public static let `default` = SyncPolicy()

    /// How long the next outer chunk waits after one took `fetch` seconds.
    func outerGap(afterFetch fetch: TimeInterval, pacing: SyncPacing) -> TimeInterval {
        let (cycle, minimum): (Double, TimeInterval)
        switch pacing {
        case .normal: (cycle, minimum) = (outerDutyCycle, 0)
        case .lowPower: (cycle, minimum) = (lowPowerDutyCycle, lowPowerMinGap.timeInterval)
        case .thermal: (cycle, minimum) = (thermalDutyCycle, thermalMinGap.timeInterval)
        }
        return min(maxOuterGap.timeInterval, max(minimum, fetch * cycle))
    }
}

/// What the machine allows right now — read before every outer chunk.
public struct SyncConditions: Sendable, Equatable {
    public var isLowPower: Bool
    public var thermal: ProcessInfo.ThermalState

    public init(isLowPower: Bool = false, thermal: ProcessInfo.ThermalState = .nominal) {
        self.isLowPower = isLowPower
        self.thermal = thermal
    }

    public static func current() -> SyncConditions {
        SyncConditions(isLowPower: ProcessInfo.processInfo.isLowPowerModeEnabled,
                       thermal: ProcessInfo.processInfo.thermalState)
    }

    public var pacing: SyncPacing {
        if thermal == .serious || thermal == .critical { return .thermal }
        return isLowPower ? .lowPower : .normal
    }
}

/// How fast the outer bands fill.
public enum SyncPacing: String, Sendable, Equatable {
    case normal, lowPower, thermal
}

extension Duration {
    var timeInterval: TimeInterval {
        let parts = components
        return TimeInterval(parts.seconds) + TimeInterval(parts.attoseconds) / 1e18
    }
}
