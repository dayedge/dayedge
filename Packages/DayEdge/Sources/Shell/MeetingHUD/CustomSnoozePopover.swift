import SwiftUI
import UI

/// The menu has already established the intent; this popover only edits a
/// minute count and commits it. The native popover supplies its arrow and
/// outside-click dismissal.
struct CustomSnoozePopover: View {
    @Environment(\.themePalette) private var theme

    let onSnooze: (Int) -> Void
    let onCancel: () -> Void

    @State private var minutes = 5
    @State private var draft = "5"
    @State private var isInvalid = false
    @State private var didSubmit = false
    @FocusState private var isDurationFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            durationControl

            Button(L10n.tr("customsnoozepopover.remind", "Remind"), action: submit)
                .buttonStyle(.borderedProminent)
                .tint(theme.nativeControlAccent)
                .controlSize(.large)
                .frame(width: 88, height: 40)
                .keyboardShortcut(.defaultAction)
                .disabled(isInvalid)
                .accessibilityLabel(L10n.tr("snooze.remind.minutes", "Remind in \(minutes) minutes"))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .floatingSurface(radius: FloatingSurface.reminderRadius, role: .elevated)
        .onExitCommand(perform: onCancel)
        .task { isDurationFocused = true }
    }

    private var durationControl: some View {
        HStack(spacing: 5) {
            TextField(L10n.tr("customsnoozepopover.minutes", "Minutes"), text: $draft)
                .textFieldStyle(.plain)
                .font(.system(size: 16, weight: .medium).monospacedDigit())
                .frame(width: 34)
                .focused($isDurationFocused)
                .onSubmit(submit)
                .onKeyPress(.upArrow) { step(1); return .handled }
                .onKeyPress(.downArrow) { step(-1); return .handled }
                .accessibilityLabel(L10n.tr("customsnoozepopover.reminder.duration", "Reminder duration"))

            Text(L10n.tr("snooze.minutes.label", "\(minutes) minutes"))
                .font(.system(size: 15))
                .foregroundStyle(.secondary)

            Stepper(
                value: Binding(
                    get: { minutes },
                    set: { update($0) }
                ),
                in: CustomSnoozeDuration.range
            ) { EmptyView() }
                .labelsHidden()
                .controlSize(.small)
                .accessibilityLabel(L10n.tr("customsnoozepopover.reminder.duration", "Reminder duration"))
                .accessibilityValue(CustomSnoozeDuration.display(minutes))
        }
        .fixedSize(horizontal: true, vertical: false)
        .frame(height: 40)
        .padding(.horizontal, 8)
        .background(theme.chrome.rowSelection, in: RoundedRectangle(cornerRadius: 9))
        .overlay {
            RoundedRectangle(cornerRadius: 9)
                .strokeBorder(
                    isInvalid ? theme.declinedStatus.opacity(0.55) : theme.chrome.pressedFill,
                    lineWidth: 1
                )
        }
        .onChange(of: draft) { _, newValue in
            if let value = CustomSnoozeDuration.parse(newValue) {
                minutes = value
                isInvalid = false
            } else {
                isInvalid = true
            }
        }
        .onChange(of: isDurationFocused) { _, focused in
            if !focused && !isInvalid { draft = String(minutes) }
        }
    }

    private func step(_ delta: Int) {
        update(min(max(minutes + delta, CustomSnoozeDuration.range.lowerBound), CustomSnoozeDuration.range.upperBound))
    }

    private func update(_ value: Int) {
        minutes = value
        draft = String(value)
        isInvalid = false
    }

    private func submit() {
        guard !didSubmit else { return }
        guard let validMinutes = CustomSnoozeDuration.parse(draft) else {
            isInvalid = true
            isDurationFocused = true
            return
        }
        didSubmit = true
        onSnooze(validMinutes)
    }
}
