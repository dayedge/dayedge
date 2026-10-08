import Foundation

/// A window of positions in a long list that a lazy stack renders — paged
/// like the Month agenda: it opens around where reading starts, grows a page
/// as the reader nears either end, and trims the far side past a limit. A
/// `LazyVStack` keeps every row it has built while that row is in its
/// `ForEach`; only leaving the window frees it, so the window is what
/// bounds memory.
package struct ListWindowPaging {
    /// Positions rendered before and after where the list opens.
    package let openingBefore: Int
    package let openingAfter: Int
    /// Positions added at an edge at a time.
    package let page: Int
    /// The window grows once the visible positions come this close to its edge.
    package let threshold: Int
    /// The most positions rendered: past this, the far side is trimmed back
    /// to `trimmedTo` around what's on screen.
    package let limit: Int
    package let trimmedTo: Int

    /// Where the list opens: around `anchor`.
    package func opening(at anchor: Int?, count: Int) -> Range<Int> {
        guard count > 0 else { return 0..<0 }
        let anchor = min(max(anchor ?? 0, 0), count - 1)
        return max(0, anchor - openingBefore)..<min(count, anchor + openingAfter)
    }

    /// The window once `visible` positions are on screen — grown toward the
    /// edge they're near (and trimmed on the far side past `limit`); nil
    /// when it stays as it is.
    package func paged(_ window: Range<Int>, visible: ClosedRange<Int>, count: Int) -> Range<Int>? {
        var lower = window.lowerBound, upper = window.upperBound
        if visible.lowerBound - lower < threshold, lower > 0 {
            lower = max(0, lower - page)
            if upper - lower > limit { upper = max(visible.upperBound + 1, lower + trimmedTo) }
        } else if upper - 1 - visible.upperBound < threshold, upper < count {
            upper = min(count, upper + page)
            if upper - lower > limit { lower = min(visible.lowerBound, upper - trimmedTo) }
        }
        let next = lower..<upper
        return next == window ? nil : next
    }

    /// A window that shows `position` — the same one when it already does,
    /// otherwise one opened around it.
    package func showing(_ position: Int, in window: Range<Int>, count: Int) -> Range<Int> {
        window.contains(position) ? window : opening(at: position, count: count)
    }
}

/// Which result days the Search view renders (positions in
/// `SearchIndex.days`). So a query matching years of days ("daily") never
/// builds years of sections and rows — nor scrolls across them to open at
/// today. Unlike the agenda, nothing is fetched to page: the index already
/// knows every day, so moving the window is immediate.
package enum SearchDayPaging {
    /// The agenda's 7 behind, 21 ahead; result days are fuller than calendar
    /// days ("daily": several on almost every one), so a tighter limit than
    /// the agenda's 160.
    package static let paging = ListWindowPaging(openingBefore: 7, openingAfter: 21, page: 30, threshold: 7,
                                         limit: 90, trimmedTo: 60)

    package static var openingBefore: Int { paging.openingBefore }
    package static var openingAfter: Int { paging.openingAfter }
    package static var page: Int { paging.page }
    package static var threshold: Int { paging.threshold }
    package static var limit: Int { paging.limit }
    package static var trimmedTo: Int { paging.trimmedTo }

    package static func opening(at anchor: Int?, dayCount: Int) -> Range<Int> {
        paging.opening(at: anchor, count: dayCount)
    }

    package static func paged(_ window: Range<Int>, visible: ClosedRange<Int>, dayCount: Int) -> Range<Int>? {
        paging.paged(window, visible: visible, count: dayCount)
    }

    package static func showing(_ day: Int, in window: Range<Int>, dayCount: Int) -> Range<Int> {
        paging.showing(day, in: window, count: dayCount)
    }
}

/// Which rows of a conversation the Ask transcript renders (positions in
/// its rows, newest first): it opens on the newest answers and pages down
/// into older ones as the reader scrolls. Measured: an agenda-sized answer
/// is ~50 rows and ~10 MB of built views, so a long conversation must not
/// keep them all.
package enum ChatTranscriptPaging {
    package static let paging = ListWindowPaging(openingBefore: 0, openingAfter: 80, page: 60, threshold: 15,
                                         limit: 200, trimmedTo: 120)

    /// The window after the rows changed by `delta` at the top (new
    /// messages, a streaming answer): pinned to the newest it grows with
    /// them; reading further down it shifts, so the same rows stay.
    package static func adjusted(_ window: Range<Int>, delta: Int, count: Int,
                                 followsTop: Bool, anchorShift: Int? = nil,
                                 visible: ClosedRange<Int>? = nil) -> Range<Int> {
        guard count > 0 else { return 0..<0 }
        if followsTop {
            return 0..<min(count, paging.limit, max(window.upperBound + delta, min(count, paging.openingAfter)))
        }
        let shift = anchorShift ?? delta
        let lower = min(max(window.lowerBound + shift, 0), count - 1)
        let upper = min(max(window.upperBound + shift, lower + 1), count)
        return bounded(lower..<upper, visible: visible, count: count)
    }

    package static func paged(_ window: Range<Int>, visible: ClosedRange<Int>, count: Int) -> Range<Int>? {
        let proposed = paging.paged(window, visible: visible, count: count) ?? window
        let next = bounded(proposed, visible: visible, count: count)
        return next == window ? nil : next
    }

    /// Keep the viewport even when unusually tiny rows let it show more than
    /// the normal limit. The exception is bounded by visible rows, not history.
    private static func bounded(_ window: Range<Int>, visible: ClosedRange<Int>?, count: Int) -> Range<Int> {
        let first = max(0, min(visible?.lowerBound ?? window.lowerBound, count - 1))
        let last = max(first, min(visible?.upperBound ?? first, count - 1))
        let width = min(count, max(paging.limit, last - first + 1))
        guard window.count > width || first < window.lowerBound || last >= window.upperBound else { return window }
        let lower = max(0, min(first - max(0, (width - (last - first + 1)) / 2), count - width))
        return lower..<(lower + width)
    }
}
