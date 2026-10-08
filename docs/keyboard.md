# Keyboard

## Shortcuts (`UI/Presentation`)
- `ShortcutCommand` = identity. `KeyboardCommands` = defaults + `fixedKeys` (keys other handlers own). `KeyboardShortcutSettings.shared` = the only store; monitors, menus, tooltips and Settings read it.
- Recordable: Today, Focus Search, ⌘1–4, Join ⌘J, Copy Link ⇧⌘C, Open in Apple Calendar ⌘O, occurrences ⌘] / ⌘[, Sort Tasks (unassigned). Navigation keys are fixed.
- Matching: modifiers ⌘⌥⌃⇧; special keys by key code; others by layout base character.
- Storage: overrides only, UserDefaults `com.dayedge.shortcuts` (JSON, `"none"` = cleared, bad data ⇒ defaults).
- One key, one command: overrides first, then defaults; a taken key leaves the later command unassigned.
- Eligible keys need ⌘ or ⌃ and mustn't be needed by the search field/macOS.
- `resolve(_:)` does nothing while recording, while a menu tracks, on auto-repeat of one-shot commands, or for unbound keys. Event commands re-read the selected event first and run only if its menu offers the item.
- `ShortcutRecorder`: local monitor on its own window only; no global monitors, no permissions.

## Quick Add
- Collapsed: ↩ and ⌘↩ create.
- Expanded: ⌘↩ creates from anywhere (closes an open picker first; respects IME composition). ↩ never creates — opens the focused picker. Tab/⇧Tab walk fields. Esc: close picker, then collapse.
- Collapsing keeps edits; a new query resets.
- Footer: "⇥ Edit ↵ Create" / "esc Back ⌘↵ Create" (pl "Wstecz").

## Priority
Decision card → detail card → panel (`ActionShortcutMonitor`), own window only, never while a text field edits.
