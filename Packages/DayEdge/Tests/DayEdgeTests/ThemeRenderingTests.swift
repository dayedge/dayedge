import AppKit
import EventKit
import SwiftUI
import XCTest

@testable import Shell
@testable import Domain
@testable import UI
@testable import Agenda
@testable import Tasks
@testable import Intelligence

@MainActor
final class ThemeRenderingTests: XCTestCase {
    func testHostedThemeChangesKeepStateAndUpdateNativeWindow() {
        let store = AppearanceStore(defaults: UserDefaults(suiteName: "ThemeRender-\(UUID())")!, observesSystem: false)
        var observations: [(Bool, UUID)] = []
        let probe = PaletteProbe { observations.append(($0, $1)) }.equatable()
            .surfaceElevation(.floatingControl)
        let hosting = NSHostingView(rootView: ThemedRoot(content: probe, usesWindowBackground: true, appearance: store))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 100),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = hosting
        defer { window.contentView = nil }
        settle(hosting)
        XCTAssertEqual(window.appearance?.bestMatch(from: [.aqua, .darkAqua]), .darkAqua)
        let initialIdentity = observations.first?.1
        XCTAssertNotNil(initialIdentity)

        store.selectTheme("apple-light")
        settle(hosting)
        XCTAssertEqual(window.appearance?.bestMatch(from: [.aqua, .darkAqua]), .aqua)
        XCTAssertEqual(observations.last?.0, true)
        XCTAssertEqual(observations.last?.1, initialIdentity)

        store.selectTheme("apple-system")
        store.updateSystemAppearance(NSAppearance(named: .darkAqua)!)
        settle(hosting)
        XCTAssertEqual(window.appearance?.bestMatch(from: [.aqua, .darkAqua]), .darkAqua,
                       "System themes set the Mac's resolved appearance explicitly")
        XCTAssertEqual(observations.last?.0, false)
        XCTAssertEqual(observations.last?.1, initialIdentity)

