# Architecture

Paths relative to `Packages/DayEdge/Sources/`.

## Modules
- Dependency graph and import rules: `AGENTS.md`. Allowed imports per target: `scripts/check-modules.sh`.
- Features get services via: Domain protocols; environment (`\.weatherProvider`, `\.eventActionCoordinator`); shell closures (`PanelRouter`); `PanelRevealing` for the panel reveal. Holidays reach `WorkdayStore` from `RootModels`.
- `RootModels` builds the panel object graph once and hands Platform types to features as Domain protocols.
- `CalendarIndex` package never imports EventKit; `CalendarIndexEventKit` is the only adapter.

## Data flow
- Read: `CalendarProvider` (all projection, filtering, ordering) over `IndexedCalendarEventSource` (SQLite). Month dots from day markers without decoding events.
- Write: `EventKitEventEditor` / `EventKitEventRemovalService` → re-locate occurrence (`EventKitOccurrenceFinder`), revalidate, save, announce `CalendarWriteScope` → index refetches those months.
- Index change ⇒ `.calendarEventsDidChange`, only for displayed months.
- `CalendarIndexRuntime`: opens index (temporary fallback, then `UnavailableCalendarEventSource`), syncs while access granted. Low Power/thermal slows outer years, never skips. Reindex = erase + refill near months first.

## Permissions
- Calendar access checked live on every read (`currentAuthorization()`), never stored.
- `CalendarPermissionMonitor` → `AppDelegate.calendarAccessChanged(to:)`.
- Revoked: stop sync, erase all event rows, ignore in-flight fetches, clear menu bar/HUD, show `PermissionStateView` in Month/Day.
- Granted: refill from scratch.
- Reminders permission is separate (`PermissionStateView(.reminders)` in Tasks).

## EventKit gotchas
- `calendarItemIdentifier` ≠ `eventIdentifier` ≠ `calendarItemExternalIdentifier`. Apple Calendar deep link uses `calendarItemIdentifier` + `occurrenceDate ?? startDate`; no fallback.
- `event(withIdentifier:)` is unreliable for recurring occurrences — use `EventKitOccurrenceFinder` (identifier + calendar + exact start).
- `EventEditability` is the single editability rule (popover, menu, chat). Editable = own event, no attendees, writable calendar. Meetings/invitations: read-only; delete allowed with "nobody is told" warning.
- Repeating events: This Event / All Future Events (`EventSpan`).
- Undo of delete recreates from `EventSnapshot.draft` (new identifier); only `EventSnapshot.canRecreate` (no attendees, not repeating).
- Destructive removal gates on raw `EKEvent.status == .canceled`, not UI `EventStatus.cancelled`.

## Structure
- Pure logic (projections, layouts, plans, magnetism) in value types, SwiftUI-free where possible.
- `@Observable` coordinators own non-view work: `PanelRouter` (all cross-feature routes), `ChatCoordinator`, `PanelRefreshCoordinator`, `EventActionCoordinator`.
- `RootView` is presentation only; triggers in `RootView+Lifecycle`, keys in `RootView+Keyboard`.
- Transient `NSPanel`s guard async completions with `presentationGeneration`.
- Status menu: pure `StatusMenuPlan`, rebuilt on each open; navigation sends `PopoverCommand` after the popover is revealed.
- Global meeting-alert pause (`ReminderSuppressionStore`) outranks per-occurrence mutes.

## Weather
- Location unset ⇒ no weather (never guessed). Current Location = one reduced-accuracy fix, permission asked only when chosen. City via MapKit (`PlaceSearch`).
- Open-Meteo, cached per place. Views key weather `.task(id:)` on the location.

## Onboarding
- Shown only to fresh installs (Calendar access undecided and not completed). Effects behind `OnboardingActions` (mock in tests).
- Force: `open --env DAYEDGE_ONBOARDING=1 build/DayEdge.app`. Reset: `defaults delete com.dayedge.app com.dayedge.onboarding.completed`.
