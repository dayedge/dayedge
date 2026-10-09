import SwiftUI
import UI

/// The conversation, newest message first, right under the composer at
/// the top: user turns trailing in the app-blue bubbles, assistant turns
/// leading as bubble-less prose — with the events and tasks they refer to
/// drawn as the app's own rows.
///
/// One lazy list of small rows (`ChatTranscriptRows`), paged like the
/// agenda (`ChatTranscriptPaging`): only a window of rows around what's on
/// screen is in the list — a lazy stack keeps every row it has built while
/// it's there — so a long conversation scrolls, streams and weighs like a
/// short one. A new question brings the view back to the top; its answer
/// then appears above it, and nothing else scrolls by itself.
package struct ChatTranscriptView: View {
    package let messages: [ChatMessage]
    package let objects: ChatObjectContext
    /// The change waiting for approval, and Undo.
    package let approvals: ChatApprovals
    /// ⌘⌫ deletes only when it can't mean "delete text".
    package var isComposerEmpty = true
    /// Whether the jump-to-latest arrow shows; shared with the button.
    package let follow: ChatScrollFollow
    package var isActive = true

    @State private var position = ScrollPosition(edge: .top)
    @State private var rowCache = ChatTranscriptRowCache()
    /// The rows rendered (positions in the newest-first rows).
    @State private var window = 0..<ChatTranscriptPaging.paging.openingAfter
    /// Re-anchoring after rows above changed; reports meanwhile are ignored.
    @State private var anchors = ChatTranscriptScrollAnchors()

    private static let gaps = ChatTranscriptGaps(message: AppTheme.Chat.messageSpacing,
                                                 part: AppTheme.Chat.partSpacing,
                                                 dayToRows: AppTheme.Chat.dateContextToRows)

    package var body: some View {
        let rows = rowCache.rows(for: messages, gaps: Self.gaps, calendar: objects.calendar)
        // The approval card, if one waits: it belongs to the newest answer,
        // which is now at the top.
        let latestPendingID = rows.first { if case .pending(true) = $0.kind { true } else { false } }?.id
        ThemedScrollView(position: $position, edgeDissolve: .all,
                         topDissolve: AppTheme.ScrollEdge.tallHeader,
                         isDissolveActive: isActive, onMetricsChange: {
            follow.observe($0)
            anchors.observe(offset: $0.offset)
        }, onScrollerTracking: { tracking in
            if tracking { anchors.userScrolled() }
        }, content: {
            LazyVStack(alignment: .leading, spacing: 0) {
                let shown = window.clamped(to: rows.indices)
                ForEach(Array(rows[shown].enumerated()), id: \.element.id) { offset, row in
                    ChatTranscriptRowView(row: row, objects: objects, approvals: approvals,
                                          isComposerEmpty: row.id == latestPendingID ? isComposerEmpty : true)
                        .equatable()
                        .background {
                            ChatTranscriptRowAnchorProbe(id: row.id, position: shown.lowerBound + offset, anchors: anchors)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                }
            }
            // No side padding here: object rows span the width on the
            // agenda's marker geometry; prose and bubbles pad themselves.
            // The gaps live inside the scroll content, so content can still
            // pass under the floating bars.
            .scrollTargetLayout()
            .padding(.top, AppTheme.Chat.headerToContent)
            .padding(.bottom, 4)
        })
        .onScrollTargetVisibilityChange(idType: String.self, threshold: 0.01) { ids in
            visibilityChanged(ids, rows: rows)
        }
        // New rows arrive at the top (a question, a streaming answer).
        .onChange(of: rows.count) { old, new in
            rowsChanged(rows, delta: new - old)
        }
        // The user's own question: back to the top, where it now sits.
        .onChange(of: messages.count) { _, _ in
            if messages.last?.role == .user { scrollToLatest(animated: true) }
        }
        .onChange(of: follow.jumpRequests) { _, _ in scrollToLatest(animated: true) }
        .onDisappear { anchors.cancelRestoration() }
    }

    /// Rows on screen: the window pages near an edge — re-anchored on the
    /// top row when rows above changed.
    private func visibilityChanged(_ ids: [String], rows: [ChatTranscriptRow]) {
        guard !anchors.isRestoring else { return }
        anchors.rememberVisible()
        let shown = rows[window.clamped(to: rows.indices)]
        let positions = ids.compactMap { id in shown.firstIndex { $0.id == id } }
        guard let first = positions.min(), let last = positions.max(),
              let next = ChatTranscriptPaging.paged(window, visible: first...last, count: rows.count)
        else { return }
        let aboveChanged = next.lowerBound != window.lowerBound
        let anchor = anchors.snapshot   // just measured by rememberVisible()
        window = next
        if aboveChanged, let anchor { anchors.restore(anchor) }
    }

    private func rowsChanged(_ rows: [ChatTranscriptRow], delta: Int) {
        let anchor = anchors.snapshot
        let visibleIDs = Set(anchor?.visibleIDs ?? [])
        let positions = rows.enumerated().filter { visibleIDs.contains($0.element.id) }.map(\.offset)
        let visible = positions.first.flatMap { first in positions.last.map { first...$0 } }
        let anchorPosition = anchor.flatMap { saved in rows.firstIndex { $0.id == saved.id } }
        let shift = anchor.flatMap { saved in anchorPosition.map { $0 - saved.position } }
        let followsNewest = anchors.isAtTop && window.lowerBound == 0
        window = ChatTranscriptPaging.adjusted(window, delta: delta, count: rows.count,
                                              followsTop: followsNewest, anchorShift: shift, visible: visible)
        if !followsNewest, anchorPosition != nil, let anchor { anchors.restore(anchor) }
    }

    private func scrollToLatest(animated: Bool) {
        // The newest rows again: the window back where it opens.
        anchors.resetToTop()
        window = 0..<ChatTranscriptPaging.paging.openingAfter
        if animated {
            withAnimation(.easeOut(duration: 0.2)) { position.scrollTo(edge: .top) }
        } else {
            position.scrollTo(edge: .top)
        }
    }
}

/// Whether the jump-to-latest arrow shows: once the reader is well down
/// from the top (more than `jumpDistance` of the viewport), hidden again
/// near it. Only a flip is written, never every scroll tick.
@MainActor
@Observable
package final class ChatScrollFollow {
    package private(set) var showsJump = false
    /// Bumped by the jump button.
    package private(set) var jumpRequests = 0

    /// How far below the top (in viewports) the jump button appears; it
    /// hides again under half that, so it doesn't flicker at the edge.
    package static let jumpDistance: CGFloat = 0.75

    package func observe(_ metrics: ScrollMetrics) {
        let distance = metrics.offset
        let viewport = max(metrics.viewportHeight, 1)
        if !showsJump, distance > viewport * Self.jumpDistance {
            showsJump = true
        } else if showsJump, distance < viewport * Self.jumpDistance / 2 {
            showsJump = false
        }
    }

    /// The jump button: back to the newest message at the top.
    package func jumpToLatest() {
        showsJump = false
        jumpRequests += 1
    }
}
