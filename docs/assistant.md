# Chat and models

`Intelligence/Assistant/`, `Intelligence/Chat/`. UI name: chat (`ViewMode.ask`, ⌘4).

## Privacy
- Default: Apple on-device model. Nothing leaves the Mac.
- External provider (OpenRouter via Tachikoma): opt-in only, user's own key. `AssistantBackendResolver` never picks a provider implicitly.
- Conversations are memory-only (`ChatHistory`).
- Keys in `Application Support/DayEdge/intelligence.json`, 0600, excluded from backups. Not Keychain: without Developer ID, login-keychain items are bound to each build's cdhash (prompts on every update). Move to data-protection keychain, one item per provider, after Developer ID.

## Structure
- `ChatSession` → `ChatResponding` (streams full text so far; each element replaces the last).
- Backends: `AppleFoundationModelsBackend` (`#if HAS_MACOS26_SDK`), `TachikomaBackend` (`#if canImport(Tachikoma)`).
- `AssistantBackendResolver`: picks backend, only place tools are registered.
- New provider = `AssistantProviderKind` case + its `ModelSource` + mapping in `TachikomaBackend.provider(…)`.
- No environment variables configure the assistant.
- Transcript: `LazyVStack` of small `Equatable` rows, cached per message. Follow-bottom via explicit `scrollTo`; never `.defaultScrollAnchor(.bottom)` (infinite loop; guarded by `ChatTranscriptStressTests`).
- Remote tier renders references `[[E1]]` / `[[T1]]` / `[[D1]]` (`ChatReferenceRegistry`). Day-run layout is a fixed rule, never the model's choice.

## Prompts
- Two tiers (`AssistantInstructions`): `full` (remote, reference contract) and `onDevice` (short, plain lines, no handles — 3B model can't follow the contract).
- Instructions rebuilt every reply with current date/time. New day in a conversation ⇒ `ChatTimeline.dated` marker in model history.

## Tools
- Read-only: `get_agenda`, `find_free_time`, `find_events` (search operators as parameters), `event_details`, `get_days`, `list_tasks`, `task_recurrence`, `get_current_date`.
- Every tool: data only via `AssistantDataSource`; dates via `AssistantWhen` (model never computes dates); ordinary errors returned as text, cancellation propagated; compact capped lines.
- Changes: `create/complete/update/delete_task`, `create/update/delete_event` (one occurrence, never invitations, writable calendars only).
- Every change → `ChangeRunner` → resolve target/time → `ChatApprovals.request` (card or saved permission) → `AssistantChangeWriter`. Stop/new chat cancels the active reply.
- Receipt with one-shot Undo. The tool's text is all the model may report.
- "Always allow": per `ChangeKind`, remote models only, never deletions.
- On-device: compact task tools only; its narration after changes hidden (`narratesChanges`) — measured unreliable.

## On-device budget (`Assistant/OnDevice/`)
- Window 4,096 tokens, budgeted per reply. Remote models untouched.
- Caps: question 300, tool result 450 (whole lines), 2 tool calls (`ReplyToolGuard`), answer 400. History fills the rest, newest first, older answers cut to 120.
- `OnDeviceToolSpelling`: short tool descriptions (same names/params).
- `TokenMeter`: `ModelTokenMeter` (26.4+, 3% margin), `EstimatingTokenMeter` (chars/3, 10%; calibrated by `EstimateCalibrationTests`), `NoOpTokenMeter`. Only `TokenMeters.make` knows which exist. Override: `defaults write com.dayedge.app com.dayedge.assistant.tokenMeter none|estimate|model`.
- Overflow ⇒ one retry without history, then "too long". Failures typed (`AssistantReplyError`), marked `isFailure`, never resent as history.
- Polish unsupported on-device.

## Tests
- No keys, no network: Tachikoma via scripted `.custom(provider:)`; writes via `FakeChangeWriter`.
- Live on-device tests: opt-in `DAYEDGE_LIVE_APPLE_MODEL=1`.