        store.selectTheme("frost")
        settle(hosting)
        XCTAssertEqual(window.appearance?.bestMatch(from: [.aqua, .darkAqua]), .darkAqua)
        XCTAssertFalse(window.isOpaque)
        XCTAssertEqual(window.backgroundColor, .clear)
        store.updateSystemAppearance(NSAppearance(named: .aqua)!)
        settle(hosting)
        XCTAssertEqual(observations.last?.1, initialIdentity)
        XCTAssertEqual(observations.last?.0, true)
        store.selectTheme("apple-dark")
        settle(hosting)
        XCTAssertTrue(window.isOpaque, "Leaving material restores the original native window opacity")
        XCTAssertEqual(observations.last?.1, initialIdentity)
    }

    /// Opt-in mock-data board of actual app components for visual QA; never touches real calendars.
    func testRenderThemeBoardsWhenRequested() throws {
        guard let output = ProcessInfo.processInfo.environment["DAYEDGE_THEME_RENDER_DIR"] else {
            throw XCTSkip("Set DAYEDGE_THEME_RENDER_DIR to render visual theme fixtures")
        }
        let directory = URL(fileURLWithPath: output, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for id in ["opal", "apple-light", "apple-dark", "one-dark-pro", "graphite-pro", "quartz-pro"] {
            let store = AppearanceStore(
                defaults: UserDefaults(suiteName: "ThemeBoard-\(UUID())")!, observesSystem: false)
            store.selectTheme(id)
            try render(
                ThemeBoard(themeTitle: store.definition.title), store: store, size: NSSize(width: 440, height: 740),
                to: directory.appendingPathComponent("\(id).png"))
            try render(
                GeneralSettingsView().frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .background(store.palette.settings.background),
                store: store, size: NSSize(width: 620, height: 480),
                to: directory.appendingPathComponent("\(id)-general-settings.png"))
            let repository = TaskRepository(
                provider: MockTaskDataProvider(),
                listVisibility: SourceVisibilityStore(kind: .taskLists))
            let settings = SettingsRootView(
                visibilityStore: SourceVisibilityStore(kind: .calendars), taskRepository: repository,
                assistantSettings: AssistantSettingsStore(
                    fileURL: directory.appendingPathComponent("unused-settings.json")),
                router: SettingsRouter(), eventStore: EKEventStore()
            )
            try render(
                settings, store: store, size: NSSize(width: 860, height: 620),
                to: directory.appendingPathComponent("\(id)-settings.png"))
            try render(
                ThemeDetailBoard(), store: store, size: NSSize(width: 820, height: 570),
                to: directory.appendingPathComponent("\(id)-details-chat.png"))
            try render(
                ThemeEditorBoard(), store: store, size: NSSize(width: 440, height: 610),
                to: directory.appendingPathComponent("\(id)-editor.png"))
            try render(
                ThemeTimelineBoard(), store: store, size: NSSize(width: 620, height: 260),
                to: directory.appendingPathComponent("\(id)-timeline.png"))
            let day = Date(timeIntervalSince1970: 1_791_110_400)
            let event = AgendaEventModel(
                id: "meeting", startTime: "09:00", endTime: "10:00",
                startDate: day, endDate: day.addingTimeInterval(3600),
                title: "Design review", videoService: .zoom, tint: .purple,
                calendarName: "Work", videoURL: "https://zoom.us/j/123456789")
            let occurrence = MeetingHUDOccurrence(event: event, start: day, end: day.addingTimeInterval(3600))
            try render(
                MeetingHUDView(occurrence: occurrence, interactionState: CompactMeetingHUDInteractionState()),
                store: store, size: NSSize(width: 680, height: 110),
                to: directory.appendingPathComponent("\(id)-hud.png"))
            let takeover = MeetingTakeoverView(
                state: MeetingTakeoverState(
                    occurrence: occurrence, now: day.addingTimeInterval(-120), activeDisplayID: 1),
                displayID: 1, onJoin: {}, onSnoozeSmart: {}, onSnoozeDuration: { _ in }, onDismiss: {}
            )
            try render(
                takeover.transaction {
                    $0.animation = nil
                    $0.disablesAnimations = true
                },
                store: store, size: NSSize(width: 1000, height: 750),
                to: directory.appendingPathComponent("\(id)-takeover.png"))
        }
    }

    func testRenderFrostScreensWhenRequested() async throws {
        guard let output = ProcessInfo.processInfo.environment["DAYEDGE_THEME_RENDER_DIR"] else {
            throw XCTSkip("Set DAYEDGE_THEME_RENDER_DIR for material visual fixtures")
        }
        let directory = URL(fileURLWithPath: output, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let defaults = UserDefaults(suiteName: "FrostScreens-\(UUID())")!
        let tasks = TaskStore(provider: MockTaskDataProvider(), defaults: defaults)
        await tasks.load()
        let chat = ChatSession()
        chat.start(with: "Help me prepare for my next meeting")
        await chat.settle()
        let notice = NoticeCenter()
        notice.show(.init(style: .success, title: "Task completed", action: .init(title: "Undo", handler: {}), duration: 60))
        defer { notice.dismiss(); chat.cancel() }
        for light in [true, false] {
            let palette = SearchPaletteModel(resolveDate: { text, _, _ in .freeTextSearch(text) },
                                             resolveTask: { _, _, _, _, _ in nil })
            palette.update(query: "Design review")
            await palette.settle()

            let store = AppearanceStore(defaults: defaults, observesSystem: false, systemScheme: light ? .light : .dark)
            store.selectTheme("frost")
            let prefix = light ? "frost-light" : "frost-dark"
            try render(ThemeBoard(themeTitle: "Frost"), store: store, size: NSSize(width: 440, height: 740),
                       to: directory.appendingPathComponent("\(prefix)-month.png"))
            try render(ThemeTimelineBoard(), store: store, size: NSSize(width: 620, height: 260),
                       to: directory.appendingPathComponent("\(prefix)-timeline.png"))
            try render(ThemeEditorBoard(), store: store, size: NSSize(width: 440, height: 610),
                       to: directory.appendingPathComponent("\(prefix)-editor.png"))
            try render(ThemeDetailBoard(), store: store, size: NSSize(width: 820, height: 570),
                       to: directory.appendingPathComponent("\(prefix)-details.png"))
            try render(FrostInteractionBoard(tasks: tasks, chat: chat, palette: palette, notice: notice),
                       store: store, size: NSSize(width: 1320, height: 720),
                       to: directory.appendingPathComponent("\(prefix)-interactions.png"))

        }
    }

    private func render<Content: View>(_ content: Content, store: AppearanceStore, size: NSSize, to url: URL) throws {
        let view = NSHostingView(rootView: ThemedRoot(content: content, appearance: store))
        view.sizingOptions = []
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless], backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.contentView = view
        defer { window.orderOut(nil); window.contentView = nil }
        view.frame = NSRect(origin: .zero, size: size)
        settle(view)
        // Simulate the system appearance on this temporary fixture window only.
        window.appearance = NSAppearance(named: store.colorScheme == .light ? .aqua : .darkAqua)
        settle(view)
        // Native scroll/material layers cannot be faithfully cached offscreen.
        // Opt-in window capture exercises the actual compositor without real calendar data.
        if store.themeID == "frost", ProcessInfo.processInfo.environment["DAYEDGE_THEME_CAPTURE_WINDOWS"] == "1" {
            window.center()
            // Controlled bright, dark and saturated content behind native desktop blur.
            let backdrop = NSWindow(contentRect: window.frame.insetBy(dx: -30, dy: -30),
                                    styleMask: [.borderless], backing: .buffered, defer: false)
            backdrop.contentView = MaterialBackdropProbe(frame: NSRect(origin: .zero, size: backdrop.frame.size))
            backdrop.orderFrontRegardless()
            defer { backdrop.orderOut(nil); backdrop.contentView = nil }
            window.orderFrontRegardless()
            for _ in 0..<16 { settle(view) }
            let capture = Process()
            capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            let top = NSScreen.screens.first!.frame.maxY - window.frame.maxY
            let region = "\(Int(window.frame.minX)),\(Int(top)),\(Int(window.frame.width)),\(Int(window.frame.height))"
            // A screen-region capture includes the WindowServer's behind-window blur;
            // isolated -l captures can flatten/remove that backdrop contribution.
            capture.arguments = ["-x", "-R", region, url.path]
            try capture.run()
            capture.waitUntilExit()
            XCTAssertEqual(capture.terminationStatus, 0, "Native window capture failed")
            return
        }
        let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: url)
    }

    private func settle(_ view: NSView) {
        for _ in 0..<4 {
            view.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.025))
        }
    }
}

