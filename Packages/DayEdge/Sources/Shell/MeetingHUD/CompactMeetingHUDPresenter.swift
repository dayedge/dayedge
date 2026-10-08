import AppKit
import UI

/// Fans one logical compact reminder out to one or several independently
/// positioned panels. All copies send actions to the same controller.
@MainActor
final class CompactMeetingHUDPresenter: MeetingHUDPresenting {
    private struct Presentation {
        let occurrence: MeetingHUDOccurrence
        let display: MeetingHUDDisplay
        let actions: MeetingHUDActions
    }

    private let single = MeetingHUDWindowController()
    private var byDisplayID: [CGDirectDisplayID: MeetingHUDWindowController] = [:]
    private var current: Presentation?
    private var screenObserver: NSObjectProtocol?

    init() {
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.render() }
        }
    }

    func show(_ occurrence: MeetingHUDOccurrence, display: MeetingHUDDisplay, actions: MeetingHUDActions) {
        current = Presentation(occurrence: occurrence, display: display, actions: actions)
        render()
    }

    private func render() {
        guard let current else { return }
        if current.display != .all {
            byDisplayID.values.forEach { $0.hide() }
            byDisplayID.removeAll()
            single.show(current.occurrence, display: current.display, actions: current.actions)
            return
        }

        single.hide()
        let activeIDs = Set(MeetingHUDDisplaySelection.screens(for: .all).compactMap(\.stableDisplayID))
        for id in byDisplayID.keys where !activeIDs.contains(id) {
            byDisplayID[id]?.hide()
            byDisplayID[id] = nil
        }
        for id in activeIDs {
            let panel = byDisplayID[id] ?? MeetingHUDWindowController(fixedDisplayID: id)
            byDisplayID[id] = panel
            panel.show(current.occurrence, display: .all, actions: current.actions)
        }
    }

    func hide() {
        current = nil
        single.hide()
        byDisplayID.values.forEach { $0.hide() }
    }

    deinit {
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
    }
}
