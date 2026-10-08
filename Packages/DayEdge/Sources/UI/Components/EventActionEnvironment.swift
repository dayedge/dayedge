import SwiftUI
import Domain

private struct EventActionCoordinatorKey: EnvironmentKey {
    static let defaultValue: EventActionCoordinator? = nil
}

private struct ReminderSuppressionStoreKey: EnvironmentKey {
    static let defaultValue: ReminderSuppressionStore? = nil
}

private struct SearchResultRevealKey: EnvironmentKey {
    static let defaultValue: (() -> Void)? = nil
}

extension EnvironmentValues {
    package var eventActionCoordinator: EventActionCoordinator? {
        get { self[EventActionCoordinatorKey.self] }
        set { self[EventActionCoordinatorKey.self] = newValue }
    }

    package var reminderSuppressionStore: ReminderSuppressionStore? {
        get { self[ReminderSuppressionStoreKey.self] }
        set { self[ReminderSuppressionStoreKey.self] = newValue }
    }

    /// Set only on Search's result rows: what Tab does there — show the
    /// result where it lives (an event in the calendar, a task in Tasks).
    /// Its menus offer it, with ⇥, only where this is set.
    package var searchResultReveal: (() -> Void)? {
        get { self[SearchResultRevealKey.self] }
        set { self[SearchResultRevealKey.self] = newValue }
    }
}

extension View {
    /// Attaches the app's shared event context menu, reading the app-wide
    /// `EventActionCoordinator` from the environment rather than requiring
    /// every intermediate view between the app root and an event row to
    /// thread it through explicitly — an event row is built independently
    /// in several places (the Agenda list, the Day timeline, the all-day
    /// lane, and `DayGlanceView`'s month-grid hover popover). Call this
    /// once, inside each reusable event view itself, so every place an
    /// event renders gets the same menu automatically.
    package func eventContextMenu(for event: AgendaEventModel) -> some View {
        modifier(EventContextMenuModifier(event: event))
    }
}

private struct EventContextMenuModifier: ViewModifier {
    let event: AgendaEventModel
    @Environment(\.eventActionCoordinator) private var coordinator

    func body(content: Content) -> some View {
        content.contextMenu {
            if let coordinator {
                EventContextMenuView(event: event, actions: coordinator)
            }
        }
    }
}
