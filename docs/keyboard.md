# Keyboard

## Shortcuts (`UI/Presentation`)
- `PanelCommand` = what the user can ask for (`.action(PanelAction)` / `.viewMode` / `.taskView`; the view switches run from `ViewModeShortcutMonitor`, even while typing), whatever invokes it — a key, a menu, the Actions list. `PanelCommands` = defaults + `fixedKeys` (keys other handlers own). `KeyboardShortcutSettings.shared` = the only store; monitors, menus, tooltips and Settings read it. `PanelKeyHandler` runs them.
- Recordable: New Event ⌘N, New Task ⇧⌘N, New Chat ⌥⌘N, Actions ⌘K, Today, Focus Search, ⌘1–4, Tasks ⌥⌘1–4 (⌥⌘1 jumps to Needs attention; ⌥⌘2–4 filter Today, Next 7 Days, All Tasks; they open Tasks), Join ⌘J, Copy Link ⇧⌘C, Open in Apple Calendar ⌘O, occurrences ⌘] / ⌘[, Sort Tasks (unassigned). Navigation keys are fixed.
- Matching: modifiers ⌘⌥⌃⇧; special keys by key code; others by layout base character.
- Storage: overrides only, UserDefaults `com.dayedge.shortcuts` (JSON, `"none"` = cleared, bad data ⇒ defaults).
- One key, one command: overrides first, then defaults; a taken key leaves the later command unassigned.
- Eligible keys need ⌘ or ⌃ and mustn't be needed by the search field/macOS.
- `resolve(_:)` does nothing while recording, while a menu tracks, on auto-repeat of one-shot commands, or for unbound keys. Event commands re-read the selected event first and run only if its menu offers the item.
- `ShortcutRecorder`: local monitor on its own window only; no global monitors, no permissions.

## Global shortcut
- One: ⌃⌥D shows or hides the Command Window (`CommandWindowShortcut`, `KeyboardShortcuts` package — a system hot key, no event monitor, no permissions). Xcode builds only. Not configurable yet; the package stores overrides under `KeyboardShortcuts_toggleCommandWindow`. Taken by another app ⇒ nothing happens.
- The Command Window uses the panel's keys (`PanelKeyHandler`) unchanged. Esc unwinds as in the popover; with nothing left to close and an empty query it hides the window (the popover only leaves the field). In Ask, Esc denies a pending change or stops a reply first; with nothing to stop it hides the window.

## New Event / New Task
- ⌘N / ⇧⌘N open Quick Add on an empty event / task (`SearchPaletteModel.startCreating`): no parsing, no ranking; the default list or calendar, no due date / the next whole hour for an hour. From Ask they go back to the calendar view first. Esc closes it in one step (there's no result list to fold into).

## Actions (⌘K)
- The selection's right-click menu first — same items, order, dividers, submenus (Priority, Due Date) with the current value checked, Delete styled destructive — run by the same executors as that menu (`PanelKeyHandler.run`: the Tasks view's store, the calendar's row completion). While search shows (palette or Search view), the selection is the result highlighted there (`SearchPaletteModel.highlightedResult`), with search's own menu (Show in Calendar = Tab); none highlighted, only the general commands; then, below a separator, what can always be done here: New Event, New Task, Today, Sort Tasks (Tasks), the other views, the Tasks views, New Chat, Settings. Searchable by title (`PanelActionList`, no parsing); a query flattens submenus ("Priority: High").
- Keys, the field keeping focus: ↑ ↓ choose, ↩ runs or opens a submenu, → opens one, ← leaves it, Esc leaves it then closes, ⌘K closes. `PanelKeyHandler.run` runs a row; ↑ ↓ ↩ in its field, Esc or ⌘K close it and focus returns to the search field.
- Tasks: the four Overview commands are always listed; a Reminders list ("Show List: Work", `ActionRow.taskList`, jumps to its section) only once a query matches it — too many to list unasked.
- Command Window only: the footer's Actions button. The popover has none; there ⌘K goes on unused.
- App-wide commands (New Event/Task/Chat, Actions, Settings, Today, Focus Search) also run while typing, with the palette open and in Ask (`PanelAction.worksWhileEditing`).

## Quick Add
- Collapsed: ↩ and ⌘↩ create.
- Expanded: ⌘↩ creates from anywhere (closes an open picker first; respects IME composition). ↩ never creates — opens the focused picker. Tab/⇧Tab walk fields. Esc: close picker, then collapse.
- Collapsing keeps edits; a new query resets.
- Footer: "⇥ Edit ↵ Create" / "esc Back ⌘↵ Create" (pl "Wstecz").

## Priority
Decision card → detail card → panel (`ActionShortcutMonitor`), own window only, never while a text field edits.
