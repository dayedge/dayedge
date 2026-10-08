import Foundation
import Observation
import SwiftUI
import Domain
import UI

extension AgendaScrollCoordinator {
    // swiftlint:disable:next function_parameter_count - a scroll request and its callbacks; labelled at the one call site
    package func handleScrollRequest(
        _ target: AgendaScrollTarget,
        nowPresentation: AgendaNowPresentation?,
        isActive: Bool,
        proxy: ScrollViewProxy,
        onKeyboardSelection: @escaping (AgendaSelection?) -> Void,
        onScrollPrepared: @escaping (AgendaScrollTarget) -> Void
    ) {
        navigationTask?.cancel()
        navigationTask = nil
        // A programmatic jump can land somewhere unrelated to whatever
        // the visible edges were before it — without this reset, the
        // next real user scroll's direction check would compare against
        // a stale, no-longer-meaningful baseline from before the jump.
        previousFirstVisibleDay = nil
        previousLastVisibleDay = nil
        keyboardAnchor = nil
        onKeyboardSelection(nil)
        activeProgrammaticID = target.requestID
        isProgrammaticScroll = true

        if store.isLoaded(target.date),
           let anchor = AgendaSectionProjection.anchor(for: target, in: sections, nowPresentation: nowPresentation, tasks: { [taskIndex] in taskIndex.tasks(on: $0) }) {
            if target.nowTarget != nil {
                // The synthetic marker is introduced by the same state
                // update as this request. Give the lazy stack one pass to
                // register its new ID before asking ScrollViewReader for it.
                navigationTask = Task { @MainActor in
                    await Task.yield()
                    guard !Task.isCancelled, self.activeProgrammaticID == target.requestID else { return }
                    self.issueScroll(
                        to: anchor,
                        requestID: target.requestID,
                        animated: target.animated && isActive,
                        proxy: proxy
                    )
                    onScrollPrepared(target)
                }
            } else {
                issueScroll(to: anchor, requestID: target.requestID, animated: target.animated && isActive, proxy: proxy)
                onScrollPrepared(target)
            }
            selectNavigatedItem(anchor, onKeyboardSelection: onKeyboardSelection)
            return
        }

        navigationTask = Task { @MainActor in
            await self.store.ensureLoaded(covering: target.date)
            guard !Task.isCancelled, self.activeProgrammaticID == target.requestID else { return }
            // Let the lazy stack receive the newly inserted exact-day anchor.
            await Task.yield()
            guard !Task.isCancelled,
                  let anchor = AgendaSectionProjection.anchor(
                      for: target, in: self.sections, nowPresentation: nowPresentation,
                      tasks: { [taskIndex = self.taskIndex] in taskIndex.tasks(on: $0) }
                  ) else {
                self.finishProgrammaticScroll(requestID: target.requestID)
                onScrollPrepared(target)
                return
            }
            self.issueScroll(to: anchor, requestID: target.requestID, animated: target.animated && isActive, proxy: proxy)
            onScrollPrepared(target)
            self.selectNavigatedItem(anchor, onKeyboardSelection: onKeyboardSelection)
        }
    }

    /// A navigated-to event or task (occurrence navigation, "Show in
    /// Calendar" from Tasks or search) arrives selected, so ↑ / ↓, Return
    /// and Space carry on from it.
    private func selectNavigatedItem(_ anchor: AgendaScrollAnchor, onKeyboardSelection: (AgendaSelection?) -> Void) {
        switch anchor {
        case .task(let sectionID, let taskID):
            keyboardAnchor = anchor
            onKeyboardSelection(.task(AgendaTaskSelection(date: sectionID, taskID: taskID)))
        case .event:
            guard let selection = selection(for: anchor) else { return }
            keyboardAnchor = anchor
            onKeyboardSelection(selection)
        default:
            return
        }
    }

    package func moveOneEvent(
        _ direction: VerticalNavigationDirection,
        proxy: ScrollViewProxy,
        onKeyboardSelection: (AgendaSelection?) -> Void
    ) {
        let anchors = itemAnchorsInOrder
        guard !anchors.isEmpty else { return }

        let reference = keyboardAnchor
            ?? visibleAnchors.first(where: \.isItem)

        let targetIndex: Int
        if let reference, let currentIndex = anchors.firstIndex(of: reference) {
            targetIndex = direction == .up
                ? max(currentIndex - 1, 0)
                : min(currentIndex + 1, anchors.count - 1)
        } else if let visibleDay = visibleAnchors.first?.sectionID {
            let indices = anchors.indices.filter { anchors[$0].sectionID == visibleDay }
            switch direction {
            case .up: targetIndex = indices.first.map { max($0 - 1, 0) } ?? 0
            case .down: targetIndex = indices.first ?? 0
            }
        } else {
            targetIndex = direction == .up ? 0 : anchors.count - 1
        }

        select(anchors[targetIndex], proxy: proxy, onKeyboardSelection: onKeyboardSelection)
    }

