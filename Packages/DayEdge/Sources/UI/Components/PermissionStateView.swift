import SwiftUI
import Domain

/// Calendar or Reminders isn't allowed: one component, two subjects —
/// it replaces the whole content area (no page title above it), centered
/// under the shared toolbar.
package struct PermissionStateView: View {
    package enum Subject {
        case calendar, reminders
    }

    @Environment(\.themePalette) private var theme

    package let subject: Subject
    package let status: SourceAccessStatus
    package let onAction: () -> Void

    package var body: some View {
        VStack(spacing: 0) {
            Image(systemName: symbol)
                .font(.system(size: 34, weight: .regular))
                .foregroundStyle(theme.secondaryText)
                .accessibilityHidden(true)
            Text(title)
                .font(AppTheme.TextStyle.eventTitle)
                .foregroundStyle(theme.primaryText)
                .padding(.top, 18)
            Text(message)
                .font(AppTheme.TextStyle.eventSubtitle)
                .foregroundStyle(theme.secondaryText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)
            if let action {
                Button(action, action: onAction)
                    .buttonStyle(.borderedProminent)
                    .tint(theme.primaryActionTint)
                    .controlSize(.regular)
                    .padding(.top, 16)
            }
        }
        .frame(maxWidth: 260)
        .padding(.horizontal, AppTheme.horizontalPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var symbol: String {
        switch subject {
        case .calendar: "calendar"
        case .reminders: "checklist"
        }
    }

    private var isOff: Bool { status == .denied }

    private var title: String {
        switch subject {
        // swiftlint:disable:next void_function_in_ternary - both localization calls return String
        case .calendar: isOff ? L10n.tr(
            "permissionstateview.calendar.access.is.off",
            "Calendar access is off"
        ) : L10n.tr(
            "permissionstateview.connect.calendar",
            "Connect Calendar"
        )
        // swiftlint:disable:next void_function_in_ternary - both localization calls return String
        case .reminders: isOff ? L10n.tr(
            "permissionstateview.reminders.access.is.off",
            "Reminders access is off"
        ) : L10n.tr(
            "permissionstateview.connect.reminders",
            "Connect Reminders"
        )
        }
    }

    private var message: String {
        switch (subject, isOff) {
        case (.calendar, false): L10n.tr("permissionstateview.dayedge.uses.apple.calendar.cf3514", "DayEdge uses Apple Calendar to show your events, agenda and upcoming meetings.")
        case (.calendar, true): L10n.tr("permissionstateview.enable.calendar.access.to.2c7068", "Enable Calendar access to show your events, agenda and upcoming meetings again.")
        case (.reminders, false): L10n.tr("permissionstateview.dayedge.uses.apple.reminders.ae283d", "DayEdge uses Apple Reminders to show your tasks alongside your day.")
        case (.reminders, true): L10n.tr("permissionstateview.enable.reminders.access.to.4f8892", "Enable Reminders access to show your tasks again.")
        }
    }

    private var action: String? {
        switch status {
        case .granted: nil
        case .denied: L10n.tr("permissionstateview.open.system.settings", "Open System Settings")
        // swiftlint:disable:next void_function_in_ternary - both localization calls return String
        case .notDetermined: subject == .calendar ? L10n.tr(
            "permissionstateview.allow.calendar.access",
            "Allow Calendar Access"
        ) : L10n.tr(
            "permissionstateview.allow.reminders.access",
            "Allow Reminders Access"
        )
        }
    }

    package init(subject: Subject, status: SourceAccessStatus, onAction: @escaping () -> Void) {
        self.subject = subject
        self.status = status
        self.onAction = onAction
    }
}

/// While the index refills after Calendar access came back.
package struct CalendarUpdatingNotice: View {
    @Environment(\.themePalette) private var theme

    package var body: some View {
        HStack(spacing: 6) {
            ProgressView().controlSize(.mini)
            Text(L10n.tr("permissionstateview.updating.calendars", "Updating calendars…"))
                .font(AppTheme.TextStyle.eventSubtitle)
                .foregroundStyle(theme.secondaryText)
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }

    package init() {
    }
}
