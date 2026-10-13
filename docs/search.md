# Search

`Intelligence/Search/`, `Intelligence/QuickAdd/`.

- `NaturalLanguageParser`: shared lazy TimeWhisper instance. No external date finder or fallback parser. Releases provider resources after 120 idle seconds.
- Each plain query uses `parse` and `findTemporal` with one reference time and zone. A date with no remaining text offers Go to; otherwise candidates offer Create. Search and Ask keep their existing visibility rules.
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
Keys: `docs/keyboard.md`. Operators stay English. Parser language is explicitly `en`, independent of app language and system locale; the entry point accepts another supported language for future settings. Date order follows parser language; week start follows the supplied calendar.

## Local dependency

The package currently uses the sibling `../../../time-whisper` relative to `Packages/DayEdge/Package.swift`. Build its universal core before building DayEdge:

```sh
cd ../time-whisper
sh ./gradlew assembleTimeWhisperCoreReleaseXCFramework --console=plain
```

Swift wrapper changes rebuild normally. Kotlin changes require rebuilding the XCFramework. DayEdge builds do not invoke Gradle. To use a published release later, replace the local package declaration with the GitHub URL and an exact version; product names and application code stay the same. Remote release builds require that switch or an explicit checkout/build of the sibling package.

The original 116 navigation queries are retained in the integration snapshot. The switch adds recognition of `the 23rd of September` and its explicit-year variant; the other recorded results are unchanged. Current TimeWhisper grammar is authoritative: legacy spellings outside that set, such as `today + 3 weeks`, are not recreated in DayEdge.
