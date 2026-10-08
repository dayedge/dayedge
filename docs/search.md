# Search

`Intelligence/Search/`, `Intelligence/QuickAdd/`.

- `SearchIntentPipeline`: ordered stages, first match wins → `SearchIntent` (`.jumpToDate`, `.jumpToMonth`, `.freeTextSearch`). Don't change this contract for UI tweaks.
- `chrono.js` runs in JavaScriptCore on a private serial queue.
- `SearchBarView` resolves while typing; `PanelRouter.handle(_:)` executes.

## Operators
- `subject:` `from:` (`from:me`) `with:` `type:` `day:` `before:` `after:` `between:`
- `SearchQuerySyntax` (pure; unknown `key:` stays text; empty value ignored) → `SearchQueryResolver` (`before` exclusive, `after` inclusive) → `SearchQueryParts` → one `SearchRequest` (column FTS: title, organizer, attendees; a date range alone needs no text).
- Operators never affect ranking. Operator queries offer no Go to / Create.

## Results
- Events: index FTS. Tasks: `TaskSearch`.
- `SearchDateFilter` splits a day/month phrase into a range ("standup tomorrow"). A date alone = Go to.
- Palette top 3: `SearchRelevance` (title tier, bm25, closeness to now).
- Search view: day-grouped, chronological, no recurring dedupe.

## Quick Add
Keys: `docs/keyboard.md`. Parsers and operators stay English.
