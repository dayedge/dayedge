# Search

`Intelligence/Search/`, `Intelligence/QuickAdd/`.

- `NaturalLanguageParser`: shared lazy TimeWhisper instance. No external date finder or fallback parser. Releases provider resources after 120 idle seconds.
- Each plain query uses `parse` and `findTemporal` with one reference time and zone. A date with no remaining text offers Go to; otherwise candidates offer Create. Search and Ask keep their existing visibility rules.
- A value that is all date — an operator's (`day:friday`, `after:next week`) or an assistant tool's `when` and times — is read whole with `parseTemporal`, which needs no model and also reads ranges such as `2026-10-01..2026-10-07`.
- The temporal result is reused by search rather than parsed again.
- `SearchBarView` resolves while typing; `PanelRouter.handle(_:)` executes.

## Operators
- `subject:` `from:` (`from:me`) `with:` `type:` `day:` `before:` `after:` `between:`
- `SearchQuerySyntax` (pure; unknown `key:` stays text; empty value ignored) → `SearchQueryResolver` (`before` exclusive, `after` inclusive) → `SearchQueryParts` → one `SearchRequest` (column FTS: title, organizer, attendees; a date range alone needs no text).
- Operators never affect ranking. Operator queries offer no Go to / Create.

## Results
- Events: index FTS. Tasks: `TaskSearch`.
- TimeWhisper splits a date phrase into a range ("standup tomorrow"). A date alone = Go to.
- Palette top 3: `SearchRelevance` (title tier, bm25, closeness to now).
- Search view: day-grouped, chronological, no recurring dedupe.

## Quick Add
Keys: `docs/keyboard.md`. Operators stay English. Parser language is explicitly `en`, independent of app language and system locale; the entry point accepts another supported language for future settings. Date order follows the region of the supplied calendar (day first in Poland, month first in the US), and so does week start. How text is read is TimeWhisper's to test: DayEdge's tests cover only what it passes in and how answers become drafts, with answers built by hand or `parseTemporal`, which needs no model.

## Parser packages

TimeWhisper and TimeWhisperModel are pinned to the published `0.7.0` releases in `Package.swift`.
SwiftPM downloads the universal Kotlin core and All-model framework during dependency resolution;
no sibling checkout, Gradle build or model copy is required to build DayEdge.

`Intelligence` depends on `TimeWhisper` and `TimeWhisperModelAll`. The parser loads the model from
`AllModel.folder`; the model package owns its weights, tokenizer and labels. DayEdge does not carry
a second model resource. Parsing and inference remain on device and do not use the network.
