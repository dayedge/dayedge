import AppKit
import EventKit
import Foundation
import Observation
import Domain
import UI

/// Decides what the status item *should* currently show, and when to
/// recompute it — split out of `AppDelegate`. Never touches `NSStatusItem`
/// directly; only calls `MenuBarStatusItemController.apply(...)` with the
/// result. Owns the minute-aligned refresh timer and the four
/// notifications (EventKit changes, settings changes, app activation,
/// wake from sleep) that trigger an early recompute.
@MainActor
final class MenuBarStateController {
    private let dataProvider: CalendarDataProviding
    private let eventStore: EKEventStore
    private let statusItemController: MenuBarStatusItemController
    private let taskRepository: TaskRepository
    private let reminderSuppression: ReminderSuppressionStore

    /// The event represented by the right-hand accessory when clicking
    /// that accessory should immediately join its call.
    private var readyCallEvent: AgendaEventModel?

    private var badgeRefreshTimer: Timer?
    private var eventStoreChangeObserver: NSObjectProtocol?
    private var settingsChangeObserver: NSObjectProtocol?
    private var appActiveObserver: NSObjectProtocol?
    private var wakeObserver: NSObjectProtocol?

    init(
        dataProvider: CalendarDataProviding,
        eventStore: EKEventStore,
        taskRepository: TaskRepository,
        reminderSuppression: ReminderSuppressionStore,
        statusItemController: MenuBarStatusItemController
    ) {
        self.reminderSuppression = reminderSuppression
        self.dataProvider = dataProvider
        self.eventStore = eventStore
        self.taskRepository = taskRepository
        self.statusItemController = statusItemController

        eventStoreChangeObserver = NotificationCenter.default.addObserver(
            forName: .calendarEventsDidChange, object: nil, queue: .main
        ) { [weak self] _ in
            // `queue: .main` above already guarantees this runs on the
            // main thread at runtime; the `Task` is only to satisfy the
            // compiler, which can't see that guarantee through a plain
            // non-isolated closure type.
            Task { @MainActor in self?.refresh() }
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

    /// Redraws the combined status item image from today's agenda — one
    /// EventKit read decides both halves, rather than each recomputing its
    /// own.
    func refresh() {
        let calendar = Calendar.autoupdatingCurrent
        let now = Date.now
        let today = calendar.startOfDay(for: now)
        let events = dataProvider.events(for: today, calendar: calendar)

        let resolution = resolveMenuBarAccessory(
            events: events,
            on: today,
            now: now,
            calendar: calendar,
            indicatorConfiguration: MenuBarEventIndicatorSettings.configuration,
            callReadinessStrategy: CallReadinessSettings.strategy,
            timeFormat: .current
        )
        readyCallEvent = resolution.readyCallEvent

        let badge = MenuBarBadgeSettings.strategy.badgeContent(events: events, now: now, calendar: calendar)
        // New corner glyphs get their data here — see `MenuBarCornerGlyph`.
        let tasksToday = taskRepository.scheduledIndex(now: now, calendar: calendar).tasks(on: today, calendar: calendar)
        let cornerGlyph = MenuBarCornerGlyph.resolve(MenuBarCornerGlyphInputs(
            isOverflow: badge.isOverflow,
            hasTasksDueToday: !tasksToday.isEmpty
        ))
        let rendered = CombinedMenuBarIcon.render(
            accessory: resolution.accessory, badgeValue: badge.number, cornerGlyph: cornerGlyph
        )

        let joinURL = readyCallEvent?.meetingLink?.preferredURL
        statusItemController.apply(
            image: rendered?.image,
            toolTip: readyCallEvent.map { L10n.tr("menubarstatecontroller.join", "Join \(String(describing: $0.title))") },
            accessoryRegionMinX: rendered?.accessoryRegionMinX,
            onAccessoryClick: joinURL.map { url in { NSWorkspace.shared.open(url) } }
        )
    }

    /// The right-click menu, from what's true right now.
    func menuPlan() -> [[StatusMenuItem]] {
        let calendar = Calendar.autoupdatingCurrent
        let now = Date.now
        reminderSuppression.pruneExpired()
        let mute = reminderSuppression.activeGlobalMute
        return StatusMenuPlan.resolve(StatusMenuPlan.Inputs(
            now: now,
            calendar: calendar,
            events: dataProvider.events(for: calendar.startOfDay(for: now), calendar: calendar),
            actionableTaskCount: TaskBuckets.actionableTodayCount(tasks: taskRepository.tasks, now: now, calendar: calendar),
            isMuted: { [reminderSuppression] in reminderSuppression.isMuted($0) },
            globalMute: mute.map { ($0.until, $0.chosen) }
        ))
    }

    /// Redraws whenever the task repository's contents change (a reload, a
    /// task completed from the popover). Observation fires once per
    /// registration, so this re-registers after each change.
    func observeTasks() {
        withObservationTracking {
            _ = taskRepository.revision
        } onChange: { [weak self] in
            // `onChange` runs before the new value is stored; hop to the
            // next main-actor turn to read it.
            Task { @MainActor in
                self?.refresh()
                self?.observeTasks()
            }
        }
    }

    /// Uses a one-shot timer aligned to the next wall-clock minute. This
    /// avoids accumulating drift and is rescheduled after wake/activation,
    /// while common run-loop mode keeps it alive during menu tracking.
    func scheduleMinuteRefresh() {
        badgeRefreshTimer?.invalidate()
        let now = Date.now
        let calendar = Calendar.autoupdatingCurrent
        let currentMinute = calendar.dateInterval(of: .minute, for: now)?.start ?? now
        let nextMinute = calendar.date(byAdding: .minute, value: 1, to: currentMinute)
            ?? now.addingTimeInterval(60)
        let timer = Timer(fire: nextMinute.addingTimeInterval(0.05), interval: 0, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
                self?.scheduleMinuteRefresh()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        badgeRefreshTimer = timer
    }

    func invalidate() {
        badgeRefreshTimer?.invalidate()
        if let eventStoreChangeObserver { NotificationCenter.default.removeObserver(eventStoreChangeObserver) }
        if let settingsChangeObserver { NotificationCenter.default.removeObserver(settingsChangeObserver) }
        if let appActiveObserver { NotificationCenter.default.removeObserver(appActiveObserver) }
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
    }
}
