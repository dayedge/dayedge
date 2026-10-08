import Foundation

/// Which calendar data source the app reads from.
package enum CalendarBackend: Equatable {
    case mock
    case eventKit
}

/// Which reminders source the Tasks view reads from and writes to.
package enum TaskBackend: Equatable {
    case mock
    case eventKit
}

/// Central place for values that will become real Settings UI later.
/// Nothing else in the app should hardcode these — this is the seam a
/// future Settings screen reads from and writes back to.
package enum AppConfiguration {
    package static let calendarBackend: CalendarBackend = .eventKit
    package static let taskBackend: TaskBackend = .eventKit

    /// Development-only visual preview. Normal launches leave this off;
    /// start the executable with DAYEDGE_PREVIEW_FIRST_EVENT_ONGOING=1 to
    /// evaluate Now as fifteen minutes into today's first timed event.
    package static var previewsFirstEventAsOngoing: Bool {
        ProcessInfo.processInfo.environment["DAYEDGE_PREVIEW_FIRST_EVENT_ONGOING"] == "1"
    }

    /// Development-only: show onboarding at launch even when it's done
    /// (`DAYEDGE_ONBOARDING=1`). It's the real one — its buttons ask.
    package static var showsOnboardingPreview: Bool {
        ProcessInfo.processInfo.environment["DAYEDGE_ONBOARDING"] == "1"
    }

    /// Initial agenda window loaded on first launch/cold navigation,
    /// before any on-demand extension — small on purpose, since this is
    /// what determines how much rendering work happens before the agenda
    /// is first interactive.
    package static let agendaInitialWindowBehindDays = 7
    package static let agendaInitialWindowAheadDays = 21

    /// How much additional range `AgendaSectionStore` loads each time the
    /// user scrolls near either loaded edge, or jumps outside the
    /// currently loaded window.
    package static let agendaChunkDays = 45

    /// `AgendaSectionStore` triggers the next chunk load once the visible
    /// edge is within this many days of the currently loaded boundary, so
    /// the load has a chance to finish before the user actually scrolls
    /// past it.
    package static let agendaEdgeLoadThresholdDays = 7
    /// Month's agenda trims once it holds more than this many days: a longer
    /// list makes every frame and page merge slower (measured: ~90 fps at
    /// 120 days, ~40 at 200 with pinned headers). Trimming leaves ~90 days
    /// and costs a re-anchoring, so it waits for a margin over that —
    /// fewer corrections while scrolling fast.
    package static let agendaMaxLoadedDays = 160
    /// When trimming, days within this far past the visible day are kept.
    package static let agendaKeptDaysBeyondVisible = 45

    /// Maximum distance a recurring-event context-menu jump searches in
    /// either direction. An internal tuning value, not a Settings option.
    package static let recurrenceNavigationHorizonYears = 4

    /// Caps how many dots a single month-grid day shows, regardless of how
    /// many events actually fall on it.
    package static let maxDotsPerDay = 4
}
