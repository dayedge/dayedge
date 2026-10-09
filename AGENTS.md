# DayEdge — agent guide

Native macOS menu-bar calendar + reminders app. SwiftUI with an AppKit shell. macOS 15+. MPL-2.0.
Canonical instructions; `CLAUDE.md` points here. Details per area in `docs/` — read the relevant one first.

## Principles
- KISS: smallest change, plainest code. No speculative abstraction, options, fallbacks or compatibility shims. Delete, don't deprecate.
- Modular: a file goes in the lowest module that has what it needs. Modules talk through `Domain` contracts.
- Low resources: menu-bar app, always running. Near-zero idle CPU, small flat memory, observe instead of poll, draw only what's visible. Every feature has a cost — weigh it, measure it (`docs/ui.md`).
- Apple-like: native controls, menus, keys first. Minimal. Keyboard-first.
- Best practices: modern Swift/Apple APIs (Observation, Swift Concurrency), value types, pure logic, one way to do each thing.
- Private: no telemetry; external chat is opt-in. Network requests match the service disclosures in `PRIVACY.md`; update it when adding or changing a request.

## Toolchain
- Xcode 26 (Swift 6.2+ compiler) for app, lint, full features. Manifests `swift-tools-version: 5.9`; Swift 5 language mode; app target `MainActor` default isolation. No new concurrency warnings.
- Command Line Tools must still build the packages: `#if HAS_MACOS26_SDK` / `HAS_MACOS26_4_SDK` (set in `Packages/DayEdge/Package.swift` from the SDK) gate new APIs; Tachikoma only under `#if compiler(>=6.2)`, sources `#if canImport(Tachikoma)`.
- Dependencies: GRDB, Tachikoma. Adding one needs explicit approval.

## Required tools
| Tool | Used by | Install |
| --- | --- | --- |
| Xcode 26 | `make build/run/release`, SwiftLint, macOS 26 SDK | App Store, then `sudo xcode-select -s /Applications/Xcode.app` and `xcodebuild -runFirstLaunch` |
| Command Line Tools | `make`, `git`, `swift`, `python3`, `/usr/bin/openssl` | `xcode-select --install` (included with Xcode) |
| SwiftLint | `make lint` | `brew install swiftlint` (Homebrew: https://brew.sh) |
- Everything else the scripts use (`security`, `codesign`, `footprint`, `vmmap`, `heap`, `malloc_history`) ships with macOS/Xcode.
- The `Makefile` uses Xcode's toolchain when `/Applications/Xcode.app` exists, else the active one.
- Missing SwiftLint ⇒ `make lint` stops with the install hint. Missing signing identity ⇒ `make build` signs ad hoc; create it once with `make signing-identity`.

## Layout
```
DayEdge.xcodeproj       thin app target: App/ (AppEntry → DayEdgeApp.main(), icon, Info.plist, entitlements)
Packages/DayEdge        7 module targets + DayEdgeTests
Packages/CalendarIndex  SQLite mirror of EventKit (GRDB) + its tests
```
- Release: `DayEdge.app`, `com.dayedge.app`. Debug: `DayEdge Dev.app`, `com.dayedge.app.dev` (separate settings/permissions).
- Hardened runtime, no sandbox.

```
Shell ─┬─ Agenda ───────┐
       ├─ Tasks ────────┼─→ UI ─→ Domain
       ├─ Intelligence ─┘          ↑
       └─ Platform ─────→ Domain, CalendarIndex
```
- `Domain`: values, settings, contracts, mocks. Foundation + Observation only.
- `Platform`: implements contracts — EventKit, index runtime, permissions, weather, holidays. No SwiftUI.
- `UI`: shared theme, components, presentation plans, shared coordinators. Never Platform.
- `Agenda` (Month, Day), `Tasks`, `Intelligence` (search, Quick Add, chat): features.
- `Shell`: composition (`RootModels`), panel, menu bar, Meeting HUD, onboarding, Settings.

## Rules
- Only `Shell` imports `Platform`. Features import `Domain` + `UI` only, never each other; cross-feature routes via `PanelRouter`. Enforced by `scripts/check-modules.sh`.
- Cross-target API is `package`, never `public` (except `DayEdgeApp`). Structs used across targets need an explicit `package init`.
- Events: read from the index, write to EventKit only via `EventKitEventEditor` / `EventKitEventRemovalService` (they announce `CalendarWriteScope`).
- Calendar access: checked live, never cached. Revoked ⇒ index erased.
- User-visible dates/times: `DatePresentationFormatter` and `TimeFormat` only. Never `DateFormatter` / `Date.FormatStyle` at call sites.
- Colours, fonts, metrics: theme tokens only (`AppTheme`, `ThemePalette`).
- Decisions: `TransientNotice` (done, with Undo) or `DecisionCard` (choice needed). No `NSAlert` except OS-level.
- No `print` / `NSLog` / `debugPrint` / `dump` (lint error). Failures → `os.Logger` at error level.
- Chat writes need explicit or saved approval; remote "Always allow" never covers deletions. Tools never let the model compute dates.
- Every user-facing string localized: English + Polish.
- Persisted state must not collide between DayEdge and DayEdge Dev.
- Comments: rare, short, explain why.

## Tests
- Small and focused: one behaviour per test, named for it. No multi-scenario tests.
- Test pure logic (layouts, plans, parsers, projections, rules) — keep it out of views so it can be.
- Deterministic: tests must pass across machines, dates, time zones, and locales. Fix or inject the clock, calendar, time zone, locale, and defaults; never rely on real sleeps or ambient system defaults. No network, no API keys, no real EventKit. Use mocks/fakes.
- Fast: no sleeps, no polling in normal tests. Live model tests require `DAYEDGE_LIVE_APPLE_MODEL=1`; read-only live EventKit tests require `DAYEDGE_LIVE_EVENTKIT=1` and Calendar access.
- New logic ⇒ new tests. Bug fix ⇒ a test that fails without it.
- App tests: `DayEdgeTests`; CalendarIndex has its own test targets. `@testable import` only the modules a file needs.

## Lint
- `make lint`: SwiftLint strict, no baseline + module imports + localizations.
- Fix findings. Disable only where the fix makes code worse, inline with a reason: `// swiftlint:disable:next <rule> - <why>`.

## Commands
```
make build | make build CONFIGURATION=Debug | make run | make test | make lint | make memory ARGS=…
swift test --package-path Packages/DayEdge --filter <TestClass>
DEVELOPER_DIR=/Library/Developer/CommandLineTools swift build --package-path Packages/DayEdge --scratch-path /tmp/dayedge-clt
```

## Done means
- `make test` passes.
- `make lint` clean. CLT build passes. `make build` with no new warnings.
- UI / data processing / long-lived change: memory compared before/after. Docs and translation-only changes do not need a memory capture.
- Docs made wrong by the change are fixed in the same change.
- Don't commit or bump the version unless asked.

## Docs
`architecture.md` modules, data flow, EventKit · `ui.md` resource cost, UI rules · `keyboard.md` · `search.md` · `assistant.md` chat/models · `theming.md` · `localization.md` · `development.md` signing, memory, SDKs · `release.md`
