# Security

## Reporting a vulnerability

Please report security issues privately through
[GitHub's Report a vulnerability form](https://github.com/dayedge/dayedge/security/advisories/new).
You need a GitHub account to submit a report. Do not post API keys, calendar content or an exploit
in a public issue.

Include the affected DayEdge and macOS versions, steps to reproduce, the likely impact, and a minimal
example using fictional data. If a key has been exposed, revoke it with its provider.

If the private reporting form is unavailable, open a public issue asking for a private contact method,
without vulnerability details or personal information. We will arrange a private channel.

## Supported versions

Security fixes target the latest public release. Please reproduce on that release when possible;
reports about older versions are still welcome.

## Early releases

Initial releases are self-signed and not notarized by Apple. Download from the official repository's
Releases page or the project's Homebrew tap, and follow the installation instructions in
[README.md](README.md). Release archives include SHA-256 checksums.

External model keys are currently stored in an unencrypted, owner-only local file. See
[PRIVACY.md](PRIVACY.md) for storage and data-sharing details.
