# Localization

- Languages: English + Polish (Polish wording not yet reviewed). Every target ships the same set.
- Each target: `Localization/<lang>.lproj/Localizable.strings` (+ `.stringsdict`), internal `L10n.tr` over `Bundle.module`. Native files, not string catalogs (keeps the CLT build).
- Keys are stable identifiers describing source and meaning. English default at the call site.
- Complete sentences/templates; never concatenate or re-case translated fragments.
- Plurals: native `Int` interpolation + `.stringsdict`. `%@` strings, `%lld` integers, positional `%1$lld` / `%2$@` when reordering; `%%` for literal percent.
- User content (titles, notes, calendar names, URLs, model ids) is verbatim: `Text(verbatim:)`, never `LocalizedStringKey`.
- Stay English: parsers, search operators, assistant instructions, tool schemas and reports, persisted identifiers.
- Language follows macOS (per-app language); no in-app picker. Region controls date order and hour cycle separately.
- Translator comments for ambiguous labels.

## Adding a language
1. Complete translation in every module's `Localization/`, with the language's plural categories.
2. `App/<lang>.lproj/InfoPlist.strings` with every permission description; add to `CFBundleLocalizations`.
3. `make lint`, `make test`, both builds. Clean build products after renaming/removing a localization.
4. Check visually at the smallest panel width, including RTL and long labels.

## Testing
- `LocalizationTests`: bundle lookup, plural counts (1, 2, 5, 12, 22), reordered placeholders, fallbacks.
- Fixtures: `Tests/DayEdgeTests/Fixtures/Localization`.
- Previews: `DAYEDGE_LOCALIZATION_PREVIEWS_DIR=/tmp/dayedge-l10n swift test --package-path Packages/DayEdge --filter LocalizationLayoutTests`.
- One Polish launch: `open -n build/DayEdge.app --args -AppleLanguages '(pl, en)'`.
