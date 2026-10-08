# Release

## Before publishing

- Version: SemVer. `MARKETING_VERSION` in `DayEdge.xcodeproj/project.pbxproj` has Debug and Release values;
  keep them equal. `CURRENT_PROJECT_VERSION` stays 1. Bump or commit only when asked.
- Run `make test`, `make lint`, `make build`, and the explicit CLT check in [development.md](development.md#both-sdks).
- Smoke-test Calendar/Reminders permissions, search, event/task changes and Undo, meeting links, and chat
  approval. Check English and Polish at the smallest panel width.
- Check README links, privacy disclosures, bundled third-party notices, and screenshots. Use fictional
  data and meeting links. Retake screenshots after UI changes; do not alter them to hide incorrect behaviour.
- Create the public repository at `dayedge/dayedge`. Enable **Settings → Code security → Private
  vulnerability reporting** before publication; test the private route linked in [SECURITY.md](../SECURITY.md).
- Enable **Settings → General → Features → Sponsorships** so GitHub shows the Ko-fi link from
  `.github/FUNDING.yml`. Check the website and donation links.

## First releases: self-signed, not notarized

Keep the development signing keychain outside the repository. Never publish its private key or a
keychain file. The early-release signature is not Apple Developer ID signing.

```sh
make signing-identity
make build
codesign --verify --deep --strict build/DayEdge.app
ditto -c -k --keepParent build/DayEdge.app build/DayEdge.zip
shasum -a 256 build/DayEdge.zip > build/DayEdge.zip.sha256
```

The checksum file names `build/DayEdge.zip`; when checking a download, compare its digest with
`shasum -a 256 DayEdge.zip`.

Create a release for the corresponding source tag and attach **DayEdge.zip** and **DayEdge.zip.sha256**.
State the minimum macOS version, supported architectures of that archive, changes, and that the app
is self-signed and not notarized. Link the README's Gatekeeper instructions. Test the downloaded archive
on a separate Mac/user account; a local build does not exercise download quarantine.

## Homebrew tap

Keep the cask in the project's separate tap repository. For each release:

1. Update its version, release archive URL and SHA-256 digest together.
2. Keep `app "DayEdge.app"` and the macOS 15 minimum consistent with the archive.
3. Include the self-signed/not-notarized caveat. Homebrew installation does not provide notarization.
4. Test the published cask with a fresh install and an upgrade, including Calendar/Reminders grants.
5. Keep the exact tap/cask command in README aligned with the published cask.

## Developer ID releases later

Enroll in the Apple Developer Program, configure Developer ID signing, and store notarization
credentials once with `xcrun notarytool store-credentials <profile>`.

`make release TEAM=<id> NOTARY_PROFILE=<profile>` archives, exports, notarizes and staples the app, then
creates `build/DayEdge.zip`. Generate its SHA-256 file and publish through the same release/tap process.
Update the README and SECURITY signing disclosure when the public builds become notarized.
