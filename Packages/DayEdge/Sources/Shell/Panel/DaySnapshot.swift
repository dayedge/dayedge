import Foundation
import Observation
import Domain
import Agenda

/// Everything the Day view shows that changes while it's hidden.
struct DayInputs: Equatable {
    var date: Date
    var events: [AgendaEventModel] = []
    var nowPresentation: AgendaNowPresentation?
    var positioningRequest: AgendaScrollTarget?
}

/// What the Day view is built from. While Day is on screen, the live
/// selection, its events, NOW and positioning. While it's hidden, a
/// snapshot of them that catches up only once Month's scrolling
/// settles (and only when something it shows changed). The live
/// values change constantly while Month scrolls — the agenda's days
/// page in and out, the selection moves — and each change redrew the
/// whole hidden timeline, briefly costing ~120 MB of graphics memory,
/// every few seconds, for a view nobody could see. Day is still ready
/// when switched to.
@MainActor
@Observable
final class DaySnapshot {
    private var hidden: DayInputs
    @ObservationIgnored private var sync: Task<Void, Never>?
    @ObservationIgnored private let viewModel: CalendarViewModel
    @ObservationIgnored private let agendaStore: AgendaSectionStore
    @ObservationIgnored private let agendaNavigation: AgendaNavigationCoordinator

    init(viewModel: CalendarViewModel, agendaStore: AgendaSectionStore, agendaNavigation: AgendaNavigationCoordinator) {
        self.viewModel = viewModel
        self.agendaStore = agendaStore
        self.agendaNavigation = agendaNavigation
        self.hidden = DayInputs(date: viewModel.selectedDate)
    }

    private var isDayShown: Bool { agendaNavigation.displayedViewMode == .day }

    var inputs: DayInputs {
        isDayShown ? live(for: viewModel.selectedDate) : hidden
    }

    /// Refreshes the hidden Day's snapshot 300 ms after the last change —
    /// right away while Day is on screen — and only if it differs.
    func selectedDateDidChange(to date: Date) {
        sync?.cancel()
        guard !isDayShown else {
            hidden = live(for: date)
            return
        }
        sync = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            let inputs = live(for: date)
            if inputs != hidden { hidden = inputs }
        }
    }

    /// The hidden snapshot follows the agenda's data (a reload, the
    /// first load), settled like the date — and changes nothing unless
    /// the hidden day's own events did.
    func agendaDidChange() {
        guard !isDayShown else { return }
        selectedDateDidChange(to: hidden.date)
    }

    /// Leaving Day: the snapshot starts from what was on screen.
    func viewModeDidChange(from old: ViewMode) {
        if old == .day { hidden = live(for: viewModel.selectedDate) }
    }

    private func live(for date: Date) -> DayInputs {
        DayInputs(date: date, events: agendaStore.events(onDate: date),
                  nowPresentation: agendaNavigation.agendaNowPresentation,
                  positioningRequest: agendaNavigation.requestedMonthAgendaDate)
    }
}