private struct PaletteProbe: View, Equatable {
    @Environment(\.themePalette) private var theme
    @State private var identity = UUID()
    let report: (Bool, UUID) -> Void

    static func == (lhs: Self, rhs: Self) -> Bool { true }

    var body: some View {
        Text("Palette probe")
            .foregroundStyle(theme.primaryText)
            .onChange(of: theme.isLight, initial: true) { _, value in report(value, identity) }
    }
}

private struct ThemeBoard: View {
    let themeTitle: String
    @Environment(\.themePalette) private var theme
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(secondsFromGMT: 0)!
        c.firstWeekday = 2
        return c
    }
    private var day: Date { calendar.date(from: DateComponents(year: 2026, month: 10, day: 4))! }
    private var events: [AgendaEventModel] {
        [
            .init(
                id: "accepted", startTime: "09:00", endTime: "10:00", title: "Design review", subtitle: "Studio",
                tint: .purple),
            .init(
                id: "tentative", startTime: "11:00", endTime: "11:30", title: "Planning", status: .tentative,
                tint: .orange),
            .init(
                id: "cancelled", startTime: "13:00", endTime: "14:00", title: "Cancelled meeting", status: .cancelled,
                tint: .blue),
        ]
    }

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Text("Search").font(.system(size: 13)).foregroundStyle(theme.secondaryText)
                Spacer()
                ViewModeSwitcherView(selectedMode: .month, onSelect: { _ in })
            }
            .padding(.horizontal, 18)
            MonthHeaderView(monthTitle: "October", yearTitle: "2026", onToday: {}, onPrevious: {}, onNext: {})
            WeekdayRowView(symbols: ["M", "T", "W", "T", "F", "S", "S"])
            MonthGridView(
                days: previewDays, selectedDate: calendar.date(byAdding: .day, value: 1, to: day)!,
                onSelect: { _ in }, eventsProvider: { _ in events })
            ForEach(events) { event in
                AgendaEventRowView(event: event, date: day, isKeyboardSelected: event.id == "accepted")
            }
            TaskRowView(
                task: .init(id: "task", title: "Prepare notes", listID: "work"), tint: .purple,
                isSelected: false, isDetailPresented: false, onToggle: {}, onTap: {})
            HStack {
                CalendarDateTile(date: day, isToday: true)
                Text("Today").foregroundStyle(theme.todayAccent)
                Spacer()
                KeyboardShortcutHint(key: "↩", action: "Open", accessibilityLabel: "Open")
            }.padding(.horizontal, 18)
            SettingsGroup(header: "Appearance") {
                SettingsRow(title: "Theme") {
                    Text(themeTitle).foregroundStyle(theme.primaryText)
                }
                SettingsToggleRow(title: "Show weather", isOn: .constant(true))
            }.padding(.horizontal, 18)
            DetailValueLabel(icon: "clock", text: "09:00 – 10:00", isKeyboardSelected: true)
                .padding(.horizontal, 18)
            HStack(spacing: 0) {
                NowIndicatorView(minutesSinceMidnight: 0).frame(height: 18)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 15)
        .themedSurface(.window, fill: theme.background, in: Rectangle())
    }

    private var previewDays: [DayCellModel] {
        MockCalendarDataProvider().days(for: day, selectedDate: day, calendar: calendar).map { cell in
            DayCellModel(
                date: cell.date, dayNumber: cell.dayNumber, isCurrentMonth: cell.isCurrentMonth,
                isToday: calendar.isDate(cell.date, inSameDayAs: day), isSelected: false,
                isWeekend: cell.isWeekend, dots: cell.dots)
        }
    }
}

