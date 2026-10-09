import Foundation
import Observation
import SwiftUI
import Domain
import UI

extension AgendaScrollCoordinator {
    package func visibilityChanged(
        _ anchors: [AgendaScrollAnchor],
        isActive: Bool,
        proxy: ScrollViewProxy? = nil,
        onCurrentSectionChange: (Date) -> Void
    ) {
        visibleAnchors = anchors
        isListActive = isActive
        guard isActive, isUserScrolling, !isProgrammaticScroll else { return }

        let visibleDays = Set(anchors.map(\.sectionID))
        considerTopPaging(visibleDays, proxy: proxy)
        considerBottomPaging(visibleDays, proxy: proxy)
        reportCurrentSection(visibleDays, onCurrentSectionChange: onCurrentSectionChange)
    }

    func reportCurrentSection(_ visibleDays: Set<Date>, onCurrentSectionChange: (Date) -> Void) {
        // Still gated on the loading flags (and the restoration flag)
        // here specifically: a chunk merging in above/below the
        // viewport — or the corrective re-scroll that follows a top
        // merge — can make SwiftUI report a transient visible set that
        // isn't a real user position — reporting one of those as "the
        // current day" would make the month grid jump. Loading one edge
        // doesn't need to block *paging* the other (see the two methods
        // above), but it does need to pause this.
        guard !store.isLoadingAtTop, !store.isLoadingAtBottom, !isRestoringTopScrollPosition else { return }
        guard let date = sections.first(where: { visibleDays.contains($0.id) })?.date else { return }
        onCurrentSectionChange(date)
    }

    /// `afterLoad`: the re-check once a load finished — no new movement
    /// is needed (see `recheckPagingAfterLoad`).
    func considerTopPaging(_ visibleDays: Set<Date>, proxy: ScrollViewProxy?, afterLoad: Bool = false) {
        guard !store.isLoadingAtTop, !isRestoringTopScrollPosition, topPagingTask == nil,
              let firstVisible = visibleDays.min() else { return }

        // Only page toward the past while the visible top is actually
        // moving that way. Without this, the very first scroll tick in
        // *either* direction can look like "near the top edge," since
        // the initial window's own start sits exactly at the load
        // threshold (`agendaInitialWindowBehindDays` ==
        // `agendaEdgeLoadThresholdDays`, both 7 days) — i.e. today
        // already satisfies it at rest.
        let isMovingBackward = previousFirstVisibleDay.map { firstVisible < $0 } ?? false
        previousFirstVisibleDay = firstVisible
        guard isMovingBackward || afterLoad else { return }

        let contentTopDate = sections.first?.date
        let isAtContentTop = contentTopDate != nil && contentTopDate == firstVisible
        if isAtContentTop {
            // Don't retry forever from the same spot when a chunk turned
            // out to add nothing new (a stretch of the calendar with no
            // events) — only reattempt once the first rendered section
            // has actually moved since the last attempt made from here.
            guard contentTopDate != lastTopPagingContentDate else { return }
            lastTopPagingContentDate = contentTopDate
        }

        // Captured before the load — merging new sections in above the
        // viewport doesn't otherwise preserve scroll position, so
        // without re-anchoring to this after the merge, the view lands
        // wherever the raw content offset now happens to fall in the
        // taller content (the first event-bearing day in the newly
        // fetched chunk), which reads as a visible jump.
        // Nothing to load this far from the loaded top: don't start a
        // load-and-correct cycle at all. (Doing so snapped every newly
        // visible day's header to the top while scrolling back.)
        guard store.wouldLoadMore(nearTopOf: firstVisible, isAtLoadedContentEdge: isAtContentTop) else { return }

        let preservedAnchor = AgendaScrollAnchor.day(firstVisible)
        let topBefore = sections.first?.date
        topPagingTask = Task { @MainActor in
            await store.loadMoreIfNeeded(nearTopOf: firstVisible, isAtLoadedContentEdge: isAtContentTop)
            // Only block reporting from here — the fetch above doesn't
            // change what's visible, so it's safe to keep reporting the
            // real, unchanged position through it. Gating the *whole*
            // cycle (fetch included) made the month grid lag further and
            // further behind during sustained fast scrolling, since
            // chunk after chunk can fire back-to-back off an
            // already-warm cache with barely a gap between them.
            // Only a real prepend moves content; otherwise leave the
            // user's position exactly where it is.
            guard self.sections.first?.date != topBefore else {
                topPagingTask = nil
                recheckPagingAfterLoad(proxy: proxy)
                return
            }
            await restore(preservedAnchor, proxy: proxy)
            topPagingTask = nil
            recheckPagingAfterLoad(proxy: proxy)
        }
    }

