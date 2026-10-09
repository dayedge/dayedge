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

## GitHub Actions

`.github/workflows/release.yml` builds with Xcode 26.6 on `macos-26`. It runs lint and tests, imports
the existing signing identity, builds separate `arm64` (Apple Silicon) and `x86_64` (Intel) Release apps,
and verifies each app's signature, certificate fingerprint, version, bundle identifier, and exact
architecture before packaging it. No Apple account or provisioning profile is required for these
self-signed builds; they remain non-notarized.

### One-time signing setup

Export the **existing** `DayEdge Self-Signed` certificate together with its private key as a
password-protected `.p12` file from Keychain Access. Use a strong export password. Do not create a new
certificate on CI: the name alone does not make it the same signing identity.

Under **Settings → Secrets and variables → Actions**, add these repository secrets:

| Secret | Value |
| --- | --- |
| `CERTIFICATE_P12_BASE64` | Base64-encoded `.p12` containing the existing certificate and private key |
| `CERTIFICATE_PASSWORD` | The `.p12` export password |

For example, after exporting the file outside the checkout:

```sh
base64 -i /path/outside/repository/DayEdge.p12 | gh secret set CERTIFICATE_P12_BASE64 --repo dayedge/dayedge
gh secret set CERTIFICATE_PASSWORD --repo dayedge/dayedge
```

The second command prompts for the password. Never paste the key or password into an issue, workflow
file, or chat. Keep an encrypted backup of the identity outside the repository, then remove the temporary
export. The runner uses a random password for its temporary keychain and deletes signing material at
the end of the job. The workflow pins the public SHA-1 certificate fingerprint; update it deliberately
if the signing identity changes. SHA-1 here identifies the certificate; archive checksums use SHA-256.

### Build and release

Commit and push the workflow before creating a release tag. With both `MARKETING_VERSION` values set
to `1.0.0`, run these commands in the **publication checkout**, which has the clean public history:

```sh
git tag -a v1.0.0 -m "DayEdge 1.0.0"
git push origin v1.0.0
```

A tag push creates a **draft** GitHub Release containing `DayEdge-1.0.0-arm64.zip` and
`DayEdge-1.0.0-x86_64.zip`, each with its own `.sha256` file.
The tag must match the checked-in app version. Existing releases are never overwritten; remove a failed
draft explicitly before retrying its creation. Download and smoke-test the archive, replace the draft
notes with release highlights, then publish and update the tap for both architecture-specific assets.

For a test build, choose **Actions → Release → Run workflow** and select a branch or tag. Manual runs
upload separate `DayEdge-1.0.0-arm64` and `DayEdge-1.0.0-x86_64` Actions artifacts retained for 14 days
and do not create a GitHub Release. Choose `arm64` for Apple Silicon (M-series) or `x86_64` for Intel.
After extracting the downloaded artifact, run `shasum -a 256 -c DayEdge-1.0.0-arm64.zip.sha256` (or the
`x86_64` equivalent) alongside the inner app archive. Private repository assets require repository
access; public Homebrew distribution needs a public release download URL.

## Homebrew tap

Keep the cask in the project's separate tap repository. For each release:

1. Update its version and both architecture-specific release archive URLs and SHA-256 digests together.
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