private struct ThemeDetailBoard: View {
    @Environment(\.themePalette) private var theme
    @FocusState private var composerFocus: Bool
    private let day = Date(timeIntervalSince1970: 1_791_110_400)

    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            TaskDetailPopoverView(
                task: .init(
                    id: "task", title: "Prepare design notes", notes: "Review the calendar colors.",
                    listID: "work", dueDate: day, hasDueTime: true, priority: .high),
                lists: [], onEdit: { _ in }, onToggleCompleted: {}
            )
            VStack(alignment: .leading, spacing: 20) {
                Text("Ask DayEdge").font(.system(size: 26, weight: .bold)).foregroundStyle(theme.primaryText)
                Text("Show my agenda for today.")
                    .font(AppTheme.Chat.messageFont).foregroundStyle(theme.chat.userBubbleText)
                    .padding(12).background(theme.chat.userBubbleFill, in: RoundedRectangle(cornerRadius: 12))
                Text("You have a design review and notes to prepare.")
                    .font(AppTheme.Chat.assistantFont).foregroundStyle(theme.chat.assistantText)
                ChatSuggestionChips(onChoose: { _ in })
                ChatComposerView(
                    draft: .constant("Review my day"), canSend: true,
                    focus: $composerFocus, onSend: {})
                EventDetailPopoverView(
                    event: .init(
                        id: "event", startTime: "09:00", endTime: "10:00",
                        title: "Design review", subtitle: "Studio", tint: .purple,
                        calendarName: "Work", notes: "Bring sketches."), date: day)
            }
            .frame(width: 390)
        }
        .padding(10)
        .themedSurface(.window, fill: theme.background, in: Rectangle())
    }
}

/// Real timeline cards with vivid source colors; appearance effects stay confined to the fills.
private struct ThemeTimelineBoard: View {
    @Environment(\.themePalette) private var theme
    private let day = Date(timeIntervalSince1970: 1_791_110_400)

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            DayHeaderView(date: day, isToday: true, eventCount: 3, onPrevious: {}, onNext: {})
            HStack(alignment: .top, spacing: 12) {
                card("Planning", color: .orange, status: .confirmed)
                card("Product review", color: .teal, status: .confirmed)
                card("Tentative meeting", color: .orange, status: .tentative)
            }
            .padding(.horizontal, 18)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .themedSurface(.window, fill: theme.background, in: Rectangle())
    }

    private func card(_ title: String, color: RGBAColor, status: EventStatus) -> some View {
        DayTimelineEventView(
            event: .init(id: title, startTime: "09:00", endTime: "10:00", title: title,
                subtitle: "Design studio", status: status, tint: color),
            date: day, height: 115)
    }
}

/// Existing event/task editors and field states, without real calendar writes or open popovers.
private struct ThemeEditorBoard: View {
    @Environment(\.themePalette) private var theme
    @FocusState private var focus: QuickAddField?
    @State private var eventEdit: EventQuickAddEdit
    @State private var taskEdit: QuickAddEdit
    @State private var openEditor: QuickAddField?
    private let day = Date(timeIntervalSince1970: 1_791_110_400)
    private let source = CalendarSource(id: "work", title: "Work", tint: .purple)

