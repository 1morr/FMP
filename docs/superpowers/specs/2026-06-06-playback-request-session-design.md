# Playback Request Session Refactor Design

Date: 2026-06-06

## Context

FMP's audio request lifecycle is currently split between
`AudioController` and `PlaybackRequestExecutor`.

`AudioController` owns user-facing playback state, queue/mix/temporary mode,
source-error UI decisions, history, lyrics matching, notification/SMTC
coordination, and radio ownership filtering. It also currently owns raw playback
request IDs, loading request state, play locks, media-open pending recovery,
retry generation, retry timers, manual retry, network recovery, and premature
completion recovery.

`PlaybackRequestExecutor` owns part of stream selection and backend handoff, but
its interface is still shallow: callers pass `requestId`, `isSuperseded`,
`getNextTrack`, `persist`, `prefetchNext`, and separate queue-restore inputs.

The refactor should deepen the request and recovery modules while preserving the
observable playback semantics unless an existing inconsistency is clearly caused
by duplicated state handling.

## Goals

- Move request token, supersession, play lock, backend stop/handoff, fallback
  handoff, queue restore handoff, and media-open pending recovery behind a deep
  `PlaybackRequestSession` interface.
- Move retry generation, retry timers, retry attempt state, manual retry,
  network recovery, and premature completion recovery behind a deep
  `PlaybackRecoveryCoordinator` interface.
- Keep `AudioController` as the owner of product-facing semantics: player state,
  queue/mix/temporary/detached mode, source-error UI decisions, history, lyrics,
  and notification/SMTC coordination.
- Preserve user-visible behavior for retry timing, max retry count, toast copy,
  source skip behavior, radio exception behavior, and Mix load-more behavior.
- Allow small consistency fixes where current duplicated paths update loading,
  retry, or terminal error state in different orders.

## Non-Goals

- Do not redesign source stream fallback or source auth/header policy.
- Do not change retry delays or max retry attempts.
- Do not change source-error skip semantics.
- Do not move queue ordering, shuffle, loop, or Mix load-more ownership out of
  `AudioController`/`QueueManager`.
- Do not change UI playback entrypoints; UI controls must still call
  `AudioController`.
- Do not change radio's documented direct shared-backend exception.

## Proposed Modules

### PlaybackRequestSession

New file: `lib/services/audio/playback_request_session.dart`

Owns:

- Request token creation and supersession.
- Active loading request state.
- Play lock completion.
- Backend stop before handoff.
- Normal playback handoff.
- Queue restore handoff with seek/resume.
- Manager-selected fallback handoff.
- Media-open pending recovery and terminal media-open failure.

Depends on:

- `FmpAudioService`
- `PlaybackRequestStreamAccess`
- A small set of callbacks for loading-state publication and current request
  state observation.

Does not own:

- Queue mutation.
- Temporary/mix/detached mode policy.
- Source-error skip or toast decisions.
- History or lyrics side effects.
- Retry policy.

Primary types:

- `PlaybackSessionCommand`
- `PlaybackRestoreCommand`
- `PlaybackSessionResult`
- Internal active request handle.

`PlaybackSessionResult` should be typed enough for `AudioController` to avoid
inspecting internal session state:

- `completed(track, attemptedUrl, streamResult)`
- `superseded`
- `terminalMediaOpenError(message)`
- `failed(error, stackTrace)`

The existing `PlaybackRequestExecutor` can either become an inner helper of the
session or be absorbed into the session. If it remains, its interface should no
longer expose `requestId` or `isSuperseded` to external callers.

### PlaybackRecoveryCoordinator

New file: `lib/services/audio/playback_recovery_coordinator.dart`

Owns:

- Retry generation.
- Scheduled retry track key.
- Retry attempt count.
- Retry timer.
- Saved recovery track and position.
- Duplicate backend network error suppression.
- Fresh generation when a backend network error arrives during retry handoff.
- Manual retry.
- Network recovered handling.
- Premature completion recovery decision.

Depends on:

- `PlaybackRetryExecutor`, implemented by `AudioController` or by a small
  adapter around `PlaybackRequestSession`.
- Timer creation injection for deterministic tests.

Does not own:

- Toast copy.
- Source-error UI.
- Queue next/previous.
- Radio ownership filtering.
- Mix load-more.

Primary types:

- `PlaybackRecoveryCoordinator`
- `PlaybackRecoveryState`
- `PlaybackRecoveryEvent`
- `PlaybackRetryExecutor`

The coordinator should produce typed state patches/events such as:

- `retryScheduled`
- `retryExhausted`
- `retrySucceeded`
- `recoveryFailedNonRetryable`
- `staleEventIgnored`

`AudioController` applies these to `PlayerState` and handles visible errors.

## Data Flow

### Normal Play

1. `AudioController` decides playback mode and updates queue/temporary/mix
   context.
2. `AudioController` builds `PlaybackSessionCommand`.
3. `PlaybackRequestSession.start(command)` supersedes any active request, enters
   loading, stops backend, selects playback, and hands off to the backend.
4. On `completed`, `AudioController` updates `PlayerState`, replaces the queue
   track when needed, records history, starts lyrics auto-match, and triggers
   Mix load-more if appropriate.
5. On `superseded`, `AudioController` leaves the latest request in control.
6. On `failed`, `AudioController` decides whether the error is retryable or
   terminal.

### Queue Restore / Resume

