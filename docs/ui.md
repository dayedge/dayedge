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
- Theme tokens only (`docs/theming.md`). Every hosting tree wrapped in `ThemedRoot`.
- One `PanelToolbar` + `LargeTitleHeader` at the root, shared by all views. Panel stays flat.
- Search's expanded surface is opaque (`AppTheme.searchSurface`) — overlay bugs there came from translucency.

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
- Items are `Label`s with SF Symbols; menus reset tint (`.tint(nil)`).
- Item shortcuts come from `KeyboardShortcutSettings`. No key deletes an event.
- "Show in Calendar ⇥" appears only on search results (`\.searchResultReveal`).

## Words
- "Show in Calendar/Tasks" = inside DayEdge. "Open in Apple Calendar / Reminders" = Apple's apps. Polish: "w aplikacji Kalendarz".
- Event alerts are "alerts"; Reminders are "tasks".
- Multi-day labels: en dash ("Continues – 16:45"), never arrows.