    init() {
        let reference = Date(timeIntervalSince1970: 1_791_110_400)
        var event = QuickAddDraft(title: "Product review", confidence: 1, spans: [])
        event.eventTitle = event.title
        event.day = reference
        event.startTime = DateComponents(hour: 9, minute: 0)
        event.endTime = DateComponents(hour: 10, minute: 0)
        event.calendarID = "work"
        _eventEdit = State(initialValue: EventQuickAddEdit(draft: event, calendar: .autoupdatingCurrent, referenceDate: reference))
        var task = QuickAddDraft(title: "Prepare review notes", confidence: 1, spans: [])
        task.listID = "work"
        _taskEdit = State(initialValue: QuickAddEdit(draft: task, calendar: .autoupdatingCurrent, referenceDate: reference))
    }

    private var overlapEvent: AgendaEventModel {
        .init(id: "overlap", startTime: "09:00", endTime: "09:30", title: "Planning meeting", tint: .teal)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Search").font(.system(size: 13)).foregroundStyle(theme.secondaryText)
            EventQuickAddEditorView(
                edit: $eventEdit, calendars: [source],
                overlap: EventOverlap(conflict: .busy, event: overlapEvent),
                overlapRow: { event in AgendaEventRowView(event: event, date: day) },
                focus: $focus, openEditor: $openEditor, iconColumn: 18, iconToText: 10)
                .padding(.horizontal, 12).padding(.vertical, 10)
                .themedSurface(.nested, fill: theme.editor.panelFill, in: RoundedRectangle(cornerRadius: 12))
            QuickAddEditorView(edit: $taskEdit, lists: [source], focus: $focus, openEditor: $openEditor,
                iconColumn: 18, iconToText: 10)
                .padding(.horizontal, 12).padding(.vertical, 10)
                .themedSurface(.nested, fill: theme.editor.panelFill, in: RoundedRectangle(cornerRadius: 12))
            QuickAddControl(text: "4 Oct 2026", isPlaceholder: false, hasMenu: false,
                isFocused: true, minWidth: 100)
            Spacer(minLength: 0)
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .themedSurface(.transient, fill: theme.searchSurface, in: Rectangle())
    }
}

/// Actual shared screens and transient components, with isolated mock state.
private struct FrostInteractionBoard: View {
    @Environment(\.themePalette) private var theme
    @FocusState private var searchFocus: Bool
    let tasks: TaskStore
    let chat: ChatSession
    let palette: SearchPaletteModel
    let notice: NoticeCenter
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            TasksView(store: tasks, query: "", isActive: false, navigationRequest: nil)
                .frame(width: 420)
                .floatingSurface(radius: FloatingSurface.calendarRadius)
            ChatView(session: chat, isPresented: true,
                     objects: .init(event: { _, _ in nil }, taskActions: tasks.actions,
                                    taskCoordinator: CalendarTaskCoordinator(actions: tasks.actions))) {
                FooterBarView(label: "New Chat", isPresented: .constant(false), onSettingsTap: {}) { EmptyView() }
            }
                .frame(width: 420)
                .floatingSurface(radius: FloatingSurface.calendarRadius)
            VStack(spacing: 30) {
                SearchBarView(query: .constant("Design review"), searchFocus: $searchFocus, palette: palette)
                Spacer(minLength: 0)
                DecisionCardSurface(title: "Allow this change?", symbol: "checkmark.shield", placement: .docked) {
                    Text("Create a task in your Work list.").foregroundStyle(theme.secondaryText)
                } actions: {
                    Button("Cancel") {}
                    Button("Allow") {}
                }
                TransientNoticeHost(center: notice).frame(height: 100)
            }
            .padding(.vertical, 18)
            .frame(width: 420)
            .floatingSurface(radius: FloatingSurface.calendarRadius)
        }
        .padding(12)
    }
}

private final class MaterialBackdropProbe: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let colors: [NSColor] = [.white, .black, .systemOrange, .systemBlue]
        for (index, color) in colors.enumerated() {
            color.setFill()
            NSRect(x: CGFloat(index) * bounds.width / 4, y: 0,
                   width: bounds.width / 4, height: bounds.height).fill()
        }
    }
}
