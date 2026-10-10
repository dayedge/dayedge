import AppKit
import SwiftUI
import Domain
import UI

/// Settings › Tasks. Mirrors the Calendars pane: Reminders access, which
/// lists the app uses, then how they are shown.
struct TasksSettingsView: View {
    @Environment(\.themePalette) private var theme

    let repository: TaskRepository

    @AppStorage(TaskSettings.completedWindowKey) private var completedWindow = TaskSettings.defaultCompletedWindow
    @AppStorage(TaskSettings.showsInCalendarKey) private var showsInCalendar = true

    var body: some View {
        SettingsPane {
            accessGroup
            if repository.accessStatus == .granted {
                listsGroups
                displayGroup
                calendarGroup
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await repository.refreshAccess() }
        }
        .onChange(of: completedWindow) {
            Task { await repository.reloadIfCompletedWindowChanged() }
        }
    }

    // MARK: Access

    private var access: SourceAccessStatus { repository.accessStatus }

    private var accessGroup: some View {
        SettingsGroup(
            header: L10n.tr("taskssettingsview.access", "Access"),
            footer: access == .granted ? nil
                : L10n.tr(
                    "taskssettingsview.dayedge.needs.full.access.to.f8a770",
                    "DayEdge needs full access to Reminders to show and update your tasks. You can change this in System Settings › Privacy & Security › Reminders."
                )
        ) {
            SettingsRow(title: L10n.tr("taskssettingsview.reminders", "Reminders")) {
                HStack(spacing: 8) {
                    StatusDot(color: accessColor)
                    Text(access.title)
                        .font(.system(size: 12))
                        .foregroundStyle(theme.settings.secondaryText)
                    if let action = access.actionTitle {
                        Button(action) { Task { await repository.performAccessAction() } }
                            .controlSize(.small)
                    }
                }
            }
        }
    }

    private var accessColor: Color {
        switch access {
        case .granted: return theme.settings.granted
        case .denied: return theme.settings.denied
        case .notDetermined: return theme.settings.pending
        }
    }

    // MARK: Lists

    @ViewBuilder
    private var listsGroups: some View {
        if repository.listVisibility.allItems.isEmpty {
            SettingsGroup(header: L10n.tr(
                "taskssettingsview.lists", "Lists"
            ), footer: L10n.tr(
                "taskssettingsview.reminders.lists.will.appear.here", "Reminders lists will appear here."
            )) {
                SettingsRow(title: L10n.tr("taskssettingsview.no.lists.available", "No lists available")) { EmptyView() }
            }
        } else {
            SourceCheckboxGroups(
                store: repository.listVisibility,
                kind: .reminderList,
                title: L10n.tr("taskssettingsview.lists", "Lists"),
                footer: L10n.tr(
                    "taskssettingsview.dayedge.only.uses.the.selected.21c8e1",
                    "DayEdge only uses the selected lists. To hide them for a while, use the list menu at the bottom of Tasks."
                )
            )
        }
    }

    // MARK: Display

    private var showsAttention: Binding<Bool> {
        let store = repository.listVisibility
        let id = TaskSmartSection.attention.visibilityID
        return Binding(
            get: { !store.hiddenIDs.contains(id) },
            set: { shown in if shown == store.hiddenIDs.contains(id) { store.toggle(id) } }
        )
    }

    private var calendarGroup: some View {
        SettingsGroup(
            header: L10n.tr("taskssettingsview.calendar", "Calendar"),
            footer: L10n.tr(
                "taskssettingsview.reminders.with.a.due.date.bf4594",
                "Tasks with a due date appear in the agenda and the day view. Completed ones stay in Tasks."
            )
        ) {
            SettingsToggleRow(title: L10n.tr("taskssettingsview.show.reminders.in.calendar", "Show tasks in calendar"), isOn: $showsInCalendar)
        }
    }

    private var displayGroup: some View {
        SettingsGroup(
            header: L10n.tr("taskssettingsview.display", "Display"),
            footer: L10n.tr(
                "taskssettingsview.older.completed.reminders.stay.569b5b", "Older completed tasks stay in Reminders; they just aren't loaded here."
            )
        ) {
            SettingsToggleRow(
                title: L10n.tr("taskssettingsview.show.attention.section", "Show Attention section"),
                subtitle: L10n.tr("taskssettingsview.overdue.due.today.and.high.d06e50", "Overdue, due today and high-priority tasks, on top."),
                isOn: showsAttention
            )
            SettingsPickerRow(
                title: L10n.tr("taskssettingsview.show.completed", "Show completed"),
                selection: $completedWindow,
                options: TaskSettings.completedWindowOptions.map { ($0, TaskSettings.completedWindowTitle($0)) }
            )
        }
    }
}
