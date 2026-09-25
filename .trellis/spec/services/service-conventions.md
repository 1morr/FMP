# Service conventions

## Shape

- Most services are plain classes with constructor injection and a Riverpod
  `Provider` that owns their lifecycle (`DownloadService`, `ImportService`,
  `PlaylistService`, `QueueManager`). A few are Riverpod `Notifier`s living in
  `lib/services/` (`AudioController`, `RadioController`, `RankingCacheService`,
  `ConnectivityNotifier`). Plain services do not hold a `Ref` (`AutoRefreshService`
  is a one-off).
- Named `required` params assigned to `final _fields`. An optional collaborator
  defaults to the real implementation built from the other params:
  `mutationService ?? PlaylistMutationRepository(isar: isar)`.
- **Take the narrowest interface.** `SourceAuthContext` is split into
  `SourcePlaybackAuthContext`, `PlaybackMediaRequestContext`,
  `DownloadSourceAuthContext`, `PlaylistAuthContext`; each consumer takes the slice
  it uses. Only `source_auth_context.dart` and its provider may name the wide type
  (`test/services/static_rules/audio_seam_static_rule_test.dart`).
- Sources are reached through `SourceManager` capabilities, never by concrete type
  (see `../data/sources.md`).
- Services that get `Isar` wrap it in a repository immediately
  (`_accounts = AccountRepository(isar)`); they never call `isar.` (ADR 0002).
- Where a provider is declared: see `../ui/riverpod.md` § Naming and location.

## Disposal

- `dispose()` is idempotent: guard with a disposed flag and return early
  (`DownloadService.dispose` uses `_isDisposed`, `JustAudioService.dispose` uses
  `_disposed`; `b45b791a`).
- It closes every `StreamController`, cancels every `Timer` and
  `StreamSubscription`, kills isolates, closes `Dio`.
- **Dispose only what you created.** `DownloadService` tracks
  `_ownsStreamResolutionService`; `AudioStreamManager.dispose()` is empty on purpose.
- The provider owns the call: `ref.onDispose(service.dispose)`. A missing
  `onDispose` is a known bug class (`491f76f9`).

## Exposing state

- Private broadcast controller + public getter:

  ```dart
  final _progressController = StreamController<DownloadProgressEvent>.broadcast();
  Stream<DownloadProgressEvent> get progressStream => _progressController.stream;
  ```

- One-shot outcomes are event classes (`DownloadCompletionEvent`,
  `DownloadFailureEvent`); the provider subscribes and turns them into toasts or
  invalidations. The service does not toast.
- `Stream<void>` means "something changed, re-read the getters"
  (`QueueManager.stateStream`).
- **Broadcast events emitted before anyone subscribes are lost.** Initialisation
  that others wait on shares one in-flight future —
  `_initialization ??= _runInitialization()`, cleared in `finally` on failure so the
  next caller retries (`AudioController.initialize`, #81 / `35c0e8f4`).
- Expected outcomes come back as typed results, not exceptions
  (`PlaybackSessionResult`, `DownloadResult`, `RemotePlaylistEditResult`).

## Async guards

- After every `await` in a disposable object: `if (_isDisposed) return;` before
  touching state.
- Superseded work is dropped by a generation counter or request id checked after
  each await (`AutoRefreshService._checkGeneration` + `_isCurrentCheck`,
  `RadioController._playRequestId`, `LyricsAutoMatchCoordinator._requestId`;
  `d6b0f8f4`). When the thing is replaced wholesale, compare identity instead
  (`identical`, `MixPlaylistSession`).
- Concurrent callers of one expensive operation share a single in-flight future or
  `Completer` (`BilibiliAuthInterceptor._ensureRefreshed`: concurrent 401s refresh
  once).
- A waiter handed to a caller must be completed on **every** discard path, or the
  caller hangs (`_PendingSeek.complete()` in `playback_handoff_gate.dart`).
- Every wait is bounded (`PlaybackTimeoutBudget` in `app_constants.dart`;
  `b952ccdf`: an unbounded restore wait meant a spinner forever).
- `unawaited(...)` is written explicitly, and a future that can fail gets
  `.catchError` with a log. The `unawaited_futures` lint is not on, so this is by
  hand.

## Timers

- Anything that must be cancellable is a `Timer`, not `Future.delayed`
  (`5f3bec68`: an orphaned delay fired against a closed Isar). `Future.delayed` is
  for in-flow waits, and is injectable (`delay:` params) for tests.
- Every `Timer.periodic` / `Stream.periodic` is listed in `_timers` with its purpose
  and whether the user can turn it off
  (`test/support/periodic_timer_static_rule_test.dart`). A self-rescheduling
  `Future.delayed` loop hides from that rule — use `Timer.periodic`.
- Never log from a per-second poll (`e1bf1712`: it evicts the rotating log files).

## Platform branching

- Audio code branches on the injectable `AudioRuntimePlatform` /
  `audioRuntimePlatformProvider`, not `dart:io`. `NowPlayingPublisher` takes it in
  its constructor. (`WindowsSmtcHandler` still guards itself with
  `Platform.isWindows`.)
- Elsewhere, `Platform.isWindows` / `Platform.isAndroid` with an early return
  (`WindowsDesktopService`, `UpdateService`). When the branch needs a test, add a
  seam (`StoragePermissionService.debugIsAndroidOverride` + `resetDebugOverrides()`).
- Not gated.

## Errors

- Branch on type and `SourceErrorKind`, never on message substrings. An unlisted
  exception type is logged as a warning and **not** retried
  (`PlaybackErrorPresenter.isRetryable`; guessing "network" caused #41).
- Infrastructure failure on a playback or startup path degrades instead of
  throwing: an unreadable credential store means "logged out", a closed database
  means no-op writes, and each side-effect consumer is wrapped so one failure
  cannot stop playback.
- Partial failures are reported, not swallowed (`searchSourcesInParallel` →
  `onSourceError`).
- Retry and backoff ladders live in constants or class statics with the reason
  beside them (`NetworkRetryConfig.retryDelays`,
  `RankingCacheService.defaultFailureRetryDelays`, `RadioRefreshService.maxBackoff`).
  Reuse or extend the owner's ladder; do not add a second one.
- How messages reach the user: `../shared/errors-and-logging.md`.

## Tests

- Hand-written fakes; shared ones in `test/support/fakes/`. A test-specific
  variation is a file-local `_FakeX` / `_RecordingX`, not a switch on the shared
  fake (dartdoc on `FakeSourceAuthContext`).
- Time is injected (budgets, `delay:`, `timerFactory:`, `now`); there is no fake
  clock package.
- `@visibleForTesting` hooks on the production class when a path cannot be driven
  otherwise (`DownloadService.debugKillDownloadIsolateForTesting`).
- A regression test opens with a `///` naming the issue and the observed log.
- Assertions on logs read `AppLogger.logs` and reset with `AppLogger.clearLogs()`.
