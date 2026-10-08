# Contributing to DayEdge

Thanks for helping make DayEdge better. Bug reports, ideas, translations, docs and code are all welcome.
This page explains how we work together so your time is well spent.

## How DayEdge is built

DayEdge is a small, native menu-bar app that stays out of the way. A few principles guide every change:

- **Simple.** The smallest change that solves the problem, in the plainest code.
- **Light.** DayEdge runs all day, so every feature has to earn its CPU, memory and battery cost.
- **Native.** It should feel like it shipped with macOS.
- **Private.** No telemetry, opt-in external chat, and clear disclosures for network services ([PRIVACY.md](PRIVACY.md)).

[AGENTS.md](AGENTS.md) holds the rules for the code, and [docs/](docs/) holds the details for each
area. They apply equally to people and AI tools.

## Before you start

- **Bugs:** check the existing issues, then open one with your macOS version, your DayEdge version, the
  steps to reproduce, and what you expected compared with what happened. A screen recording helps.
- **Small fixes** (a bug, a typo, a translation): open a pull request directly.
- **Features:** open an issue first. Explain the problem and discuss the approach before building it.
  Maintainers decide scope and merge pull requests after considering the discussion. A feature can be
  declined even when the code is good, if it does not fit DayEdge or costs more than it gives.
- **Security issues:** never in public issues. See [SECURITY.md](SECURITY.md).

## Setting up

- Install the tools listed in [AGENTS.md › Required tools](AGENTS.md#required-tools).
- Run `make signing-identity` once, so macOS remembers DayEdge's permissions between builds.
- `make run CONFIGURATION=Debug` builds and opens **DayEdge Dev**. It runs beside an installed DayEdge,
  with its own settings and permissions.

## AI tools

AI tools are welcome. They're a normal part of how software is written today, and DayEdge is built
with their help too. `AGENTS.md` gives them the project's rules.

**But you own your pull request.** Whatever wrote the code, you are its author:

- understand every line you submit, and be able to explain why it's there;
- run it, use it, and check it does what the pull request says;
- take responsibility for review responses and check any tool-assisted changes yourself.

That takes a working knowledge of Mac development: Swift, SwiftUI and AppKit, Xcode and its tooling,
and how macOS apps behave (permissions, memory, the main thread). Submit code you understand and have
verified. If you are learning, ask questions in the issue or pull request; we can help you narrow the change.

## What every change needs

- **Focused.** One change per pull request, with no unrelated edits, drive-by refactors or reformatting.
- **Tested.** New logic comes with a focused test suite: small tests, one behaviour each, no network and
  no real calendar ([AGENTS.md › Tests](AGENTS.md#tests)). A bug fix includes a test that fails without
  it.
- **Measured where relevant.** Changes to views, data processing, caches or long-lived objects include
  a memory comparison before and after. Documentation and translation-only changes do not need one:
  ```
  git switch main && make build
  scripts/memory-report.sh --launch        # baseline → build/memory/memory-<time>.txt
  git switch my-branch && make build
  scripts/memory-report.sh --launch --compare build/memory/memory-<time>.txt
  ```
  Also exercise your feature while measuring, for example with `--spike` or `--stacks` ([docs/development.md](docs/development.md#memory)).
  **Put the comparison in the pull request.**
- **Clean.** `make test`, `make lint` and `make build` pass with no new warnings, and so does the Command
  Line Tools build ([AGENTS.md › Commands](AGENTS.md#commands)).
- **Localized.** Any text the user sees has English and Polish entries. If you don't speak Polish, say so
  in the pull request and we'll help.
- **Private.** A new network request is opt-in, and it updates [PRIVACY.md](PRIVACY.md) in the same pull
  request.
- **Documented.** Fix any doc your change makes wrong.

## Pull requests

- Describe **what** changed and **why**, and link the issue (`Closes #123`).
- Say **how you tested it**: which tests, and what you did in the app.
- Include a **memory comparison** for changes that affect resource use.
- For visual changes, include before and after screenshots or a short recording.
- Mention anything you changed on purpose that a reviewer might not expect, and any trade-off you made.
- Keep commits tidy and messages in the imperative ("Add weekly view"). Rebase on `main`.
- **Read your own diff top to bottom before asking for review.**

## Licensing

DayEdge is licensed under the [Mozilla Public License 2.0](LICENSE). By opening a pull request you
confirm that:

- your contribution is licensed under the MPL-2.0, the same as the rest of DayEdge, and may be
  distributed as part of it;
- you have the right to submit it: it's your own work, or you have permission to contribute it;
- it doesn't infringe anyone's copyright, patents, trademarks or other rights, and doesn't break any law
  or licence, including the terms of any AI tool or code it was derived from;
- any third-party code you include is under a licence compatible with the MPL-2.0, and is credited, with
  its required licence and notices bundled with the app, and credited in the acknowledgements
  (`Shell/Settings/Acknowledgements.swift`). See [third-party notices](Packages/DayEdge/Sources/Shell/Resources/THIRD_PARTY_NOTICES.txt).

You keep the copyright in your contribution. There's no separate agreement to sign.

## Be kind

Project decisions are open to discussion. Maintainers explain decisions and consider feedback;
contributors keep copyright in their work. Make your case and listen to the other side.

Assume good intent, be patient with newcomers, and keep discussion about the work, not the person. We'd
rather have a slow, friendly conversation than a fast, unpleasant one.
