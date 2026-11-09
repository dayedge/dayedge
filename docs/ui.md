# UI

## Resource cost — check before adding anything
- Every feature costs CPU, memory or battery in an always-running app. Justify it; small and worthwhile beats complete.
- Native controls/menus/materials over custom look-alikes.
- Lazy containers for long content; only on-screen views exist. No hidden views kept warm.
- No timers or `TimelineView` redrawing unchanged content. Observe changes; throttle streams (chat ≤ every 50 ms).
- Blur/translucency only where the design needs it; must work with Reduce Transparency.
- Non-presentation work off the main thread, cancelled with the view (`.task(id:)`).
- Caches bounded and keyed.
- New view/popover/long-lived object: run `scripts/memory-report.sh --compare` and report the delta.

## Look
- The main menu-bar panel centers below the calendar icon, clamped horizontally to the status button's screen `visibleFrame`. Its arrow shifts independently, staying at least `cornerRadius + 16 pt` from either edge; at extreme edges, containment and corner clearance take priority over exact alignment. Status-item and display layout changes reposition it; manual panel dragging remains available.
- The Command Window (⌃⌥D) opens centred on the screen under the pointer, a little above the middle, at the size it was left at (`CommandWindowPlacement`, clamped to `visibleFrame`). No title bar: it moves by the band around the command bar's field (the strip above the composer in Ask), `WindowDragBackground`. Command bar on top, the view in the middle, one quiet footer row: the view's selector, then Actions (⌘K). No view switcher, Settings button or key hints: ⌘1–4 and Actions switch views, Actions opens Settings, and the keys live in Actions and the menus.
- Month's agenda is positioned before it shows: an unseen jump counts as prepared (what reveals the window or Month) only once its day is on screen, plus one layout pass (`AgendaScrollCoordinator.reportPrepared`, 0.3 s fallback); a list coming on screen repeats its last unseen jump once (`snapToLastJump`). Taken off screen (rebuilt later), it hands its top row to `rememberMonthPosition`, which brings it back there (not mid-jump: the jump stays the request) — until a date is asked for (Day's, Today, a found item).
- Popover and Command Window are never on screen together; both show the same `RootModels`. Each window's views exist only while it's the open one (mounted as it starts opening, so they settle before it shows); hidden, they redrew and re-laid out with every change made in the other (measured). `RootLifecycle` stays mounted on the popover's root. The Command Window builds only the view on screen.
- Command Window Month: the grid fills the column, each day's events as chips (`MonthEventGridView`; `MonthChipLayout` fits them, "+N more" past that), beside the popover's continuous agenda (`PanelMonthAgenda`). Date numbers follow the compact calendar exactly (`DayNumberRole`: today, other month, weekend, holiday on a working day, regular; holiday names in a tooltip and to VoiceOver); cell surfaces carry the month shown and the selection. Chips come from `MonthEventsStore` (app-wide, in `RootModels`; warmed with the current month at launch, so the first open is filled): the month shown and both neighbours held ready (one `agendaSections` call each, neighbours in the background, at most three months), so moving a month swaps chips in without the grid filling in; the store follows calendar and visibility changes itself, refetching the month shown while its chips stay up — never per selection. Each cell's bottom inset carries the day's shape (`DayBusyStrip`): its meetings across a fixed 8–17 workday (`AppTheme.CommandWindow.busyStripHours`, one scale for every cell), the earlier meeting keeping overlapping time, so one line; all-day, cancelled and declined events left out. Computed from the cell's events, one `Canvas` per cell; removing it is the overlay in `MonthEventCellView` and that file.
- Action Panel (⌘K, `ActionsListView`): a search field, the selection's menu, then the general commands — section separators where the menu has dividers, a submenu one level deep (‹ back row), ✓ on the current choice, › on submenus, key hints where a key does the same, Delete in `workspace.destructive`, the selected row in `workspace.selectedSurface`. The Command Window opens it from the footer's Actions button; the popover has none.
- Command Window Ask: the popover's `ChatView` — its composer takes the command bar's row (no second field), the conversation below, chats in the footer's selector. In `.wide` the user's bubbles widen (`AppTheme.Chat.wideUserBubbleMaxWidth`) and every reply row keeps a reading width at the leading edge (`wideReadingWidth`); the composer's reveal opens to the view's measured width.
- Tasks filters (`TaskFilter`): Today, Next 7 Days (with overdue), All Tasks — they change which tasks show. A filter, then the `TaskBuckets` grouping (`TaskFilter.options`): All Tasks is the document as it was (Needs attention, the lists, Completed); the others show every row by list, without Needs attention (overdue and due today are both, so it would hold all of Today) or Completed. Sections are never filters: Needs Attention, a list and Completed are reached by jumping (`TaskStore.show(section:)`, All Tasks first when the filter leaves the section out). Session-only, on `TaskStore.filter`. Counts come from one pass (`TaskStore.filterCounts`). Search ignores the filter. The popover picks a filter from a native menu beside the title (`TaskScopeMenu`); the chips are the filtered list's sections. ⌥⌘2–4 pick a filter, ⌥⌘1 and ⌘K's "Show List: …" (once typed) jump, from anywhere.
- Command Window Tasks: the sidebar (`TaskSidebarView`: Overview with keycaps, My Lists in their own ~5-row scroll, Completed; the filter rows are selected, the section rows — Needs Attention, the lists, Completed — act as the popover's chips under every filter: a click jumps, the section in view is marked (the hover fill) as scrolling and ← / → move, the lists' viewport follows, and a section the filter leaves empty is dimmed and inert) beside the popover's task document under its own header (`TasksTitleHeader`: the view's name, counts, sort). Same sidebar width and divider as Day. Rows take their wide form from `\.panelLayout` (`TaskRowContent`: due date at the end of the title line, the notes' first line and the list under it); details and menus are the popover's.
- Command Window Day is master–detail: the sidebar's month heading and chevrons are the only date navigation; the timeline's heading is its own (`DayPaneHeading`: "Monday 26" and the counts, the month named only when the sidebar shows another). `DayAgendaView` takes its header from the window composing it (`DayHeaderFacts`); the popover's stays `DayHeaderView`.
- Command Window Day: the mini-month (`PanelMonthGrid`) and the selected day's weather (`DayWeatherPanel`, that day's forecast only; none past the forecast window) beside the timeline, which drops its own weather bar (`showsWeatherBar: false`).
- Theme tokens only (`docs/theming.md`). Every hosting tree wrapped in `ThemedRoot`.
- One `PanelToolbar` + `LargeTitleHeader` at the root, shared by all views. Panel stays flat.
- Switching Month / Day / Tasks / Ask crossfades the content only (`panelColumn`, 0.15 s, opacity); toolbar, search field, switcher and footer never move.
- Search's expanded surface is opaque (`AppTheme.searchSurface`) — overlay bugs there came from translucency.
- Day timeline and chat use the shared dissolve at both scroll edges; Month agenda and search results use it at the bottom. The wide Command Window drops the bottom edge (no bar floats there) and keeps the top. Their bars use plain safe-area insets, with native edge effects hidden. Settings keeps its system treatment.
- `ThemedScrollView(edgeDissolve:)` selects the edges: separate AppKit blur and fade views become direct siblings above its native scroll, outside the SwiftUI probe. Visibility updates only during the 64 pt transition; inactive surfaces and Reduce Transparency / Increase Contrast disable the blur.
- `topDissolve` / `bottomDissolve` configure fade strength, fully opaque height, transparent overscan, blur radius and an optional surface role. Defaults preserve the compact 80 pt profile; Day and chat use `AppTheme.ScrollEdge.tallHeader`, reusing the window surface's material and tint for uniform coverage. Reduce Transparency uses the token's solid tint.
- Day's bar above the timeline (`DayTopBar`: weather, all-day lane) fades panels in and out when one appears or disappears; a timeline still on its programmatic anchor follows the bar. Reduce Motion or hidden: instant.
- Stepping days (`DayAdvance`): the new day arrives 12 pt from the side it lies on while fading in (0.17 s, ease-out); header, weather and timeline together, chrome fixed. Reduce Motion: a 0.1 s fade.

