# Service conventions

## Shape

- Most services are plain classes with constructor injection and a Riverpod
  `Provider` that owns their lifecycle (`DownloadService`, `ImportService`,
  `PlaylistService`, `QueueManager`). A few are Riverpod `Notifier`s living in
  `lib/services/` (`AudioController`, `RadioController`, `RankingCacheService`,
  `ConnectivityNotifier`). Plain services do not hold a `Ref` (`AutoRefreshService`
  is a one-off).
- Most constructors take named `required` params assigned to `final _fields`;
  some older ones are positional (`BackupService(Isar isar, …)`,
  `DownloadPathManager(this._settingsRepo)`, `DownloadPathSyncService`). An
  optional collaborator defaults to the real implementation built from the other
  params: `mutationService ?? PlaylistMutationRepository(isar: isar)`.
- **Take the narrowest interface.** `SourceAuthContext` is split into
  `SourcePlaybackAuthContext`, `PlaybackMediaRequestContext`,
  `DownloadSourceAuthContext`, `PlaylistAuthContext`; each consumer takes the slice
  it uses. Only `source_auth_context.dart` and its provider may name the wide type
  (`test/services/static_rules/audio_seam_static_rule_test.dart`).
- Sources are reached through `SourceManager` capabilities, never by concrete type
  (see `../data/sources.md`).
- Services that get `Isar` wrap it in a repository, usually in the initialiser
  list (`_accounts = AccountRepository(isar)`); `BilibiliFavoritesService` keeps
  `_isar` and builds a `TrackRepository` per call. They never call `isar.` (ADR 0002).
- Where a provider is declared: see `../ui/riverpod.md` § Naming and location.

## Disposal

- Most `dispose()` methods are idempotent: a disposed flag and an early return
  (`DownloadService.dispose` uses `_isDisposed`, `JustAudioService.dispose` uses
  `_disposed`; `b45b791a`). `ImportService`, `RadioRefreshService` and
  `PlaylistImportService` have no flag.
- It closes every `StreamController`, cancels every `Timer` and
  `StreamSubscription`, kills isolates, closes `Dio`.
- **Dispose only what you created.** `DownloadService` tracks
  `_ownsStreamResolutionService`; `AudioStreamManager.dispose()` is empty on purpose.
- The provider usually owns the call: `ref.onDispose(service.dispose)`. A missing
  `onDispose` is a known bug class (`491f76f9`). Exceptions:
  `audioServiceProvider` and `queueManagerProvider` are disposed by
  `AudioController.dispose`; `playlistImportServiceProvider` registers nothing
  (an open gap, not a pattern).

## Exposing state

- Private broadcast controller + public getter:

  ```dart
  final _progressController = StreamController<DownloadProgressEvent>.broadcast();
  Stream<DownloadProgressEvent> get progressStream => _progressController.stream;
  ```

- One-shot outcomes of a plain service are event classes (`DownloadCompletionEvent`,
  `DownloadFailureEvent`); the provider subscribes and turns them into toasts or
  invalidations, and the service does not toast. `Notifier` services such as
  `AudioController` toast directly through `toastServiceProvider`.
- `Stream<void>` means "something changed, re-read the getters"
  (`QueueManager.stateStream`).
- **Broadcast events emitted before anyone subscribes are lost.** Initialisation
  that others wait on shares one in-flight future —
  `_initialization ??= _runInitialization()`, cleared in `finally` on failure so the
  next caller retries (`AudioController.initialize`, #81 / `35c0e8f4`).
- Expected outcomes come back as typed results, not exceptions
  (`PlaybackSessionResult`, `DownloadResult`, `RemotePlaylistEditResult`).

## Async guards

- A disposable object with a disposed flag checks it after an `await` before
  touching state (`if (_isDisposed) return;`, as in `DownloadService`).
  `RadioRefreshService` drops stale work by generation instead; `ImportService`
  has no guard.
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
- Fire-and-forget is usually written as `unawaited(...)`, though some calls drop
  the future bare (`_handleStreamEnd();` in `radio_controller.dart`). Only a few
  attach `.catchError` with a log (`AudioController.dispose`); most do not. The
  `unawaited_futures` lint is not on, so none of this is checked.

## Timers

- Work that must be cancellable is usually a `Timer` (`5f3bec68`: an orphaned
  `Future.delayed` fired against a closed Isar). Some delayed callbacks are an
  uncancellable `Future.delayed` guarded by a generation or request id instead
  (`RefreshManagerNotifier`, the skip-to-next in `AudioController`).
  `Future.delayed` is otherwise for in-flow waits. Only `PlaybackRequestSession`
  and `PlaybackRecoveryCoordinator` take an injectable `delay:`; elsewhere the
  delay is hard-coded (`ImportService`, `AutoRefreshService`, `DownloadService`).
- Every `Timer.periodic` / `Stream.periodic` is listed in `_timers` with its purpose
  and whether the user can turn it off
  (`test/support/periodic_timer_static_rule_test.dart`). A self-rescheduling
  `Future.delayed` loop hides from that rule; the one that exists is the bounded
  reconnect loop in `RadioController._handleStreamEnd`.
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

- Branch on type and `SourceErrorKind`. Known places that still match message
  text: the not-owned delete check in `netease_playlist_service.dart` and
  `YouTubeSource._isRetryableTrendingError`. An unlisted
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
- How messages reach the user: `../shared/errors-and-logging.md`.

## Tests

- Hand-written fakes; shared ones in `test/support/fakes/`. A test-specific
  variation is usually a file-local `_FakeX` / `_RecordingX` (dartdoc on
  `FakeSourceAuthContext`); a shared fake carries a switch only occasionally
  (`FakeAudioService.playUrlSettlesReady`).
- There is no fake clock package. Time is injected where the class allows it
  (budgets, `delay:`, `timerFactory:`, `now`); most timers are not injectable,
  and those tests wait in real time (see `../testing/test-conventions.md` § Time).
- `@visibleForTesting` hooks on the production class when a path cannot be driven
  otherwise (`DownloadService.debugKillDownloadIsolateForTesting`).
- A regression test usually opens with a `///` naming the issue; a few also quote
  the observed log.
- Assertions on logs read `AppLogger.logs` and reset with `AppLogger.clearLogs()`.
