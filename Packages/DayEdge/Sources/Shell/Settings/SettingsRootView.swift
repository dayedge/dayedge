import EventKit
import SwiftUI
import Domain
import UI
import Intelligence

/// The Settings window: a sidebar of panes and a detail column of grouped
/// forms, styled with the popup's own palette (`ThemePalette.settings`).
struct SettingsRootView: View {
    @Environment(\.themePalette) private var theme
    @Environment(\.colorScheme) private var colorScheme

    let visibilityStore: SourceVisibilityStore
    let taskRepository: TaskRepository
    let assistantSettings: AssistantSettingsStore
    let router: SettingsRouter
    let eventStore: EKEventStore
    /// The calendar index's activity; nil without an index (mock data).
    var indexActivity: CalendarIndexActivity?
    var onShowMeetingHUDPreview: () -> Void = {}
    var onShowWelcome: () -> Void = {}

    @State private var selection: SettingsDestination? = .general
    /// Visited panes for the back/forward buttons, browser-style.
    @State private var history: [SettingsDestination] = [.general]
    @State private var historyIndex = 0
    @State private var isNavigatingHistory = false

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Rectangle()
                .fill(theme.settings.divider)
                .frame(width: 0.5)
            detailColumn
        }
        // Rebuilt when the appearance flips: AppKit-backed controls
        // (pop-up buttons, switches, the sidebar) otherwise sometimes keep
        // the old appearance's text — white on white after dark → light.
        .id(colorScheme)
        .ignoresSafeArea(edges: .top)
        .frame(minWidth: 680, minHeight: 480)
        .themedSurface(.window, fill: theme.settings.background, in: Rectangle())

        .tint(theme.settings.tint)
        .onChange(of: selection) { _, pane in
            if let pane { record(pane) }
        }
        // Open on the pane another part of the app asked for ("Manage…").
        .onChange(of: router.request) { _, request in
            if let request { selection = request.pane }
        }
        .onAppear {
            if let request = router.request { selection = request.pane }
        }
    }

    /// A flat, full-height darker column (not the floating rounded sidebar
    /// `NavigationSplitView` draws on macOS 26).
    private var sidebar: some View {
        List(selection: $selection) {
            Section {
                ForEach([SettingsDestination.general, .calendars, .tasks, .menuBar, .meetings, .intelligence, .shortcuts]) { row($0) }
            }
            Section {
                row(.about)
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        // Clears the traffic lights, which sit over this column.
        .safeAreaPadding(.top, AppTheme.Settings.titlebarHeight)
        .frame(width: AppTheme.Settings.sidebarWidth)
        .frame(maxHeight: .infinity)
        .background(theme.settings.sidebarBackground)
    }

    private var detailColumn: some View {
        let pane = selection ?? .general
        // Material themes (Frost): the window's surface is the desktop
        // behind it, which the scroll edge effect can't sample — under the
        // bar it came out see-through. There the bar carries the window's
        // own surface instead.
        let isMaterialWindow = theme.surfaces != nil
        return ThemedScrollView(appliesTopEdgeEffect: !isMaterialWindow) {
            detail(for: pane)
                .frame(maxWidth: .infinity, alignment: .top)
        }
        // A registered top bar, so options scrolling underneath it get the
        // system's Liquid Glass edge blur instead of running behind it.
        .floatingTopBar {
            HStack(spacing: 12) {
                SettingsHistoryButtons(
                    canGoBack: historyIndex > 0,
                    canGoForward: historyIndex < history.count - 1,
                    onBack: { move(by: -1) },
                    onForward: { move(by: 1) }
                )
                Text(pane.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(theme.settings.primaryText)
                Spacer()
            }
            .padding(.horizontal, 14)
            .frame(height: AppTheme.Settings.titlebarHeight)
            .background {
                if isMaterialWindow {
                    ThemedSurface(role: .window, fill: theme.settings.background, shape: Rectangle())
                        .ignoresSafeArea(edges: .top)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func record(_ pane: SettingsDestination) {
        if isNavigatingHistory {
            isNavigatingHistory = false
            return
        }
        guard history[historyIndex] != pane else { return }
        history = Array(history.prefix(historyIndex + 1)) + [pane]
        historyIndex = history.count - 1
    }

    private func move(by offset: Int) {
        let target = historyIndex + offset
        guard history.indices.contains(target) else { return }
        historyIndex = target
        isNavigatingHistory = true
        selection = history[target]
    }

    private func row(_ pane: SettingsDestination) -> some View {
        Label {
            Text(pane.title)
                .foregroundStyle(theme.settings.primaryText)
        } icon: {
            // Dark-theme variant of the colored tile: the hue is kept but
            // deepened, with a soft top-lit gradient and hairline edge, so
            // it reads like System Settings in dark mode, not a bright badge.
            Image(systemName: pane.symbolName)
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(theme.settings.iconGlyph)
                .frame(width: 22, height: 22)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(pane.iconColor(theme: theme).mix(with: .black, by: theme.settings.iconDarkening).gradient)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(theme.settings.iconKeyline, lineWidth: 0.5)
                )
        }
        .tag(pane)
    }

    @ViewBuilder
    private func detail(for pane: SettingsDestination) -> some View {
        switch pane {
        case .general: GeneralSettingsView()
        case .calendars: CalendarsSettingsView(visibilityStore: visibilityStore, eventStore: eventStore,
                                               indexActivity: indexActivity)
        case .tasks: TasksSettingsView(repository: taskRepository)
        case .menuBar: MenuBarSettingsView()
        case .meetings: MeetingHUDSettingsView(onShowPreview: onShowMeetingHUDPreview)
        case .intelligence: IntelligenceSettingsView(store: assistantSettings)
        case .shortcuts: ShortcutsSettingsView()
        case .about: AboutSettingsView(onShowWelcome: onShowWelcome)
        }
    }
}
