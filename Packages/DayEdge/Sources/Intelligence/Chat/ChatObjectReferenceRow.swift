import SwiftUI
import Domain
import UI

/// How Chat finds the live objects its messages reference, and acts on
/// them — through the app's own data and task actions, never a copy.
@MainActor
package struct ChatObjectContext {
    /// The event occurrence with this id on this day, if it still exists.
    package let event: (_ id: String, _ day: Date) -> AgendaEventModel?
    package let taskActions: TaskActions
    /// Chat's own task-details presentation, apart from the calendar's.
    package let taskCoordinator: CalendarTaskCoordinator
    /// Opens a day in the calendar (Day view).
    package var showDay: (Date) -> Void = { _ in }
    package var calendar: Calendar = .autoupdatingCurrent

    package init(
        event: @escaping (_ id: String, _ day: Date) -> AgendaEventModel?,
        taskActions: TaskActions,
        taskCoordinator: CalendarTaskCoordinator,
        showDay: @escaping (Date) -> Void = { _ in },
        calendar: Calendar = .autoupdatingCurrent
    ) {
        self.event = event
        self.taskActions = taskActions
        self.taskCoordinator = taskCoordinator
        self.showDay = showDay
        self.calendar = calendar
    }
}

/// A referenced event or task, drawn by the same rows the agenda uses — in
/// their compact density — with their popovers, menus and actions. An
/// object that's gone shows its last known title, muted.
package struct ChatObjectReferenceRow: View {
    @Environment(\.timeFormat) private var timeFormat
    package let part: ChatContentPart
    package let objects: ChatObjectContext

    package var body: some View {
        switch part {
        case .event(let reference):
            if let event = objects.event(reference.id, reference.day) {
                AgendaEventRowView(event: event, date: reference.day, density: .compact)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(eventLabel(event))
            } else {
                MissingObjectRow(title: reference.snapshot.title, note: L10n.tr("chatobjectreferencerow.no.longer.in.your.calendar", "no longer in your calendar"), isTask: false)
            }
        case .task(let reference):
            if let task = objects.taskActions.task(reference.id) {
                CalendarTaskRowView(
                    task: task,
                    day: reference.day,
                    coordinator: objects.taskCoordinator,
                    isOverdue: !task.isCompleted && TaskBuckets.isOverdue(task, now: Date(), calendar: objects.calendar),
                    isProjected: isProjected(task, on: reference.day),
                    density: .compact,
                    onComplete: { _ = objects.taskActions.setCompleted(!task.isCompleted, taskID: task.id) }
                )
            } else {
                MissingObjectRow(title: reference.snapshot.title, note: L10n.tr("chatobjectreferencerow.no.longer.in.your.tasks", "no longer in your tasks"), isTask: true)
            }
        case .text, .day:
            EmptyView()
        }
    }

    /// A later occurrence of a repeating task (not its current one) can't
    /// be completed from here — same rule as the agenda.
    private func isProjected(_ task: TaskItem, on day: Date) -> Bool {
        guard task.isRecurring, let due = task.dueDate else { return false }
        return !objects.calendar.isDate(due, inSameDayAs: day)
    }

    private func eventLabel(_ event: AgendaEventModel) -> String {
        guard let start = event.startText(timeFormat), let end = event.endText(timeFormat) else { return L10n.tr(
            "chatobjectreferencerow.event.all.day", "Event, \(String(describing: event.title)), all day"
        ) }
        return L10n.tr("chatobjectreferencerow.event.to", "Event, \(String(describing: event.title)), \(String(describing: start)) to \(String(describing: end))")
    }
}

/// The last known title of an object that can't be found any more — never
/// an id, never an error.
private struct MissingObjectRow: View {
    @Environment(\.themePalette) private var theme

    let title: String
    let note: String
    let isTask: Bool

    var body: some View {
        HStack(alignment: .top, spacing: AppTheme.AgendaRow.markerToContent) {
            AgendaLeadingMarkerSlot {
                Circle()
                    .strokeBorder(theme.dimmedText, lineWidth: 1.5)
                    .frame(width: isTask ? AppTheme.Tasks.embeddedRingSize : 10,
                           height: isTask ? AppTheme.Tasks.embeddedRingSize : 10)
            }
            Text("\(title) · \(note)")
                .font(AppTheme.TextStyle.eventTitle)
                .foregroundStyle(theme.secondaryText)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
        }
        .padding(.leading, AppTheme.AgendaRow.leadingInset)
        .padding(.trailing, AppTheme.horizontalPadding)
        .padding(.vertical, AgendaRowDensity.compact.verticalPadding)
        .accessibilityElement(children: .combine)
    }
}
