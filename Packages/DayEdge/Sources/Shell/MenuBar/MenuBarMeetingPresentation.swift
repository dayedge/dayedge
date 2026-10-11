import Foundation
import Domain

enum MenuBarMeetingPresentation: Equatable {
    case callIcon(VideoConferenceService)
    case contextual(
        state: MenuBarEventIndicatorState,
        configuration: MenuBarEventIndicatorConfiguration,
        calendar: Calendar,
        timeFormat: TimeFormat
    )
}
