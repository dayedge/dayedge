import AppKit
import SwiftUI

/// An inline shortcut field, like System Settings': click (or Space/↩ while
/// focused) to record, press the new keys; Esc cancels, ⌫ removes it. A key
/// `validate` turns down keeps it listening, with the reason underneath.
/// While recording it takes every key in its window (a local monitor — never
/// global), and `ShortcutRecording` tells the app's key handlers to stand by.
/// Recording ends on a key, Esc, a click elsewhere, the window losing focus
/// or closing, and the view going away.
package struct ShortcutRecorder: View {
    @Environment(\.themePalette) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let command: ShortcutCommand
    let shortcut: KeyboardCommand?
    let isCustomized: Bool
    /// A reason the key can't be used, or nil.
    let validate: (KeyboardCommand) -> String?
    let onAssign: (KeyboardCommand) -> Void
    let onClear: () -> Void
    let onReset: () -> Void

    @State private var isRecording = false
    @State private var message: String?

    package init(command: ShortcutCommand, shortcut: KeyboardCommand?, isCustomized: Bool,
                 validate: @escaping (KeyboardCommand) -> String?, onAssign: @escaping (KeyboardCommand) -> Void,
                 onClear: @escaping () -> Void, onReset: @escaping () -> Void) {
        self.command = command
        self.shortcut = shortcut
        self.isCustomized = isCustomized
        self.validate = validate
        self.onAssign = onAssign
        self.onClear = onClear
        self.onReset = onReset
    }

    package var body: some View {
        VStack(alignment: .trailing, spacing: 3) {
            HStack(spacing: 6) {
                if isCustomized, !isRecording {
                    Button(action: onReset) {
                        Image(systemName: "arrow.uturn.backward")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(theme.settings.secondaryText)
                    }
                    .buttonStyle(.plain)
                    .help(L10n.tr("shortcutrecorder.restore.default", "Restore Default"))
                    .accessibilityLabel(L10n.tr("shortcutrecorder.restore.default", "Restore Default"))
                }
                field
            }
            if let message {
                Text(message)
                    .font(.system(size: 11))
                    .foregroundStyle(theme.settings.secondaryText)
                    .transition(.opacity)
            }
        }
    }

    private var field: some View {
        Button { isRecording ? stop() : start() } label: {
            Text(isRecording ? L10n.tr("shortcutrecorder.type.shortcut", "Type Shortcut") : shortcut?.displayLabel ?? "—")
                .font(.system(size: 12, weight: isRecording ? .regular : .medium))
                .foregroundStyle(isRecording || shortcut == nil ? theme.settings.secondaryText : theme.settings.primaryText)
                .frame(minWidth: 64)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(theme.settings.groupFill))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(isRecording ? theme.nativeControlAccent : theme.settings.groupBorder,
                                      lineWidth: isRecording ? 1.5 : 0.5)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            RecorderKeyCatcher(isRecording: isRecording, onKey: handle, onEnd: stop)
        )
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: isRecording)
        .accessibilityLabel(command.title)
        .accessibilityValue(isRecording ? L10n.tr("shortcutrecorder.recording", "Recording")
                                        : shortcut?.displayLabel ?? L10n.tr("shortcutrecorder.none", "None"))
        .accessibilityHint(L10n.tr("shortcutrecorder.hint", "Press to record a new shortcut"))
        .onDisappear(perform: stop)
    }

    private func start() {
        message = nil
        isRecording = true
        ShortcutRecording.shared.begin(command)
    }

    private func stop() {
        guard isRecording else { return }
        isRecording = false
        message = nil
        ShortcutRecording.shared.end(command)
    }

    private func handle(_ event: NSEvent) {
        switch ShortcutRecorderDecision.decide(event, validate: validate) {
        case .cancel: stop()
        case .clear:
            onClear()
            stop()
        case .assign(let shortcut):
            onAssign(shortcut)
            stop()
        case .reject(let reason):
            message = reason
            AccessibilityNotification.Announcement(reason).post()
        }
    }
}

/// While recording: every key down in this window goes to `onKey` and no
/// further (local monitors run before menus' key equivalents, so ⌘W or
/// ⌘[ do nothing either); a click outside the field, the window resigning
/// key or closing ends it.
private struct RecorderKeyCatcher: NSViewRepresentable {
    let isRecording: Bool
    let onKey: (NSEvent) -> Void
    let onEnd: () -> Void

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.onKey = onKey
        context.coordinator.onEnd = onEnd
        if isRecording { context.coordinator.start(in: nsView) } else { context.coordinator.stop() }
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) { coordinator.stop() }

    func makeCoordinator() -> Coordinator { Coordinator(onKey: onKey, onEnd: onEnd) }

    @MainActor
    final class Coordinator {
        var onKey: (NSEvent) -> Void
        var onEnd: () -> Void
        private var monitors: [Any] = []
        private var observers: [NSObjectProtocol] = []

        init(onKey: @escaping (NSEvent) -> Void, onEnd: @escaping () -> Void) {
            self.onKey = onKey
            self.onEnd = onEnd
        }

        func start(in view: NSView) {
            guard monitors.isEmpty, let window = view.window else { return }
            monitors.append(NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self, weak window] event in
                guard let self, event.window === window else { return event }
                MainActor.assumeIsolated { self.onKey(event) }
                return nil
            } as Any)
            monitors.append(NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self, weak view] event in
                guard let self, let view, event.window === view.window,
                      !view.bounds.contains(view.convert(event.locationInWindow, from: nil)) else { return event }
                MainActor.assumeIsolated { self.onEnd() }
                return event
            } as Any)
            for name in [NSWindow.didResignKeyNotification, NSWindow.willCloseNotification] {
                observers.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.onEnd() }
                })
            }
        }

        func stop() {
            monitors.forEach(NSEvent.removeMonitor)
            observers.forEach(NotificationCenter.default.removeObserver)
            monitors = []
            observers = []
        }
    }
}