    /// Content above the viewport changed (days prepended, or far days
    /// dropped): back to the day that was at the top, without animation.
    private func restore(_ anchor: AgendaScrollAnchor, proxy: ScrollViewProxy?) async {
        topScrollCorrections += 1
        isRestoringTopScrollPosition = true
        // Let the lazy stack register the changed day headers before
        // asking `ScrollViewReader` to scroll to one — same one-pass wait
        // `handleScrollRequest` uses elsewhere.
        await Task.yield()
        if let proxy {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                proxy.scrollTo(anchor, anchor: .top)
            }
        }
        isRestoringTopScrollPosition = false
    }

    func considerBottomPaging(_ visibleDays: Set<Date>, proxy: ScrollViewProxy?, afterLoad: Bool = false) {
        guard !store.isLoadingAtBottom, bottomPagingTask == nil, let lastVisible = visibleDays.max() else { return }

        // Mirrors `considerTopPaging`'s direction gate.
        let isMovingForward = previousLastVisibleDay.map { lastVisible > $0 } ?? false
        previousLastVisibleDay = lastVisible
        guard isMovingForward || afterLoad else { return }

        let contentBottomDate = sections.last?.date
        let isAtContentBottom = contentBottomDate != nil && contentBottomDate == lastVisible
        if isAtContentBottom {
            guard contentBottomDate != lastBottomPagingContentDate else { return }
            lastBottomPagingContentDate = contentBottomDate
        }
        guard store.wouldLoadMore(nearBottomOf: lastVisible, isAtLoadedContentEdge: isAtContentBottom) else { return }

        // Appending below doesn't move anything — but once the agenda is
        // over its limit, the same load drops far days above, and then the
        // view is re-anchored on the day at its top.
        let preservedAnchor = visibleDays.min().map(AgendaScrollAnchor.day)
        let topBefore = sections.first?.date
        bottomPagingTask = Task { @MainActor in
            await store.loadMoreIfNeeded(nearBottomOf: lastVisible, isAtLoadedContentEdge: isAtContentBottom)
            if let preservedAnchor, self.sections.first?.date != topBefore {
                await restore(preservedAnchor, proxy: proxy)
            }
            bottomPagingTask = nil
            recheckPagingAfterLoad(proxy: proxy)
        }
    }

    /// Visibility reported while a load was running is dropped (the load
    /// owns the edge). If that load — or the re-anchoring after it — left
    /// the view at an edge, nothing else would ask again: at the bottom of
    /// the content, scrolling on moves nothing, so no new report comes,
    /// and the agenda just stopped until the reader scrolled back a little.
    /// So once a load is done, the current position is checked once more.
    /// (A chunk that added nothing isn't retried from the same edge — the
    /// `last…PagingContentDate` guards.)
    func recheckPagingAfterLoad(proxy: ScrollViewProxy?) {
        guard isListActive, !isProgrammaticScroll, !isRestoringTopScrollPosition else { return }
        let visibleDays = Set(visibleAnchors.map(\.sectionID))
        guard !visibleDays.isEmpty else { return }
        considerTopPaging(visibleDays, proxy: proxy, afterLoad: true)
        considerBottomPaging(visibleDays, proxy: proxy, afterLoad: true)
    }
}
