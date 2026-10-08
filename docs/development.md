# Development

## Build
- `make build` → `build/DayEdge.app`. `CONFIGURATION=Debug` → `build/DayEdge Dev.app`.
- `make run` builds, quits the running copy, opens it.
- Smoke test: `make run`, check Console for crashes.

## Both SDKs
- Xcode SDK: macOS 26 APIs behind `HAS_MACOS26_SDK` / `HAS_MACOS26_4_SDK`.
- Select CLT explicitly; unsetting `DEVELOPER_DIR` merely uses `xcode-select`'s active developer directory.
- Save a copy of `Packages/DayEdge/Package.resolved` outside the repository before this check and restore
  that copy afterwards, including if the build fails. Older toolchains can drop Tachikoma pins. Do not
  discard unrelated edits to the lockfile.
  ```sh
  DEVELOPER_DIR=/Library/Developer/CommandLineTools swift build \
    --package-path Packages/DayEdge --scratch-path /tmp/dayedge-clt
  ```

## Lint
- `.swiftlint.yml`: 4 spaces, 180 columns, short/underscored names allowed, no debug output.
- `scripts/check-modules.sh`: imports per target.
- `scripts/check-localizations.py`: keys, plurals, placeholders, languages.

## Signing
- Stable self-signed identity "DayEdge Self-Signed" in `~/Library/Keychains/dayedge-signing.keychain-db` (`make signing-identity`, once). `make build` unlocks it.
- Same identity every build ⇒ macOS keeps Calendar/Reminders/Location grants. Ad hoc (no identity) ⇒ re-asked every build.
- This identity is for local development and early releases. It does not establish a verified Apple
  developer identity or provide notarization. The development keychain uses a public password; never
  put Developer ID certificates or unrelated secrets in it.

## Memory
- `scripts/memory-report.sh` (`make memory ARGS=…`) → `build/memory/`. Don't hand-run footprint/vmmap/heap.
- `--launch` fresh launch · `--stacks` allocators (DayEdge frames ▶) · `--track 10:30` leak check · `--spike 40:120` transient peaks · `--compare <report>` delta.
- Cost an action: `--stacks`, do it, `--compare` with the first report.
