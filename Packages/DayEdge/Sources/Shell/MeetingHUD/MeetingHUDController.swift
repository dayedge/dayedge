import AppKit
import EventKit
import Foundation
import Domain
import UI

/// What the HUD's buttons and keys do.
struct MeetingHUDActions {
    let join: () -> Void
    let snoozeSmart: () -> Void
    let snoozeDuration: (TimeInterval) -> Void
    let dismiss: () -> Void
}

@MainActor
protocol MeetingHUDPresenting: AnyObject {
    func show(_ occurrence: MeetingHUDOccurrence, display: MeetingHUDDisplay, actions: MeetingHUDActions)
    func hide()
    func hide(restoreFocus: Bool)
}
extension MeetingHUDPresenting {
    func hide(restoreFocus: Bool) { hide() }
}
extension MeetingHUDWindowController: MeetingHUDPresenting {}

/// Scans for an upcoming meeting and drives the Meeting HUD panel —
/// split the same way `MenuBarStateController` splits from
/// `MenuBarStatusItemController`: this owns *when* and *whether* to show
/// something, a `MeetingHUDPresenting` owns the actual window.
@MainActor
final class MeetingHUDController {
    private let dataProvider: CalendarDataProviding
    private let eventStore: EKEventStore
    /// Style-specific presenters own windows, not reminder decisions.
    ///
    /// This is a *factory*, called through `presenter(for:)` below rather
    /// than directly — the production default (`MeetingHUDWindowController()`)
    /// constructs a brand-new window controller on every call. Calling it
    /// straight from `apply()`/`dismiss()`/`join()`/etc. each time meant
    /// every one of those was talking to a *different, throwaway*
    /// instance: `dismiss()`'s `.hide()` landed on a controller whose own
    /// `panel` was `nil` (it had never called `show()`), so the actually-
    /// visible window — created by whichever `apply()` call ran last —
    /// never got told to close. Tests never caught this because the fake
    /// presenter they inject is already a stable singleton by construction.
    let presenterForStyle: @MainActor (MeetingHUDStyle) -> MeetingHUDPresenting
    private var presenterCache: [MeetingHUDStyle: MeetingHUDPresenting] = [:]
    var previewPresenter: MeetingHUDPresenting?
    let now: () -> Date
    let openURL: (URL) -> Void
    private let playSound: () -> Void
    /// Injected (defaulting to the real persisted settings) so tests can
    /// exercise scanning/state logic without touching real `UserDefaults`.
    let configuration: () -> MeetingHUDConfiguration
    private let reminderSuppression: ReminderSuppressionStore

    private var scanTimer: Timer?
    var snoozeExpiryTimer: Timer?
    private var eventStoreChangeObserver: NSObjectProtocol?
    private var settingsChangeObserver: NSObjectProtocol?
    private var appActiveObserver: NSObjectProtocol?
    private var wakeObserver: NSObjectProtocol?
    private var eventStoreChangeDebounceTask: Task<Void, Never>?

    var dismissedOccurrenceIDs: Set<String> = []
    var snoozeStateByOccurrenceID: [String: MeetingHUDSnoozeState] = [:]
    var lastKnownDay: Date?
    var currentlyShown: MeetingHUDOccurrence?
    private var presentedStyle: MeetingHUDStyle?
    private var presentedDisplay: MeetingHUDDisplay?
    private var refreshGeneration = UUID()