    /// Space: completes the keyboard-selected task and moves selection to
    /// what now sits in its place (the next item, else the previous one).
    /// False when no task is selected.
    @discardableResult
    package func completeSelectedTask(
        proxy: ScrollViewProxy,
        complete: (String) -> Void,
        onKeyboardSelection: (AgendaSelection?) -> Void
    ) -> Bool {
        guard case .task(let sectionID, let taskID)? = keyboardAnchor, let removed = keyboardAnchor else { return false }
        // A later occurrence of a repeating task can't be completed.
        guard !taskIndex.tasks(on: sectionID).projectedIDs.contains(taskID) else { return true }
        let successor = SelectionSuccessor.after(removing: removed, in: itemAnchorsInOrder)
        complete(taskID)
        if let successor {
            select(successor, proxy: proxy, onKeyboardSelection: onKeyboardSelection)
        } else {
            keyboardAnchor = nil
            onKeyboardSelection(nil)
        }
        return true
    }

    /// A task completed by mouse: if it was the keyboard selection, the
    /// selection moves on the same way as with Space.
    package func taskCompleted(_ taskID: String, in sectionID: Date, proxy: ScrollViewProxy,
                               complete: (String) -> Void, onKeyboardSelection: (AgendaSelection?) -> Void) {
        if keyboardAnchor == .task(sectionID: sectionID, taskID: taskID) {
            completeSelectedTask(proxy: proxy, complete: complete, onKeyboardSelection: onKeyboardSelection)
        } else {
            complete(taskID)
        }
    }

    private func select(_ target: AgendaScrollAnchor, proxy: ScrollViewProxy, onKeyboardSelection: (AgendaSelection?) -> Void) {
        keyboardAnchor = target
        onKeyboardSelection(selection(for: target))
        let requestID = UUID()
        activeProgrammaticID = requestID
        isProgrammaticScroll = true
        issueScroll(to: target, requestID: requestID, animated: true, proxy: proxy)
    }

    func selection(for anchor: AgendaScrollAnchor) -> AgendaSelection? {
        switch anchor {
        case .event(let sectionID, let eventID):
            guard let section = sections.first(where: { $0.id == sectionID }),
                  let event = section.events.first(where: { $0.id == eventID }) else { return nil }
            return .event(AgendaKeyboardSelection(date: section.date, event: event))
        case .task(let sectionID, let taskID):
            return .task(AgendaTaskSelection(date: sectionID, taskID: taskID))
        case .day, .now:
            return nil
        }
    }

    private func issueScroll(
        to anchor: AgendaScrollAnchor,
        requestID: UUID,
        animated: Bool,
        proxy: ScrollViewProxy
    ) {
        let unitPoint: UnitPoint = {
            switch anchor {
            case .day: .top
            case .event, .task: .center
            // Month is a compact multi-day list, not an hour grid. Keeping
            // Now one-third down can expose yesterday above today's header
            // when the marker is today's first row. Put the marker at the
            // top instead, which pins TODAY and never leaks a prior section
            // into the initial orientation. Day's real timeline retains its
            // one-third positioning independently.
            case .now: UnitPoint(x: 0.5, y: 0.1)
            }
        }()

        if animated {
            withAnimation(.smooth(duration: 0.35)) {
                proxy.scrollTo(anchor, anchor: unitPoint)
            }
            navigationTask = Task { @MainActor in
                do {
                    try await Task.sleep(nanoseconds: 450_000_000)
                } catch {
                    return
                }
                self.finishProgrammaticScroll(requestID: requestID)
            }
        } else {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                proxy.scrollTo(anchor, anchor: unitPoint)
            }
            finishProgrammaticScroll(requestID: requestID)
        }
    }

    private func finishProgrammaticScroll(requestID: UUID) {
        guard activeProgrammaticID == requestID else { return }
        activeProgrammaticID = nil
        isProgrammaticScroll = false
    }

    /// Keyboard order: the same rows the list renders (all-day events stay
    /// out, as before), so ↑ / ↓ always walk what is on screen.
    private var itemAnchorsInOrder: [AgendaScrollAnchor] {
        sections.flatMap { section in
            let now = nowPresentation.flatMap { Calendar.autoupdatingCurrent.isDate($0.day, inSameDayAs: section.date) ? $0 : nil }
            return AgendaSectionProjection.itemAnchors(in: AgendaSectionProjection.rows(
                section: section, tasks: taskIndex.tasks(on: section.date), nowPresentation: now
            ))
        }
    }
}
