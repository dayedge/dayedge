import Foundation
import Observation
import SwiftUI
import Domain
import UI

/// Owns `AgendaListView`'s scroll bookkeeping — request IDs, active
/// programmatic navigation, cancellation, keyboard-selection anchoring,
/// and visible-day reporting — split out of that view for the same
/// reason `EventDetailCoordinator`/`AgendaNavigationCoordinator` were
/// split out of `RootView`.
///
/// Every callback here (`onCurrentSectionChange`/`onKeyboardSelection`/
/// `onScrollPrepared`), along with `nowPresentation`/`isActive`, is passed
/// as a parameter at the point of use rather than captured once at
/// `init` — all four are plain `var`/`let` properties on `AgendaListView`
/// itself, freshly supplied by `RootView` on every render, not
/// stable identities this coordinator could safely hold onto across its
/// own longer lifetime (a `View` struct's `init` reruns on every render;
/// a closure captured there once would be frozen to whichever render
/// happened to construct this `@State` box).
@MainActor
@Observable
package final class AgendaScrollCoordinator {
    let store: AgendaSectionStore

    package internal(set) var isProgrammaticScroll: Bool
    package internal(set) var keyboardAnchor: AgendaScrollAnchor?
    package internal(set) var visibleAnchors: [AgendaScrollAnchor] = []
    /// Kept current by `AgendaListView`; the keyboard order depends on both.
    @ObservationIgnored package var taskIndex: ScheduledTaskIndex = .empty
    @ObservationIgnored package var nowPresentation: AgendaNowPresentation?
    /// The reader is scrolling: a gesture (SwiftUI's scroll phase) or the
    /// scroll bar's knob/track (`scrollerTrackingChanged`).
    private var isGestureScrolling = false
    private var isScrollerTracking = false
    var isUserScrolling: Bool { isGestureScrolling || isScrollerTracking }
    var activeProgrammaticID: UUID?
    var navigationTask: Task<Void, Never>?

    /// The first/last rendered section's date the last time a
    /// content-edge-triggered (not date-threshold-triggered) load was
    /// attempted from there — lets `considerTopPaging`/`considerBottomPaging`
    /// tell "still sitting at the same edge because the last chunk had no
    /// events" apart from "genuinely arrived at this edge," without which
    /// the former would retry forever. See `visibilityChanged`.
    var lastTopPagingContentDate: Date?
    var lastBottomPagingContentDate: Date?
    /// Kept (and internal, not private) for test determinism
    /// (`await coordinator.topPagingTask?.value`), not to coalesce
    /// rapid-fire calls — `AgendaSectionStore`'s own `inFlightRanges`
    /// already dedupes those.
    package internal(set) var topPagingTask: Task<Void, Never>?
    /// How many post-prepend position corrections ran (tests).
    @ObservationIgnored package internal(set) var topScrollCorrections = 0
    package internal(set) var bottomPagingTask: Task<Void, Never>?

    /// The previous call's leading/trailing visible day — lets
    /// `considerTopPaging`/`considerBottomPaging` tell "the visible edge
    /// is actually moving toward the past/future" apart from merely
    /// "currently within the threshold distance of it," which the
    /// initial position alone can already satisfy (see
    /// `considerTopPaging`'s doc comment).
    var previousFirstVisibleDay: Date?
    var previousLastVisibleDay: Date?
    /// The last visibility report's `isActive`, for the re-check after a load.
    var isListActive = false
    /// True from the moment a top-edge load starts until the corrective
    /// re-scroll (see `considerTopPaging`) has actually been issued —
    /// distinct from `store.isLoadingAtTop`, which turns `false` as soon
    /// as the fetch itself finishes, before that correction has run.
    var isRestoringTopScrollPosition = false

    package init(store: AgendaSectionStore, scrollTarget: AgendaScrollTarget?) {
        self.store = store
        isProgrammaticScroll = scrollTarget != nil
    }

    var sections: [AgendaDaySection] { store.sections }

    package func cancelNavigation() {
        navigationTask?.cancel()
        navigationTask = nil
        topPagingTask?.cancel()
        topPagingTask = nil
        bottomPagingTask?.cancel()
        bottomPagingTask = nil
        // If the view disappears mid-restoration (Month hidden behind
        // Day), cancelling the task alone would leave this stuck `true`
        // forever, permanently blocking top-paging/reporting once Month
        // becomes active again.
        isRestoringTopScrollPosition = false
        previousFirstVisibleDay = nil
        previousLastVisibleDay = nil
    }

    /// `.onAppear` when there's no initial `scrollTarget`.
    package func clearProgrammaticFlagIfNoTarget() {
        isProgrammaticScroll = false
    }

    package func scrollPhaseChanged(isTracking: Bool) {
        isGestureScrolling = isTracking
    }

    /// Dragging the scroll bar's knob (or clicking its track) is the
    /// reader scrolling too — SwiftUI just reports no phase for it. When it
    /// ends, the last position is checked once more: a report that arrived
    /// right after the drag (or a single track click) still pages and
    /// moves the month grid.
    package func scrollerTrackingChanged(_ isTracking: Bool, proxy: ScrollViewProxy?, onCurrentSectionChange: @escaping (Date) -> Void) {
        isScrollerTracking = isTracking
        guard !isTracking else { return }
        Task { @MainActor in
            await Task.yield()
            guard self.isListActive, !self.isProgrammaticScroll else { return }
            self.recheckPagingAfterLoad(proxy: proxy)
            self.reportCurrentSection(Set(self.visibleAnchors.map(\.sectionID)), onCurrentSectionChange: onCurrentSectionChange)
        }
    }
}
