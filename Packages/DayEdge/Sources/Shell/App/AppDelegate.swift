import SwiftUI
import AppKit
import EventKit
import Domain
import Platform
import UI
import Intelligence

/// Top-level orchestration: decides which presentation mode the app runs
/// in and wires up the pieces that implement it, but doesn't implement any
/// of their mechanics itself — those live in `PopoverWindowController`
/// (the bubble window's lifecycle), `MenuBarStatusItemController` (the
/// status item and its click routing), and `MenuBarStateController` (what
/// the status item should currently show, and when to recompute it).
///
/// The Settings window is managed here too, rather than via SwiftUI's
/// `Settings` scene: that scene's `showSettingsWindow:` command relies on
/// the standard app-menu wiring that comes with a `WindowGroup`, which we
/// don't have — without it, `openSettings()`/`sendAction` silently does
/// nothing. Managing a plain `NSWindow` ourselves sidesteps that entirely.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var popoverWindow: PopoverWindowController?
    private var settingsWindow: NSWindow?
    let onboardingWindow = OnboardingWindowController()
    private var dockSettingObserver: NSObjectProtocol?
    private var statusItemController: MenuBarStatusItemController?
    private var menuBarState: MenuBarStateController?
    private var meetingHUD: MeetingHUDController?
    /// The local calendar index — the event source: opened at launch,
    /// filling in the background once Calendar access is granted.
    private var calendarIndex: CalendarIndexRuntime?
    private let indexActivity = CalendarIndexActivity()

    /// Toggle while developing to preview both contexts the app will run
    /// in: `.menuBarPopover` (pointing at a status item) and `.standalone`
    /// (e.g. launched from Raycast, floating free with nothing to point
    /// at). Deliberately two real, distinct modes — not one collapsed into
    /// the other — since a future Raycast/Spotlight-launched build still
    /// wants the plain floating window with no status item at all.
    private let presentationStyle: PanelPresentationStyle = .menuBarPopover()

    /// For writes, reminders and permissions; events are read from the
    /// calendar index. `RootView` and this delegate's status-item
    /// badge both read through the same `dataProvider`.
    let eventStore = EKEventStore()
    private let visibilityStore = SourceVisibilityStore(kind: .calendars)
    /// Reminder lists: owned here, like calendars, so the popover's selector,
    /// the Tasks view and Settings all share one source of truth.
    private let taskProvider: TaskDataProviding
    private let listVisibility = SourceVisibilityStore(kind: .taskLists)
    lazy var taskRepository = TaskRepository(provider: taskProvider, listVisibility: listVisibility)
    let appearance = AppearanceStore.shared
    private let settingsRouter = SettingsRouter()
    private let reminderSuppression = ReminderSuppressionStore()
    /// Settings → Intelligence: which model answers Ask. Shared by
    /// the popover and the Settings window.
    private let assistantSettings = AssistantSettingsStore()
    private let dataProvider: CalendarDataProviding
    private let presentationCoordinator = PopoverPresentationCoordinator()
    /// Calendar access, live — the only thing that decides whether events
    /// are shown. Watched from launch whatever the index does.
    let calendarAccess: CalendarPermissionMonitor

    override init() {
        switch AppConfiguration.calendarBackend {
        case .eventKit:
            // The index opens now (syncing starts once access is granted),
            // so the indexed source can read it from the first frame.
            let index = CalendarIndexRuntime.make(activity: indexActivity)
            calendarIndex = index
            let source: CalendarEventSource = index.map { IndexedCalendarEventSource(service: $0.service) }
                ?? UnavailableCalendarEventSource()
            dataProvider = CalendarProvider(source: source, visibilityStore: visibilityStore)
        case .mock:
            dataProvider = MockCalendarDataProvider()
        }
        calendarAccess = AppConfiguration.calendarBackend == .eventKit
            ? CalendarPermissionMonitor()
            : CalendarPermissionMonitor(read: { .granted })
        switch AppConfiguration.taskBackend {
        case .eventKit:
            taskProvider = EventKitTaskProvider(eventStore: eventStore)
        case .mock:
            taskProvider = MockTaskDataProvider()
        }
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // `.accessory` for the menu-bar mode — no Dock icon, no Cmd-Tab
        // entry, a pure menu-bar presence. `.regular` for standalone: a
        // bare, unsigned executable can otherwise never actually become
        // the active application (its window can look frontmost, even
        // show SwiftUI's own focus indicators, while macOS keeps routing
        // real keyboard input elsewhere) — explicitly claiming a normal
        // foreground policy is what makes clicking/activating it actually
        // hand it real keyboard focus. `.accessory` grants that same real
        // activation/focus once `NSApp.activate` is called, just without
        // the Dock/App-Switcher visibility `.regular` also brings.
        // In the menu bar it's `.accessory` unless Settings → General → Show
        // in Dock asks for the Dock too; followed live.
        applyActivationPolicy()
        calendarAccess.onChange = { [weak self] status in self?.calendarAccessChanged(to: status) }
        calendarAccess.start(eventStore: eventStore)
        dockSettingObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: UserDefaults.standard, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.applyActivationPolicy() }
        }

        let popoverWindow = makePopoverWindow()
        self.popoverWindow = popoverWindow

        switch presentationStyle {
        case .standalone:
            popoverWindow.showCentered()
        case .menuBarPopover:
            installMenuBar(popoverWindow: popoverWindow)
        }

        // Settings or the popover menu changed which calendars count.
        NotificationCenter.default.addObserver(
            forName: .sourceVisibilityDidChange, object: visibilityStore, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.menuBarState?.refresh()
                self?.meetingHUD?.refresh()
            }
        }

        taskRepository.start()
        Task { await taskRepository.loadIfNeeded() }

        // Applies the permission as it is now (a cache left from a revoked
        // run is erased here), then asks the first time — unless onboarding
        // shows: its Calendar step asks instead.
        calendarAccessChanged(to: calendarAccess.status)
        startOnboardingOrAskForCalendar()
    }

    /// The panel: the root view in its themed host, in the popover window.
    private func makePopoverWindow() -> PopoverWindowController {
        let rootView = RootView(
            eventStore: eventStore,
            dataProvider: dataProvider,
            visibilityStore: visibilityStore,
            taskRepository: taskRepository,
            reminderSuppression: reminderSuppression,
            assistantSettings: assistantSettings,
            presentationCoordinator: presentationCoordinator,
            calendarAccess: calendarAccess,
            presentationStyle: presentationStyle,
            indexActivity: indexActivity,
            onOpenSettings: { [weak self] destination in self?.showSettings(destination) }
        )
        let hosting = NSHostingController(rootView: ThemedRoot(content: rootView, appearance: appearance))
        // The panel's size is the window's (`PopoverWindowController` fixes
        // the width and the height range). Without this the hosting view
        // re-measures the whole UI for its min/ideal/max size whenever
        // anything inside changes — on every scroll frame (measured).
        hosting.sizingOptions = []

        let popoverWindow = PopoverWindowController(
            contentViewController: hosting,
            presentationStyle: presentationStyle,
            presentationCoordinator: presentationCoordinator
        )
        return popoverWindow
    }

    /// The menu-bar mode: the status item, what it shows and the Meeting HUD.
    private func installMenuBar(popoverWindow: PopoverWindowController) {
        // Stays hidden until the status item is actually clicked —
        // see `MenuBarStatusItemController.onCalendarClick`.
        let statusItemController = MenuBarStatusItemController()
        statusItemController.onCalendarClick = { [weak popoverWindow, weak statusItemController] in
            guard let popoverWindow, let anchor = statusItemController?.screenAnchor else { return }
            popoverWindow.toggle(anchoredTo: anchor)
        }
        statusItemController.onMenuAction = { [weak self] row in self?.handleMenuAction(row) }
        statusItemController.onMuteUntil = { [weak self] option in
            self?.reminderSuppression.muteAll(until: option.endDate(now: .now, calendar: .autoupdatingCurrent), chosen: option)
        }
        statusItemController.onAnchorChange = { [weak popoverWindow] anchor in
            popoverWindow?.reposition(anchoredTo: anchor)
        }
        statusItemController.install()
        popoverWindow.anchorScreenFrame = { [weak statusItemController] in statusItemController?.buttonScreenFrame }
        self.statusItemController = statusItemController
        startMenuBarState(statusItemController)
        startMeetingHUD()
    }

    private func startMenuBarState(_ statusItemController: MenuBarStatusItemController) {
        let menuBarState = MenuBarStateController(
            dataProvider: dataProvider, eventStore: eventStore,
            taskRepository: taskRepository, reminderSuppression: reminderSuppression,
            statusItemController: statusItemController
        )
        self.menuBarState = menuBarState
        statusItemController.menuPlan = { [weak menuBarState] in menuBarState?.menuPlan() ?? [] }
        menuBarState.refresh()
        menuBarState.scheduleMinuteRefresh()
        menuBarState.observeTasks()
    }

    private func startMeetingHUD() {
        let meetingHUD = MeetingHUDController(
            dataProvider: dataProvider, eventStore: eventStore,
            reminderSuppression: reminderSuppression
        )
        self.meetingHUD = meetingHUD
        reminderSuppression.onMutation = { [weak meetingHUD] key, muted in
            meetingHUD?.reminderSuppressionChanged(for: key, muted: muted)
        }
        reminderSuppression.onGlobalMutation = { [weak meetingHUD] in meetingHUD?.refresh() }
        meetingHUD.refresh()
        meetingHUD.scheduleMinuteRefresh()
    }

    func requestCalendarAccessIfNeeded() {
        guard AppConfiguration.calendarBackend == .eventKit, calendarAccess.status == .notDetermined else { return }
        Task {
            _ = await EventKitAccess.requestAccessIfNeeded(eventStore: eventStore)
            calendarAccess.check()
        }
    }

    /// The one place Calendar access takes effect. Granted: the index
    /// syncs (refilling from scratch after a revocation). Otherwise: it
    /// stops and erases every cached event, and everything derived from
    /// events — menu-bar meeting, NOW, Join, badge, the HUD — clears
    /// (their reads are empty now). Reminders are unaffected.
    private func calendarAccessChanged(to status: SourceAccessStatus) {
        if status == .granted {
            visibilityStore.update(EventKitAccess.calendarSources(eventStore: eventStore))
            calendarIndex?.start()
        } else {
            calendarIndex?.revoke()
        }
        NotificationCenter.default.post(name: .calendarEventsDidChange, object: nil)
        menuBarState?.refresh()
        meetingHUD?.refresh()
    }

    /// `.regular` (Dock and app switcher) or `.accessory` (menu bar only).
    private func applyActivationPolicy() {
        let policy: NSApplication.ActivationPolicy
        switch presentationStyle {
        case .standalone: policy = .regular
        case .menuBarPopover: policy = DockSettings.showsIcon() ? .regular : .accessory
        }
        // In the Dock, the icon shows the current month (`DockIcon`).
        DockIcon.shared.setShown(policy == .regular)
        guard NSApp.activationPolicy() != policy else { return }
        NSApp.setActivationPolicy(policy)
        // Leaving the Dock deactivates the app; the Settings window the
        // switch was just flipped in stays in front.
        if policy == .accessory, let settingsWindow, settingsWindow.isVisible {
            NSApp.activate(ignoringOtherApps: true)
            settingsWindow.makeKeyAndOrderFront(nil)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        menuBarState?.invalidate()
        meetingHUD?.invalidate()
        calendarAccess.stop()
        calendarIndex?.stop()
    }

    // MARK: - Status menu

    // swiftlint:disable:next cyclomatic_complexity - routes each status-menu and popover command
    private func handleMenuAction(_ row: StatusMenuItem) {
        switch row {
        case .open: openPopover(then: nil)
        case .search: openPopover(then: .search)
        case .ask: openPopover(then: .ask)
        case .showTodayTasks: openPopover(then: .showTodayTasks)
        case .showEvent(let event, _):
            guard let start = event.startDate else { return }
            openPopover(then: .showEvent(OccurrenceNavigationTarget(eventID: event.id, startDate: start)))
        case .join(let event):
            if let url = event.meetingLink?.preferredURL { NSWorkspace.shared.open(url) }
        case .muteMeeting(let event): reminderSuppression.setMuted(true, for: event)
        case .restoreMeeting(let event): reminderSuppression.setMuted(false, for: event)
        case .unmuteAll: reminderSuppression.unmuteAll()
        case .settings: showSettings(nil)
        case .pauseAlerts, .about, .quit: break
        }
    }

    /// Shows the popover under the status item, then hands it the command.
    func openPopover(then command: PopoverCommand?) {
        guard let popoverWindow, let anchor = statusItemController?.screenAnchor else { return }
        popoverWindow.open(anchoredTo: anchor) { [presentationCoordinator] in
            if let command { presentationCoordinator.send(command) }
        }
    }

    // MARK: - Settings

    private func showSettings(_ destination: SettingsDestination? = nil) {
        if let destination { settingsRouter.open(destination) }
        if let settingsWindow {
            settingsWindow.makeKeyAndOrderFront(nil)
        } else {
            let rootView = SettingsRootView(
                visibilityStore: visibilityStore,
                taskRepository: taskRepository,
                assistantSettings: assistantSettings,
                router: settingsRouter,
                eventStore: eventStore,
                indexActivity: calendarIndex != nil || indexActivity.isUnavailable ? indexActivity : nil,
                onShowMeetingHUDPreview: { [weak self] in self?.meetingHUD?.showPreview() },
                onShowWelcome: { [weak self] in self?.showOnboarding() }
            )
            let hosting = NSHostingController(rootView: ThemedRoot(content: rootView, usesWindowBackground: true, appearance: appearance))
            let window = NSWindow(contentViewController: hosting)
            window.title = L10n.tr("appdelegate.dayedge.settings", "DayEdge Settings")
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.titlebarSeparatorStyle = .none
            window.toolbarStyle = .unified
            window.backgroundColor = NSColor(appearance.palette.settings.background)
            window.isReleasedWhenClosed = false
            window.minSize = NSSize(width: 560, height: 400)
            window.centerOnMainScreen()
            window.makeKeyAndOrderFront(nil)
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        presentationStyle.pointer == nil
    }
}
