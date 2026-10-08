import SwiftUI
import Domain
import UI

package struct DayCellView: View {
    @Environment(\.themePalette) private var theme

    package let model: DayCellModel
    package let isSelected: Bool
    /// Holiday on a work day: gets the subtle number tint. Weekend
    /// holidays keep their weekend styling.
    package var isMarkedHoliday = false
    /// List color of the day's first open task; nil when there is none.
    package var taskColor: Color?
    package var onPress: () -> Void = {}
    package var onCancel: () -> Void = {}
    package let onTap: (Date) -> Void

    /// Whether *this* cell's glance popover should be showing — computed
    /// and owned entirely by `MonthGridView` (see its doc comment). This
    /// cell reports hover in and out; it never decides timing itself.
    package var isShowingGlance: Binding<Bool>
    package let eventsProvider: (Date) -> [AgendaEventModel]
    package var onHoverEnter: () -> Void = {}
    package var onHoverExit: () -> Void = {}
    package var onGlanceHoverChange: (Bool) -> Void = { _ in }

    /// Visual feedback at mouse-down, ahead of `onTap` firing on release —
    /// without this there's no reaction at all until the full selection +
    /// scroll round trip completes.
    @State private var isPressed = false

    private var numberColor: Color {
        if isSelected { return theme.selectedDayText }
        if model.isToday { return theme.todayText }
        if !model.isCurrentMonth { return theme.dimmedText }
        if model.isWeekend { return theme.weekendDayTint }
        if isMarkedHoliday { return theme.holidayTint }
        return theme.primaryText
    }

    /// Sized against the full row height (not just the number glyph) so it
    /// reads as a near-edge-to-edge highlight, matching the reference's
    /// "2px margin top/bottom" look rather than a tight circle hugging the
    /// digits.
    private var circleDiameter: CGFloat {
        AppTheme.Metrics.dayCellHeight
    }

    package var body: some View {
        VStack(spacing: 0) {
            ZStack {
                // Keep the highlight and the larger digit on one explicit
                // center. Moving this pair as a unit avoids separate offset
                // rounding making the circle look slightly off-axis.
                if isSelected {
                    ThemedSurface(role: .selection, fill: theme.selectedDayFill, shape: Circle())
                        .frame(width: circleDiameter, height: circleDiameter)
                } else if model.isToday {
                    Circle()
                        .fill(theme.todayFill)
                        .frame(width: circleDiameter, height: circleDiameter)
                }

                Text("\(model.dayNumber)")
                    .font(AppTheme.TextStyle.dayNumber)
                    .foregroundStyle(numberColor)
            }
            .frame(width: 18, height: 18)
            .offset(y: 1)

            EventDotsView(markers: DayMarkerLayout.markers(dots: model.dots, taskColor: taskColor))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .scaleEffect(isPressed ? 0.94 : 1)
        .animation(.easeOut(duration: 0.08), value: isPressed)
        .gesture(
            // Replaces `onTapGesture` so mouse-down feedback (the scale
            // above) can show immediately, independent of `onTap` itself
            // still committing on release — dragging off the cell before
            // releasing cancels the tap, same as a plain tap gesture would.
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard !isPressed else { return }
                    isPressed = true
                    onPress()
                }
                .onEnded { value in
                    isPressed = false
                    if abs(value.translation.width) + abs(value.translation.height) < 4 {
                        onTap(model.date)
                    } else {
                        onCancel()
                    }
                }
        )
        .onHover { hovering in
            if hovering { onHoverEnter() } else { onHoverExit() }
        }
        // Cells are kept by grid slot: a press never carries over to the
        // day that takes the slot when the month changes.
        .onChange(of: model.date) { _, _ in isPressed = false }
        .popover(isPresented: isShowingGlance, arrowEdge: .top) {
            DayGlanceView(
                date: model.date,
                events: eventsProvider(model.date),
                isToday: model.isToday,
                onHoverChange: onGlanceHoverChange
            )
        }
    }
}