## Decisions
- `TransientNotice`: already happened, with Undo. `DecisionCard`: choice needed. System alerts: OS-level only.
- Reversible actions (complete, delete a task or own single event) never ask — Undo instead.
- Cards show inline in chat or docked at the panel bottom (`DecisionDock`, one at a time). Never separate windows/popovers.
- Toast and docked card share visuals via `BottomSurface`, never state.
- Repeating scope: split button, default This Event. Keys: Esc cancel, ←/→ select, ↩ run; destructive cards start on Cancel.

## Detail cards (event, task)
- Built from `DetailComponents`. One row geometry; never per-row offsets.
- Three editor kinds only: native menu, `PropertyEditor` popover (Cancel · Done, ↩/Esc), inline text (notes: ↩ newline, ⌘↩ done).
- Editor keys never reach the card/panel behind.
- Ask only when needed (repeating scope, no Undo); else save with Undo.

## Menus
- The menu-bar badge strategy supplies its display number and overflow flag. Event counts above nine show `9+`; day-of-month shows the full date number without overflow. Corner glyphs, one at a time, by priority: alerts paused, tasks due, overflow.
- One plan per menu (`EventContextMenuPlan`, `TaskContextMenuPlan`, `StatusMenuPlan`), grouped like Apple Calendar, dividers only between non-empty groups.
- Items are `Label`s with SF Symbols and explicit `.titleAndIcon`; menus reset tint (`.tint(nil)`). The AppKit status menu opts into `preferredImageVisibility` on macOS 27, whose automatic policy hides symbols. Its public setter is called through KVC to keep the Xcode 26 / CLT builds compatible.
- Item shortcuts come from `KeyboardShortcutSettings`. No key deletes an event.
- "Show in Calendar ⇥" appears only on search results (`\.searchResultReveal`).

## Words
- "Show in Calendar/Tasks" = inside DayEdge. "Open in Apple Calendar / Reminders" = Apple's apps. Polish: "w aplikacji Kalendarz".
- Items are "tasks" ("Delete Task…", "No tasks"); "Reminders" (capitalised) names only Apple's app and its permission. Event alerts are "alerts".
- Multi-day labels: en dash ("Continues – 16:45"), never arrows.

## Menu-bar items
- Primary status item: Icon, Date & Time, or Icon and Date & Time, selected in Menu Bar Item settings. Badge and Format rows appear only when relevant; their saved preferences survive mode changes. The former date/time toggle migrates to Icon or Icon and Date & Time. The cached calendar badge and native date/time title share one status item. Presets follow app language, system region and General's hour-cycle preference; Custom shares General's pattern editor and supports minute precision.
- In Icon mode, meeting status shares the primary item with separate calendar/Join click regions. Modes containing date/time use the independent, stable meeting item. The existing meeting resolver controls visibility in both layouts. Join and right-click menu behavior are preserved. Text/countdown changes never render an icon bitmap.
- Each item's image cache retains only its last key/image, including its screen scale. Date/time and meeting text are independent of these keys. Status-item autosave names use the app bundle identifier to keep Dev and Release separate.
