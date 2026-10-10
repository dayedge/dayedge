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
- Theme tokens only (`docs/theming.md`). Every hosting tree wrapped in `ThemedRoot`.
- One `PanelToolbar` + `LargeTitleHeader` at the root, shared by all views. Panel stays flat.
- Switching Month / Day / Tasks / Ask crossfades the content only (`panelColumn`, 0.15 s, opacity); toolbar, search field, switcher and footer never move.
- Search's expanded surface is opaque (`AppTheme.searchSurface`) — overlay bugs there came from translucency.
- Day timeline and chat use the shared dissolve at both scroll edges; Month agenda and search results use it at the bottom. Their bars use plain safe-area insets, with native edge effects hidden. Settings keeps its system treatment.
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
- One plan per menu (`EventContextMenuPlan`, `TaskContextMenuPlan`, `StatusMenuPlan`), grouped like Apple Calendar, dividers only between non-empty groups.
- Items are `Label`s with SF Symbols and explicit `.titleAndIcon`; menus reset tint (`.tint(nil)`). The AppKit status menu opts into `preferredImageVisibility` on macOS 27, whose automatic policy hides symbols. Its public setter is called through KVC to keep the Xcode 26 / CLT builds compatible.
- Item shortcuts come from `KeyboardShortcutSettings`. No key deletes an event.
- "Show in Calendar ⇥" appears only on search results (`\.searchResultReveal`).

## Words
- "Show in Calendar/Tasks" = inside DayEdge. "Open in Apple Calendar / Reminders" = Apple's apps. Polish: "w aplikacji Kalendarz".
- Items are "tasks" ("Delete Task…", "No tasks"); "Reminders" (capitalised) names only Apple's app and its permission. Event alerts are "alerts".
- Multi-day labels: en dash ("Continues – 16:45"), never arrows.
