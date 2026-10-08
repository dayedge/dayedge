import Foundation
import Observation

/// What the footer's indexing indicator shows: whether the local calendar
/// index is refreshing, and how far it's got. Fed by `CalendarIndexRuntime`.
///
/// The indicator itself is gentle: it appears only when a refresh outlasts
/// `revealDelay` (quick near-month refreshes never flash it) and, once up,
/// stays at least `minimumVisible` so it never blinks.
@MainActor
@Observable
package final class CalendarIndexActivity {
    package enum Pacing: Equatable {
        case normal, lowPower, thermal
    }

    package private(set) var isIndexing = false
    package private(set) var isIndicatorVisible = false
    package private(set) var coveredChunks = 0
    package private(set) var totalChunks = 0
    package private(set) var pacing: Pacing = .normal
    /// Visible and near months are current; only further years remain.
    package private(set) var isNearReady = false
    /// The user paused filling the other years (the indicator stays up so
    /// they can resume).
    package private(set) var isPaused = false

    /// Calendar access as the index last saw it.
    package private(set) var hasAccess = true
    /// The usual location couldn't be opened: this launch uses a temporary
    /// index that isn't kept.
    package var isTemporary = false
    /// No index could be opened at all.
    package var isUnavailable = false
    /// Reindex asked for, until the visible and near months are back.
    package private(set) var isReindexing = false
    /// Calendar access came back after a revocation (which erased the
    /// index): "Updating calendars…" until the near months are back.
    package private(set) var isRefilling = false

    /// Set by `CalendarIndexRuntime`: pauses or resumes the index.
    @ObservationIgnored package var onSetPaused: ((Bool) -> Void)?
    /// Set by `CalendarIndexRuntime`: erases and rebuilds the index.
    @ObservationIgnored package var onReindex: (() -> Void)?
    /// Set by `CalendarIndexRuntime`: the database's size on disk, in bytes.
    @ObservationIgnored package var measureSize: (() -> Int64?)?
    /// Last measured size on disk (database, WAL and shared memory).
    package private(set) var databaseSize: Int64?

    package func refreshSize() {
        databaseSize = measureSize?()
    }

    /// Settings → Calendars › Index.
    package enum Status: Equatable {
        case upToDate
        case indexing
        case paused
        case noAccess
        case temporary
        case unavailable
    }

    package var status: Status {
        if isUnavailable { return .unavailable }
        if !hasAccess { return .noAccess }
        if isPaused { return .paused }
        if isIndexing || isReindexing { return .indexing }
        if isTemporary { return .temporary }
        return .upToDate
    }

    @ObservationIgnored private let revealDelay: Duration
    @ObservationIgnored private let minimumVisible: Duration
    @ObservationIgnored private var revealTask: Task<Void, Never>?
    @ObservationIgnored private var hideTask: Task<Void, Never>?
    @ObservationIgnored private var shownAt: ContinuousClock.Instant?

    package init(revealDelay: Duration = .milliseconds(600), minimumVisible: Duration = .milliseconds(900)) {
        self.revealDelay = revealDelay
        self.minimumVisible = minimumVisible
    }

    /// The footer button is up while filling (after the reveal delay) or
    /// paused.
    package var showsIndicator: Bool { isIndicatorVisible || isPaused }

    /// 0…1, nil before the first count arrives.
    package var fraction: Double? {
        totalChunks > 0 ? min(1, Double(coveredChunks) / Double(totalChunks)) : nil
    }

    /// The indicator's button: pause while filling, resume while paused.
    package func togglePause() {
        isPaused.toggle()
        onSetPaused?(isPaused)
    }

    package func reindex() {
        guard !isReindexing, let onReindex else { return }
        isReindexing = true
        onReindex()
    }

    /// The index was erased: progress starts over.
    package func didReset() {
        isPaused = false
        coveredChunks = 0
        totalChunks = 0
    }

    package func update(hasAccess: Bool) {
        self.hasAccess = hasAccess
    }

    package func update(isIndexing: Bool, coveredChunks: Int, totalChunks: Int, pacing: Pacing, isPaused: Bool? = nil) {
        if let isPaused { self.isPaused = isPaused }
        if totalChunks > 0 {
            self.coveredChunks = coveredChunks
            self.totalChunks = totalChunks
        }
        self.pacing = pacing
        guard isIndexing != self.isIndexing else { return }
        self.isIndexing = isIndexing
        if isIndexing {
            isNearReady = false
            hideTask?.cancel()
            guard !isIndicatorVisible else { return }
            revealTask?.cancel()
            revealTask = Task { [weak self, revealDelay] in
                try? await Task.sleep(for: revealDelay)
                guard let self, !Task.isCancelled, self.isIndexing else { return }
                self.isIndicatorVisible = true
                self.shownAt = .now
            }
        } else {
            revealTask?.cancel()
            guard isIndicatorVisible else { return }
            let remaining = shownAt.map { minimumVisible - (.now - $0) } ?? .zero
            hideTask = Task { [weak self] in
                if remaining > .zero { try? await Task.sleep(for: remaining) }
                guard let self, !Task.isCancelled, !self.isIndexing else { return }
                self.isIndicatorVisible = false
            }
        }
    }

    package func nearReady() {
        isNearReady = true
        isReindexing = false
        isRefilling = false
    }

    package func beginRefill() {
        isRefilling = true
        isNearReady = false
    }
}
