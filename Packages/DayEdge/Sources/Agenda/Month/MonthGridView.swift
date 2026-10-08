import SwiftUI
import Domain
import UI

package struct MonthGridView: View {
    @Environment(\.themePalette) private var theme

    package let days: [DayCellModel]
    package let selectedDate: Date
    package let onSelect: (Date) -> Void
    package let eventsProvider: (Date) -> [AgendaEventModel]
    package var isMarkedHoliday: (Date) -> Bool = { _ in false }
    /// List color for a day's open-task tick; nil for no tick.
    package var taskColor: (Date) -> Color? = { _ in nil }
    /// One label per grid row; empty hides them.
    package var weekNumbers: [Int] = []

    /// Mouse-down selection is deliberately local to the grid. Updating it
    /// does not wait for the shared calendar model, agenda loading, or a
    /// programmatic scroll, so the circle can appear on the very next frame.
    @State private var optimisticSelectedDate: Date?

    // MARK: - Hover "glance" timing
    //
    // All of it lives here, not in the 42 individual cells. Cells only
    // ever report `entered(date)`/`exited(date)` — every timer, and every
    // mutation of `presentedDate`, is owned by this single view. Splitting
    // timers across cells while they all mutated one shared date is what
    // caused the earlier "doesn't appear / appears late / closes
    // immediately" bugs: stale timers from cells the pointer had already
    // left could still fire, and a dismissal from a stale popover could
    // clear a different, newly-presented one's state.

    /// The day currently under the pointer, if any.
    @State private var hoveredDate: Date?
    /// The day whose glance popover is actually showing.
    @State private var presentedDate: Date?
    @State private var presentedAt: Date?
    @State private var isPointerInsidePopover = false
    @State private var openWorkItem: DispatchWorkItem?
    @State private var closeWorkItem: DispatchWorkItem?

    private static let hoverOpenDelay: TimeInterval = 1.2
    private static let dismissGracePeriod: TimeInterval = 0.25
    /// Right when a popover appears, AppKit can briefly (and wrongly)
    /// report the originating cell's hover as "exited" — a side effect of
    /// the window/focus change, not real mouse movement. A dismissal
    /// requested inside this window after presenting is rescheduled for
    /// whatever's left of it, rather than being dropped outright.
    private static let presentationSettleDuration: TimeInterval = 0.4

    private var displayedSelectedDate: Date {
        optimisticSelectedDate ?? selectedDate
    }

    /// Index (within the 42-cell grid) of the row that contains the
    /// selected day, so we can paint the horizontal highlight band behind it.
    private var selectedRowIndex: Int? {
        let calendar = Calendar.autoupdatingCurrent
        guard let index = days.firstIndex(where: { calendar.isDate($0.date, inSameDayAs: displayedSelectedDate) }) else { return nil }
        return index / 7
    }

    private var rowCount: Int { (days.count + 6) / 7 }

    private func cell(_ day: DayCellModel) -> some View {
        DayCellView(
            model: day,
            isSelected: Calendar.autoupdatingCurrent.isDate(day.date, inSameDayAs: displayedSelectedDate),
            isMarkedHoliday: isMarkedHoliday(day.date),
            taskColor: taskColor(day.date),
            onPress: {
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    optimisticSelectedDate = day.date
                }
            },
            onCancel: {
                optimisticSelectedDate = nil
            },
            onTap: { date in
                onSelect(date)
                dismissImmediately()
            },
            isShowingGlance: Binding(
                get: { presentedDate == day.date },
                set: { isShowing in if !isShowing { dismiss(owner: day.date) } }
            ),
            eventsProvider: eventsProvider,
            onHoverEnter: { handleEnter(day.date) },
            onHoverExit: { handleExit(day.date) },
            onGlanceHoverChange: { handleGlanceHover(day.date, $0) }
        )
    }

    package var body: some View {
        ZStack(alignment: .top) {
            if let rowIndex = selectedRowIndex {
                theme.selectedWeekBand
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .frame(height: AppTheme.Metrics.dayCellHeight)
                    .offset(y: CGFloat(rowIndex) * AppTheme.Metrics.dayCellHeight)
                    .transaction { $0.disablesAnimations = true }
            }

            // A plain grid, cells identified by their slot (0–41), not their
            // day: always all on screen, so laziness bought nothing — and with
            // dates as ids every month change (the agenda scrolling past one)
            // replaced all 42 cells; hundreds of old ones were found still
            // alive on the heap. Now a month change updates the same cells.
            VStack(spacing: 0) {
                ForEach(0..<rowCount, id: \.self) { row in
                    HStack(spacing: 0) {
                        ForEach(0..<7, id: \.self) { column in
                            let slot = row * 7 + column
                            if days.indices.contains(slot) {
                                cell(days[slot])
                                    .frame(maxWidth: .infinity)
                                    .frame(height: AppTheme.Metrics.dayCellHeight)
                            } else {
                                Color.clear
                                    .frame(maxWidth: .infinity)
                                    .frame(height: AppTheme.Metrics.dayCellHeight)
                            }
                        }
                    }
                }
            }
        }
        .padding(.horizontal, AppTheme.horizontalPadding)
        .padding(.top, 4)
        // Week numbers live in the grid's own left padding, so cell widths
        // and the selected-week band are unaffected.
        .overlay(alignment: .topLeading) {
            VStack(spacing: 0) {
                ForEach(Array(weekNumbers.enumerated()), id: \.offset) { _, number in
                    Text("\(number)")
                        .font(AppTheme.TextStyle.weekNumber)
                        .foregroundStyle(theme.dimmedText)
                        .frame(width: AppTheme.horizontalPadding - 4, height: AppTheme.Metrics.dayCellHeight, alignment: .trailing)
                }
            }
            .padding(.top, 4)
            .allowsHitTesting(false)
        }
        .onChange(of: selectedDate) { _, _ in
            optimisticSelectedDate = nil
        }
        .onExitCommand { dismissImmediately() }
    }

    private func handleEnter(_ date: Date) {
        hoveredDate = date
        closeWorkItem?.cancel()
        closeWorkItem = nil

        if presentedDate == date { return }

        openWorkItem?.cancel()

        if presentedDate != nil {
            // Already engaged with a glance elsewhere — move it to the
            // newly hovered day immediately instead of re-running the
            // full open delay.
            present(date)
            return
        }

        let workItem = DispatchWorkItem { present(date) }
        openWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.hoverOpenDelay, execute: workItem)
    }

    private func handleExit(_ date: Date) {
        // A stale exit from a cell the pointer has already moved past —
        // ignore it so it can't cancel state that belongs to whichever
        // cell is actually hovered now.
        guard hoveredDate == date else { return }
        hoveredDate = nil
        openWorkItem?.cancel()
        openWorkItem = nil
        scheduleCloseIfNeeded()
    }

    private func handleGlanceHover(_ date: Date, _ isInside: Bool) {
        // A late callback from a popover that's no longer the presented
        // one must not touch the current one's state.
        guard presentedDate == date else { return }
        isPointerInsidePopover = isInside
        if isInside {
            closeWorkItem?.cancel()
            closeWorkItem = nil
        } else {
            scheduleCloseIfNeeded()
        }
    }

    private func present(_ date: Date) {
        presentedDate = date
        presentedAt = Date()
    }

    /// Only clears `presentedDate` if `date` is still the one actually
    /// presented — a dismissal signal from a stale/previous popover must
    /// never close whichever one is showing now.
    private func dismiss(owner date: Date) {
        guard presentedDate == date else { return }
        presentedDate = nil
        presentedAt = nil
    }

    private func dismissImmediately() {
        openWorkItem?.cancel()
        closeWorkItem?.cancel()
        openWorkItem = nil
        closeWorkItem = nil
        hoveredDate = nil
        presentedDate = nil
        presentedAt = nil
        isPointerInsidePopover = false
    }

    private func scheduleCloseIfNeeded() {
        guard presentedDate != nil else { return }
        closeWorkItem?.cancel()

        let elapsedSincePresented = presentedAt.map { Date().timeIntervalSince($0) } ?? .infinity
        let settleRemaining = Self.presentationSettleDuration - elapsedSincePresented
        let delay = max(Self.dismissGracePeriod, settleRemaining)

        let workItem = DispatchWorkItem {
            if hoveredDate == nil, !isPointerInsidePopover {
                presentedDate = nil
                presentedAt = nil
            }
        }
        closeWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }
}