1. `AudioController` calculates restore position, rewind, and whether playback
   should resume.
2. `AudioController` builds `PlaybackRestoreCommand`.
3. `PlaybackRequestSession.restore(command)` prepares stream/local playback,
   calls `setUrl`/`setFile`, seeks, and optionally resumes.
4. `AudioController` applies the completed result to queue projection and
   playback-visible stream metadata.

### Backend Error Stream

1. `AudioController` filters disposed state and radio ownership.
2. Backend network errors go to `PlaybackRecoveryCoordinator`.
3. Backend media-open errors go to `PlaybackRequestSession`, because active
   request and pending media-open recovery are request lifecycle state.
4. Non-network, non-media-open backend errors keep the current ignore/display
   behavior.

### Manual Retry / Network Recovered / Premature Completion

1. `AudioController` forwards the event to `PlaybackRecoveryCoordinator`.
2. The coordinator checks generation/current-track validity.
3. If playback should be attempted, the coordinator calls
   `PlaybackRetryExecutor.retryPlayback(track, position, mode)`.
4. The retry executor uses `PlaybackRequestSession.start(...)` with
   `persist=false` and `recordHistory=false`.
5. The coordinator receives the result and emits state patches/events.
6. `AudioController` applies patches and handles visible terminal errors.

## Error Handling

### SourceApiException

`AudioController` remains the source-error UI owner.

- Retryable `network` and `timeout` errors schedule retry through
  `PlaybackRecoveryCoordinator`.
- `shouldSkipTrack` errors in queue mode keep the existing skip-next behavior.
- Rate-limit, login, permission, VIP, geo, and unavailable messages keep the
  existing toast and error copy.

### Backend Network Errors

`PlaybackRecoveryCoordinator` centralizes:

- Duplicate retrying error suppression.
- Fresh generation during retry handoff.
- Saved recovery track and saved recovery position.
- Max retry exhaustion state.
- Network recovered and manual retry guards.

Allowed consistency fixes:

- Replace raw `_playRequestId++` cancellation of an active retry handoff with an
  explicit `PlaybackRequestSession.cancelActive()` or equivalent handle.
- Centralize the order of loading-state reset and retry scheduling.
- Generate retry success/failure state patches in one place for manual retry,
  automatic retry, and network recovered paths.

### Media-Open Errors

`PlaybackRequestSession` centralizes:

- Active request pending completer.
- Backend self-recovery delay.
- Recovered vs terminal failure decision.
- Terminal failure cancellation.

Allowed consistency fixes:

- Route superseded and terminal media-open outcomes through typed session
  results instead of a controller-owned pending map.
- Leave visible terminal error state writes in `AudioController` only.

### Generic Playback Errors

`PlaybackRequestSession` returns `failed(error, stackTrace)`.

`AudioController` decides:

- Retryable generic error: schedule retry through the coordinator.
- Non-retryable generic error: stop backend, set visible error, and show the
  existing playback-failed toast.

## Test Plan

### New Session Tests

Add `test/services/audio/playback_request_session_test.dart`.

Cover:

- Superseded request aborts after async URL/header/handoff.
- Stop failure stays outside fallback handling.
- Local file playback avoids network headers.
- Manager-selected fallback succeeds.
- Original handoff error is preserved when fallback selection fails.
- Queue restore performs `setUrl`/`setFile`, seek, and optional resume.
- Media-open error recovers when backend advances.
- Media-open error becomes terminal when backend does not recover.
- Superseded session does not stop or error the newer request.

### New Recovery Tests

Add `test/services/audio/playback_recovery_coordinator_test.dart`.

Cover:

- Schedule retry generation and timer behavior.
- Duplicate backend network error suppression.
- Fresh generation during retry handoff.
- Manual retry resets attempt and restores saved position.
- Network recovered does not restart old track after switch during
  stabilization.
- Premature completion schedules current-track retry.
- Max retry exhaustion emits the same visible state patch as today.
- Non-retryable retry failure clears retry state and emits terminal failure.

### Existing Integration Tests

Keep or adapt these tests as integration coverage:

- `test/services/audio/audio_controller_phase1_test.dart`
- `test/services/audio/audio_auth_retry_phase4_test.dart`
- `test/services/audio/audio_controller_mix_boundary_test.dart`
- `test/services/audio/playback_request_executor_test.dart`

`playback_request_executor_test.dart` should either migrate to session tests or
be reduced if the executor becomes an internal helper.

## Rollout Plan

1. Introduce `PlaybackRequestSession` types and tests around behavior currently
   covered by `PlaybackRequestExecutor`.
2. Move normal handoff and queue restore through the session while preserving
   existing controller integration tests.
3. Move media-open pending recovery into the session.
4. Introduce `PlaybackRecoveryCoordinator` with timer-injected tests.
5. Route backend network errors, manual retry, network recovered, and premature
   completion through the coordinator.
6. Remove obsolete `_playRequestId`, `_LockWithId`, `_PendingMediaOpenError`,
   retry generation, and retry timer fields from `AudioController`.
7. Update `lib/services/audio/AGENTS.md` ownership guidance.
8. Run audio verification.

## Verification

Minimum:

```bash
flutter test test/services/audio
```

If the stream fallback interface changes during implementation, also run:

```bash
flutter test test/data/sources/audio_stream_quality_fallback_test.dart test/data/sources/youtube_source_test.dart
```