    init(
        dataProvider: CalendarDataProviding,
        eventStore: EKEventStore,
        presenterForStyle: @escaping @MainActor (MeetingHUDStyle) -> MeetingHUDPresenting = {
            switch $0 {
            case .compact: CompactMeetingHUDPresenter()
            case .fullScreen: FullScreenMeetingTakeoverPresenter()
            }
        },
        now: @escaping () -> Date = { .now },
        openURL: @escaping (URL) -> Void = { NSWorkspace.shared.open($0) },
        playSound: @escaping () -> Void = { NSSound(named: "Glass")?.play() },
        configuration: @escaping () -> MeetingHUDConfiguration = { MeetingHUDSettings.configuration },
        reminderSuppression: ReminderSuppressionStore? = nil
    ) {
        self.dataProvider = dataProvider
        self.eventStore = eventStore
        self.presenterForStyle = presenterForStyle
        self.now = now
        self.openURL = openURL
        self.playSound = playSound
        self.configuration = configuration
        self.reminderSuppression = reminderSuppression ?? ReminderSuppressionStore()

        // Owns its own lifecycle observers, mirroring
        // `MenuBarStateController` — `AppDelegate` only constructs,
        // starts, and invalidates this controller.
        eventStoreChangeObserver = NotificationCenter.default.addObserver(
            forName: .calendarEventsDidChange, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.handleEventStoreChange() }
        }
        settingsChangeObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: UserDefaults.standard, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        appActiveObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
                self?.scheduleMinuteRefresh()
            }
        }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
                self?.scheduleMinuteRefresh()
            }
        }
    }

    func refresh() {
        let configuration = self.configuration()
        // Without Calendar access there's no meeting to show (and nothing
        // to reconcile mutes against).
        guard configuration.isEnabled, dataProvider.isAuthorized else {
            hideIfShown()
            return
        }

        let generation = UUID()
        refreshGeneration = generation
        let calendar = Calendar.autoupdatingCurrent
        let today = calendar.startOfDay(for: now())
        pruneStateIfDayChanged(today)
        reminderSuppression.pruneExpired()

        Task { @MainActor in
            guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) else { return }
            // `agendaSections(in:calendar:)`, not `events(for:calendar:)`:
            // the latter can call through to `eventsByDaySync`'s
            // `queue.sync`, which could block this (main-actor) call
            // behind another in-flight EventKit fetch. This path is
            // already async everywhere it touches EventKit.
            let sections = await self.dataProvider.agendaSections(
                in: DateInterval(start: today, end: tomorrow), calendar: calendar
            )
            // A newer refresh (settings change, wake, another scan tick)
            // may have started and even finished while this awaited —
            // don't let a stale result overwrite it.
            guard self.refreshGeneration == generation else { return }
            self.apply(sections.flatMap(\.events), configuration: configuration)
        }
    }

    func apply(_ events: [AgendaEventModel], configuration: MeetingHUDConfiguration) {
        reminderSuppression.reconcile(events)
        // "Mute Until ›" silences every meeting until it ends; the minute
        // scan picks reminders back up once it has.
        guard !reminderSuppression.isGloballyMuted else {
            hideIfShown()
            return
        }
        let unmutedEvents = events.filter { !reminderSuppression.isMuted($0) }
        guard let occurrence = resolveMeetingHUDOccurrence(events: unmutedEvents, now: now(), configuration: configuration),
              !dismissedOccurrenceIDs.contains(occurrence.id)
        else {
            hideIfShown()
            return
        }

        if let snoozeState = snoozeStateByOccurrenceID[occurrence.id] {
            if now() < snoozeState.wakeAt {
                hideIfShown()
                return
            }
            // Expired — falls through to show again below, exactly the
            // "interrupt me again at that time" contract.
            snoozeStateByOccurrenceID[occurrence.id] = nil
            scheduleNextSnoozeExpiry()
        }

        guard occurrence != currentlyShown
                || presentedStyle != configuration.style
                || presentedDisplay != configuration.display else { return }
        let isNewOccurrence = occurrence.id != currentlyShown?.id
        if let presentedStyle, presentedStyle != configuration.style {
            presenter(for: presentedStyle).hide()
        }
        currentlyShown = occurrence
        presentedStyle = configuration.style
        presentedDisplay = configuration.display
        if isNewOccurrence {
            if configuration.playsSound { playSound() }
        }
        // Idempotent "present or update": same call whether this is a
        // brand-new occurrence or a content-only change (title/attendees/
        // link edited) to one already showing — a stale panel is never
        // left up just because the id didn't change.
        presenter(for: configuration.style).show(occurrence, display: configuration.display, actions: MeetingHUDActions(
            join: { [weak self] in self?.join(occurrence) },
            snoozeSmart: { [weak self] in self?.snoozeSmart(occurrence) },
            snoozeDuration: { [weak self] duration in self?.snoozeForDuration(occurrence, duration: duration) },
            dismiss: { [weak self] in self?.dismiss(occurrence) }
        ))
    }

    func hideIfShown() {
        guard currentlyShown != nil else { return }
        currentlyShown = nil
        hidePresented(restoreFocus: true)
    }

    func hidePresented(restoreFocus: Bool) {
        if let presentedStyle { presenter(for: presentedStyle).hide(restoreFocus: restoreFocus) }
        presentedStyle = nil
        presentedDisplay = nil
    }

    /// Looks up (or lazily creates and caches) the one presenter for
    /// `style` — never calls `presenterForStyle` fresh per call. See
    /// that property's own doc comment for why that distinction is the
    /// actual fix for Join/Snooze/Dismiss not closing a real HUD.
    func presenter(for style: MeetingHUDStyle) -> MeetingHUDPresenting {
        if let cached = presenterCache[style] { return cached }
        let created = presenterForStyle(style)
        presenterCache[style] = created
        return created
    }

    /// A burst of changes (one EventKit sync, a fill committing several
    /// months) arrives as several `.calendarEventsDidChange` posts close
    /// together; a short debounce refreshes once.
    private func handleEventStoreChange() {
        eventStoreChangeDebounceTask?.cancel()
        eventStoreChangeDebounceTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            refresh()
        }
    }

    static let previewTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    /// Uses a one-shot timer aligned to the next wall-clock minute, same
    /// pattern as `MenuBarStateController.scheduleMinuteRefresh()`.
    func scheduleMinuteRefresh() {
        scanTimer?.invalidate()
        let calendar = Calendar.autoupdatingCurrent
        let currentMinute = calendar.dateInterval(of: .minute, for: now())?.start ?? now()
        let nextMinute = calendar.date(byAdding: .minute, value: 1, to: currentMinute)
            ?? now().addingTimeInterval(60)
        let timer = Timer(fire: nextMinute.addingTimeInterval(0.05), interval: 0, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
                self?.scheduleMinuteRefresh()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        scanTimer = timer
    }

    func invalidate() {
        hidePreview(restoreFocus: false)
        hidePresented(restoreFocus: false)
        scanTimer?.invalidate()
        snoozeExpiryTimer?.invalidate()
        eventStoreChangeDebounceTask?.cancel()
        if let eventStoreChangeObserver { NotificationCenter.default.removeObserver(eventStoreChangeObserver) }
        if let settingsChangeObserver { NotificationCenter.default.removeObserver(settingsChangeObserver) }
        if let appActiveObserver { NotificationCenter.default.removeObserver(appActiveObserver) }
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
    }
}
