import AppKit
import Foundation
import Observation
import Domain
import UI

/// Coordinates both status items from one agenda read and a minute-aligned timer.
@MainActor
final class MenuBarStateController {
    private let dataProvider: CalendarDataProviding
    private let statusItemController: MenuBarStatusItemController
    private let meetingItemController: MenuBarMeetingItemController
    private let taskRepository: TaskRepository
    private let reminderSuppression: ReminderSuppressionStore

    private var badgeRefreshTimer: Timer?
    private var calendarChangeObserver: NSObjectProtocol?
    private var settingsChangeObserver: NSObjectProtocol?
    private var appActiveObserver: NSObjectProtocol?
    private var wakeObserver: NSObjectProtocol?
    private var environmentObservers: [NSObjectProtocol] = []

    init(
        dataProvider: CalendarDataProviding,
        taskRepository: TaskRepository,
        reminderSuppression: ReminderSuppressionStore,
        statusItemController: MenuBarStatusItemController,
        meetingItemController: MenuBarMeetingItemController
    ) {
        self.reminderSuppression = reminderSuppression
        self.dataProvider = dataProvider
        self.taskRepository = taskRepository
        self.statusItemController = statusItemController
        self.meetingItemController = meetingItemController

        calendarChangeObserver = NotificationCenter.default.addObserver(
            forName: .calendarEventsDidChange, object: nil, queue: .main
        ) { [weak self] _ in
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
        let changes: [Notification.Name] = [
            NSLocale.currentLocaleDidChangeNotification, .NSSystemTimeZoneDidChange, .NSSystemClockDidChange,
            NSApplication.didChangeScreenParametersNotification, NSWindow.didChangeBackingPropertiesNotification,
            NSWindow.didChangeScreenNotification
        ]
        environmentObservers = changes.map { name in
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    self?.refresh()
                    self?.scheduleMinuteRefresh()
                }
            }
        }
    }

    func refresh() {
        let calendar = Calendar.autoupdatingCurrent
        let now = Date.now
        let today = calendar.startOfDay(for: now)
        let events = dataProvider.events(for: today, calendar: calendar)

        let resolution = resolveMenuBarMeeting(
            events: events,
            on: today,
            now: now,
            calendar: calendar,
            indicatorConfiguration: MenuBarEventIndicatorSettings.configuration,
            callReadinessStrategy: CallReadinessSettings.strategy,
            timeFormat: .current
        )

        let badge = MenuBarBadgeSettings.strategy.badgeContent(events: events, now: now, calendar: calendar)
        // New corner glyphs get their data here — see `MenuBarCornerGlyph`.
        let tasksToday = taskRepository.scheduledIndex(now: now, calendar: calendar).tasks(on: today, calendar: calendar)
        let cornerGlyph = MenuBarCornerGlyph.resolve(MenuBarCornerGlyphInputs(
            isOverflow: badge.isOverflow,
            hasTasksDueToday: !tasksToday.isEmpty
        ))
        let configuration = MenuBarDateTimeSettings.configuration()
        let text = configuration.text(
            at: now, formatter: DatePresentationFormatter.current.with(calendar), timeFormat: .current
        )
        let plan = MenuBarCompositionStrategy(presentation: configuration.presentation).plan(
            configuration: configuration, badge: badge, cornerGlyph: cornerGlyph, text: text,
            meeting: resolution.presentation
        )
        let readyCallEvent = resolution.readyCallEvent
        let joinURL = readyCallEvent?.meetingLink?.preferredURL
        let onJoin: (() -> Void)? = joinURL.map { url in { NSWorkspace.shared.open(url) } }
        let toolTip = readyCallEvent.map { L10n.tr("menubarstatecontroller.join", "Join \(String(describing: $0.title))") }
        statusItemController.apply(plan.primary, toolTip: toolTip, onJoin: onJoin)
        meetingItemController.apply(plan.meeting, toolTip: toolTip, onJoin: onJoin)

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
        if let calendarChangeObserver { NotificationCenter.default.removeObserver(calendarChangeObserver) }
        if let settingsChangeObserver { NotificationCenter.default.removeObserver(settingsChangeObserver) }
        if let appActiveObserver { NotificationCenter.default.removeObserver(appActiveObserver) }
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
        environmentObservers.forEach { NotificationCenter.default.removeObserver($0) }
        environmentObservers.removeAll()
    }
}
