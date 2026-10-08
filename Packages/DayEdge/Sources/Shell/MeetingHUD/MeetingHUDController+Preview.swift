import AppKit
import EventKit
import Foundation
import Domain
import UI

extension MeetingHUDController {
    /// Shows a synthetic sample occurrence via the real presenter,
    /// bypassing scanning/dismiss/snooze state entirely — doesn't touch
    /// `currentlyShown` or either production set, so it can't interfere
    /// with (or be interfered with by) a real meeting HUD. Called from
    /// Settings' "Preview" button.
    func showPreview() {
        let sampleStart = now().addingTimeInterval(5 * 60)
        let sampleEnd = sampleStart.addingTimeInterval(25 * 60)
        let sampleEvent = AgendaEventModel(
            id: "preview",
            startTime: Self.previewTimeFormatter.string(from: sampleStart),
            endTime: Self.previewTimeFormatter.string(from: sampleEnd),
            startDate: sampleStart,
            endDate: sampleEnd,
            title: "Test Meeting",
            subtitle: "DayEdge Preview",
            videoService: .zoom,
            tint: RGBAColor(red: 0.30, green: 0.62, blue: 1.0),
            calendarName: "Work",
            videoURL: "https://zoom.us/test",
            attendees: [
                EventAttendee(name: "Alex", status: .accepted),
                EventAttendee(name: "Sam", status: .tentative)
            ]
        )
        let sample = MeetingHUDOccurrence(
            event: sampleEvent,
            start: sampleStart,
            end: sampleEnd
        )
        previewPresenter?.hide(restoreFocus: false)
        let presenter = presenterForStyle(configuration().style)
        previewPresenter = presenter
        presenter.show(sample, display: configuration().display, actions: MeetingHUDActions(
            join: { [weak self] in
                if let url = sample.meetingURL { self?.openURL(url) }
                self?.hidePreview(restoreFocus: false)
            },
            snoozeSmart: { [weak self] in self?.hidePreview(restoreFocus: true) },
            snoozeDuration: { [weak self] _ in self?.hidePreview(restoreFocus: true) },
            dismiss: { [weak self] in self?.hidePreview(restoreFocus: true) }
        ))
    }

    func hidePreview(restoreFocus: Bool) {
        previewPresenter?.hide(restoreFocus: restoreFocus)
        previewPresenter = nil
    }
}
