# Research: coding conventions in `lib/services/` + `lib/core/services/`

- **Query**: Real patterns a contributor must follow when adding code under `lib/services/**`, `lib/core/services/**`, and their tests (`test/services/**`, `test/workflows/**`, `test/support/**`).
- **Scope**: internal (source, tests, git history)
- **Date**: 2026-09-25
- **Already documented elsewhere (link, don't copy)**: `AGENTS.md` (boundaries, verification table, static-rule list), `CONTEXT.md` (Source Auth Context / Media Handoff / Auth For Play vocabulary), `docs/adr/0002` (Isar only in repositories), `docs/adr/0003` (two audio backends), `docs/adr/0004` (Android storage/raw paths), `docs/development.md` (layer map, VM-service debugging), `docs/troubleshooting.md`.
- **Historical source**: `lib/services/audio/AGENTS.md` was deleted in `e0e6c0c7` ("keep a single root AGENTS.md"; full text at `d3cc598e` / `e0e6c0c7^`). Its commit message says "Reasons that code pointed at now sit beside that code". Some of its rules survive only as dartdoc now. They are flagged below where relevant.

---

## 0. Map of the scope (≈100 files, 34.5k lines)

| Dir | What lives there | Biggest files |
|---|---|---|
| `lib/services/audio/` | `AudioController` (Riverpod `Notifier`, `audio_provider.dart`, 2,953 lines, size-ratcheted), the `FmpAudioService` interface + two backends, `QueueManager`, collaborators (session, gate, router, recovery, watchdog, publisher, side effects, Mix, temporary play), pure rule files | `audio_provider.dart`, `media_kit_audio_service.dart`, `playback_request_session.dart`, `queue_manager.dart` |
| `lib/services/account/` | Per-source `AccountService` impls, credential DTOs, Dio auth interceptors, `SourceAuthContext`, playlist/favorites services | `bilibili_account_service.dart`, `youtube_playlist_service.dart` |
| `lib/services/download/` | `DownloadService` (isolate downloads), path utils/manager/sync/maintenance | `download_service.dart` (2,030) |
| `lib/services/media/` | `MediaHandoff` (per-hop media headers + Range) | `media_handoff.dart` (63) |
| `lib/services/import/`, `library/`, `backup/`, `lyrics/`, `radio/`, `search/`, `cache/`, `network/`, `platform/`, `update/` | Feature services | `playlist_import_service.dart`, `radio_controller.dart`, `lyrics_auto_match_service.dart`, `update_service.dart` |
| `lib/core/services/` | `ToastService`, `ImageLoadingService`, `NetworkImageCacheService` | |

Feature identity for the layer rule = the subdirectory name under `lib/services/` or `lib/providers/`; both halves count as one feature (`test/support/layer_boundary_static_rule_test.dart` `_knownFeatureEdges`).

---

## 1. Service class shape

### 1.1 Two kinds of "service" coexist
- **Plain classes** with constructor injection and a `Provider` that owns their lifecycle — the majority. Examples: `DownloadService` (`lib/services/download/download_service.dart:150`), `ImportService` (`lib/services/import/import_service.dart:100`), `PlaylistService` (`lib/services/library/playlist_service.dart:56`), `QueueManager` (`lib/services/audio/queue_manager.dart:15`), `AudioStreamManager` (`lib/services/audio/audio_stream_manager.dart:30`).
- **Riverpod 3 `Notifier`s living in `lib/services/`**: `AudioController` (`audio_provider.dart:59`), `RadioController` (`radio/radio_controller.dart:229`), `RankingCacheService` (`cache/ranking_cache_service.dart:110`), `ConnectivityNotifier` (`network/connectivity_service.dart:41`), `QueueStateNotifier` (`audio/queue_state.dart:87`). No `StateNotifier` anywhere (gated: `test/providers/static_rules/riverpod3_static_rule_test.dart` "lib does not import the riverpod legacy barrel").

### 1.2 Constructor injection style
- Named `required` params assigned to `final _field` in the initializer list; optional collaborators default to a real implementation built from other params:
  - `DownloadService({... StreamResolutionService? streamResolutionService, DownloadSourceAuthContext? sourceAuthContext})` → default `DefaultStreamResolutionService(...)` and `DefaultSourceAuthContext.fromRepositories(...)` (`download_service.dart:150-195`).
  - `ImportService({..., required Isar isar, PlaylistMutationRepository? mutationService})` → `mutationService ?? PlaylistMutationRepository(isar: isar)` (`import_service.dart:140-151`); same in `PlaylistService` (`playlist_service.dart:62-72`).
  - Account services take `required Isar isar` and wrap it immediately: `_accounts = AccountRepository(isar)` (`netease_account_service.dart:41-50`; also `bilibili_account_service.dart:78`, `youtube_account_service.dart:41`). They never call `isar.` themselves (ADR 0002, gated).
- **Collaborators passed as function callbacks, not objects**, for the audio collaborators: `PlaybackRequestSession(getNextTrack:, onLoadingStarted:, onLoadingFinished:, terminalMediaOpenMessage:, delay:)` (`playback_request_session.dart:137-160`), `PlaybackHandoffGate(currentTrackKey:, performSeek:, isRequestSuperseded:)` (`playback_handoff_gate.dart:70-80`), `MixSessionCoordinator(onLoadingChanged:, onQueueChanged:)`. Typedefs name each callback (`PlaybackSessionLoadingStarted`, `PlaybackRecoveryTimerFactory`, ...).
- **Depend on the narrowest interface.** `SourceAuthContext` is split into `SourcePlaybackAuthContext`, `PlaybackMediaRequestContext`, `DownloadSourceAuthContext`, `PlaylistAuthContext` (`account/source_auth_context.dart:38-80`). Consumers take the slice they need: `DefaultStreamResolutionService` → `SourcePlaybackAuthContext`; `AudioStreamManager` → `PlaybackMediaRequestContext`; `DownloadService` → `DownloadSourceAuthContext`; `ImportService` → `PlaylistAuthContext`. **Gated**: only `source_auth_context.dart` and `lib/providers/account/source_auth_context_provider.dart` may name the wide `SourceAuthContext` (`test/services/static_rules/audio_seam_static_rule_test.dart` `_wideAuthContextOwners`). Likewise `PlaybackRequestStreamAccess` may expose only `{selectPlayback, selectFallbackPlayback, prefetchTrack}` (same test).
- **Sources are reached through `SourceManager` capabilities**, never by concrete type: `audioStreamSource(type)`, `playlistParsingSourceForUrl(url)`, `dynamicPlaylistSource(SourceIds.youtube)?.fetchMixTracks`, `rankingSource`, `liveSource` (`lib/data/sources/source_provider.dart:37-84`). E.g. `mixTracksFetcherProvider` (`lib/providers/audio/audio_controller_provider.dart:71-76`), `ImportService.importFromUrl` (`import_service.dart:174-181`). Branching on concrete source ids outside `lib/data/sources/` is budgeted per file and may only shrink (`test/support/source_branch_points_static_rule_test.dart`).
- **Anti-pattern**: service-locator access to `ref` from plain services. Only one plain service holds a `Ref` (`AutoRefreshService`, `library/auto_refresh_service.dart:17`) — one-off.

### 1.3 Where providers are declared
- Mostly `lib/providers/<feature>/` (e.g. `downloadServiceProvider` in `lib/providers/download/download_providers.dart:42`; account services in `lib/providers/account/account_provider.dart`; `audioServiceProvider`/`queueManagerProvider`/`audioStreamManagerProvider` in `lib/providers/audio/audio_controller_provider.dart`).
- Exceptions that declare providers in the service file itself: `toast_service.dart`, `audio_runtime_platform.dart`, `now_playing_publisher.dart`, `playback_side_effects.dart`, `queue_state.dart`, `ranking_cache_service.dart`, `auto_refresh_service.dart`, `connectivity_service.dart`, `radio_controller.dart` (9 files, 16 providers).
- **Documented boundary** (AGENTS.md): `AudioController` declares no providers; `audio_provider.dart` and `lib/providers/audio/audio_controller_provider.dart` import each other on purpose — comment at `audio_provider.dart:13-16` says "don't move provider declarations into this file to 'fix' it".

### 1.4 Disposal
- Idempotent `dispose()` guarded by a `_isDisposed`/`_disposed` flag, early-return if already disposed: `DownloadService.dispose` (`download_service.dart:276`), `JustAudioService.dispose` (`just_audio_service.dart:341`), `MediaKitAudioService` (`media_kit_audio_service.dart:471`), `AudioController._teardown` (`audio_provider.dart:456`), `PlaybackRequestSession.dispose` (`playback_request_session.dart:188`). Commit `b45b791a` "prevent double disposal".
- Dispose closes every `StreamController`, cancels every `Timer`/`StreamSubscription`, kills isolates, closes `Dio` (`download_service.dart:276-315`; `just_audio_service.dart:341-365`).
- **Dispose only what you created**: `DownloadService` tracks `_ownsStreamResolutionService` and only disposes the default one it built (`download_service.dart:181,306-311`). `AudioStreamManager.dispose()` is deliberately empty with a comment saying the owner disposes the resolver (`audio_stream_manager.dart:43-45`).
- **Lifecycle is owned by the provider**: `ref.onDispose(service.dispose)` / `ref.onDispose(manager.dispose)` (`audio_controller_provider.dart:51`, `download_providers.dart:103-117`, `auto_refresh_service.dart:151-153`, `toast_service.dart:262-266`). Commit `491f76f9` added missing `onDispose` to lyrics singleton providers (release Dio, flush LRU) — missing `onDispose` is a known bug class.
- Reverse-order teardown where order matters: `PlaybackSideEffectRegistry.dispose` clears the list first ("clearing is the latch") then disposes in reverse so system media controls are released last (`playback_side_effects.dart:99-108`, provider doc `:226-236`).
- Riverpod 3 pitfall in `onDispose`: you may not touch another provider synchronously; `download_providers.dart:108-114` defers `progressState.clear` via `scheduleMicrotask` (cites `riverpod/src/core/ref.dart:235`).

### 1.5 Streams / StreamController / exposing state
- Private broadcast controller + public getter, the dominant form: `final _progressController = StreamController<DownloadProgressEvent>.broadcast(); Stream<...> get progressStream => _progressController.stream;` (`download_service.dart:94-116`); `QueueManager._stateController` → `Stream<void> stateStream` (`queue_manager.dart:37-41`); `ImportService._progressController` (`import_service.dart:108-110`); `ToastService._messageController` (`toast_service.dart:47-50`); `FakeAudioService` mirrors this for every `FmpAudioService` stream.
- Event classes for one-shot outcomes consumed by providers: `DownloadCompletionEvent`, `DownloadFailureEvent`, `DownloadPathsChangedEvent`. The provider subscribes and turns them into toasts / invalidations (`download_providers.dart:60-101`); the service itself does not toast.
- `Stream<void>` "something changed, re-read getters" pattern: `QueueManager.stateStream`; controller re-projects from getters.
- **Broadcast pitfall (hard-won, #81/#43, `35c0e8f4`)**: events emitted on a broadcast stream before anyone subscribes are dropped forever. `AudioController.initialize()` therefore shares one in-flight future (`_initialization ??= _runInitialization()`, `audio_provider.dart:337-340`) so every caller waits until `subscribe(...)` has run; failure clears the future in `finally` so the next caller retries (`:436-440`).
- Collaborators report through callbacks and **never touch `PlayerState`**; projection stays in `AudioController`. Stated in dartdoc of `QueueCommands` (`queue_commands.dart`), `MixSessionCoordinator` (`mix_session_coordinator.dart:43-45`), `PlaybackHandoffGate` (`playback_handoff_gate.dart:63-65`), `PlaybackErrorPresenter` (`playback_error_presenter.dart:24-26`), `TemporaryPlayHandler`.
- `PlayerState` (now-playing) and `QueueState` (queue shape) must share no field — **gated** by `audio_seam_static_rule_test.dart` ("PlayerState and QueueState share no field"; they once duplicated 12 fields). All queue writes go through `_emitQueueState` (`audio_provider.dart:162-165`).

---

## 2. Audio

### 2.1 Roles
| Class | File | Role |
|---|---|---|
| `AudioController extends Notifier<PlayerState>` | `lib/services/audio/audio_provider.dart` | Only entry point for UI playback (AGENTS.md boundary). Holds projection state, transport commands, applies routed actions. Wires collaborators in `build()` with `ref.read` (not `watch`) because `ref.onDispose` also runs on rebuild and teardown disposes the backend (`:175-211`). Fields are `late`, not `late final`, because `build()` can re-run on the same instance (`:65-67`). |
| `FmpAudioService` (abstract) | `audio_service.dart` | Backend contract. Backend differences are documented **on each member's dartdoc** (audio focus Android-only, desktop `processingStateStream` synthesized, `bufferedPositionStream` magnitudes, device selection desktop-only, `playMedia` return timing). |
| `JustAudioService` / `MediaKitAudioService` | `just_audio_service.dart` / `media_kit_audio_service.dart` | Android (ExoPlayer) / Windows (libmpv). Selected by `audioServiceProvider` via `AudioRuntimePlatform` (`audio_controller_provider.dart:26-32`). |
| `QueueManager` | `queue_manager.dart` | "Pure queue logic… does not operate the player" (`:12-14`): tracks, index, shuffle order, loop mode, 10 s position save timer, persistence. |
| `PlaybackRequestSession` | `playback_request_session.dart` | Mints the monotonically increasing request id; runs `start`/`restore`; returns a typed `PlaybackSessionResult` (`completed/superseded/terminalMediaOpenError/failed`) instead of throwing. |
| `PlaybackHandoffGate` | `playback_handoff_gate.dart` | Latched copy of the active request id + deferred seeks during handoff. |
| `PlaybackEventRouter` | `playback_event_router.dart` | Pure functions: backend event + `PlaybackEventContext` snapshot → one `PlaybackAction`. |
| `PlaybackRecoveryCoordinator`, `BufferStarvationWatchdog` | `playback_recovery_coordinator.dart`, `buffer_starvation_watchdog.dart` | Retry ladder / stall detection with injectable timers. |
| `NowPlayingPublisher` | `now_playing_publisher.dart` | Single outlet to notification bar / SMTC; arbitrates music vs radio ownership (`claim`/`release`). |
| `PlaybackSideEffect` + registry | `playback_side_effects.dart` | Fan-out of "track started / state changed / stopped" to now-playing, play history, lyrics auto-match; each call guarded so one failing consumer cannot break playback. |
| `AudioStreamManager` → `StreamResolutionService` | `audio_stream_manager.dart`, `stream_resolution_service.dart` | Resolve track → local file or remote stream + `PreparedPlaybackMedia` with media headers. |

Radio is the one intentional exception that uses the backend directly: `RadioController` `_audioService = ref.watch(audioServiceProvider)` (`radio_controller.dart:286`) and coordinates via `audioController.onPlaybackStarting` / `isRadioPlaying` hooks (`:384-390`, cleared at `:1060-1061`).

Music playback opens media through `playMedia()`/`setMedia()` with a `PreparedPlaybackMedia` (sealed: `LocalPlaybackMedia` / `RemotePlaybackMedia`, `playback_media.dart`). The removed audio AGENTS.md said raw `playUrl`/`setUrl` remain for radio/compat only and new music callers must not use them — **now convention only, not stated in current code**.

### 2.2 Two backends — how differences are handled (ADR 0003)
- Convergeable decisions are extracted to **pure rule files** and both backends + `FakeAudioService` delegate: `playback_end_reason_rules.dart` (`classifyCompletion`, `classifyMpvMessage`, `classifyExoPlayerFailure`), `live_edge_seek_policy.dart`, `next_media_plan.dart`. Backends keep 3-line delegators (`just_audio_service.dart:325-337`, `media_kit_audio_service.dart:436-437`).
- **Gated**: `test/services/static_rules/audio_backend_shared_rules_static_rule_test.dart` — keyword tables may exist only in the rules file, and each backend must actually call the shared entries (issue #41 came from a copied table). Behaviour of the rules: `test/services/audio/backend_contract_test.dart`, `next_medium_contract_test.dart`.
- Differences that can't converge go into `FmpAudioService` member dartdoc (ADR 0003 "Consequences": undocumented differences are only found on device).
- `MediaKitAudioService({@visibleForTesting PlatformPlayer? platformPlayer})` (`:39`) is the seam that lets the desktop backend run on a fake engine (`test/services/audio/media_kit_audio_service_state_test.dart`, `media_kit_audio_service_buffer_test.dart`); `JustAudioService` has no such seam (needs platform channels).
- mpv specifics: subscribe to **both** `_player.stream.error` and `_player.stream.log` (`media_kit_audio_service.dart:378-393`) because `ao`-prefixed output-device failures never reach the error stream (`056f20c3`, #41). Desktop "buffering" must be ranked before "playing" or rebuffers are invisible (`16318b87`, noted in `audio_service.dart` dartdoc).

### 2.3 Adding a new playback behaviour — where the logic goes
1. **Backend event → decision**: add a `PlaybackAction` variant + a router test in `test/services/audio/playback_event_router_test.dart`; never an `if` in the applier (`playback_event_router.dart:1-14` library doc). `AudioController._apply` is a single exhaustive `switch` (`audio_provider.dart:2797`).
   - **Gated**: `test/services/static_rules/playback_event_routing_static_rule_test.dart` — only `playback_event_router.dart` may pattern-match a `PlaybackEndReason` variant; constructing one elsewhere is fine.
   - The context snapshot deliberately holds **no collaborators** (so the router can't call `moveToNext()`); time comparisons use `context.now`, the router never reads the clock (`playback_event_router.dart:22-27, 88-90`).
2. **Translation of native errors** belongs in the backend (via the shared rule file), never string matching in the controller (issue #41).
3. **Side effect on every track start** → implement `PlaybackSideEffect` and register it in `playbackSideEffectsProvider` (`playback_side_effects.dart:237-248`), not a new call site in the controller (dartdoc `:40-54`: two fan-out sites once diverged — lyrics were never matched after a gapless boundary).
4. **Queue mutation** → `QueueCommands`; Mix → `MixSessionCoordinator`; temporary play snapshot → `TemporaryPlayHandler`.
5. Controller size is ratcheted **both directions** on code lines (`test/support/audio_provider_size_static_rule_test.dart`); raising the limit requires the reason in the commit body (history of every bump is in that file's dartdoc, e.g. `e8cc8d8b` 2,160 → 2,178).
6. New cross-backend behaviour must be written twice or extracted to a shared rule (ADR 0003 consequences).

### 2.4 Race / concurrency guards (hard-won)
- **Monotonic request id + `isSuperseded(id)` after every await**: `PlaybackRequestSession.start` checks `isSuperseded(requestId)` after each `await` and returns `PlaybackSessionResult.superseded` (`playback_request_session.dart:210-273`); `isSuperseded` also true after dispose (`:200`).
- Exactly-named counters in audio: session id; `PlaybackHandoffGate.activeRequestId` (a latch of the session id, "not a second counter" — `playback_handoff_gate.dart:58-62`, `audio_provider.dart:108-114`); `_navRequestId` for `next()`/`previous()` awaits (`audio_provider.dart:103, 1017-1033`); `_mixStartRequestId` (`:127, 877-901`). The deleted audio AGENTS.md said "exactly three request ids, do not add a fourth" — `_mixStartRequestId` now exists as a fourth; the rule is **no longer written anywhere current**.
- Same generation-counter idiom outside audio (≥2 places): `AutoRefreshService._checkGeneration` + `_isCurrentCheck(generation)` after each await (`library/auto_refresh_service.dart:23, 57-128`), `RadioRefreshService._refreshAllGeneration` (`radio/radio_refresh_service.dart:58`), `RadioController._playRequestId`/`_isSuperseded` (`radio_controller.dart:252, 405-417`), `LyricsAutoMatchCoordinator._requestId` (`lyrics_auto_match_coordinator.dart:33`), `PlaybackRecoveryCoordinator._retryGeneration` (`:147`). Provider-side: `searchRequestId`, `FileExistsCache._cacheEpoch`. Commits `d6b0f8f4` "prevent stale async side effects", `798e2285`.
- **Object identity instead of ids** where the thing is replaced wholesale: `MixPlaylistSession` (`identical`, `mix_session_coordinator.dart:15-16`), `_PendingSeek` ("do not add `==`", `playback_handoff_gate.dart:6-12`), `_refreshCompleter == completer` check in `finally` (`bilibili_auth_interceptor.dart:108-112`).
- **Single-flight shared future** (≥3): `AudioController.initialize` (`_initialization ??=`), `BilibiliAuthInterceptor._ensureRefreshed` (Completer so concurrent 401s refresh once, `:90-114`), `LyricsCacheService._initFuture ??=` (`lyrics_cache_service.dart:49`).
- **Every discard path must complete the waiter**: `_PendingSeek.complete()` — "`AudioController.seekTo` awaits it; a forgotten path hangs the caller forever" (`playback_handoff_gate.dart:26-35`).
- **Generation + track-scoped marks** for cross-event ordering: output-device failure vs premature-end retry (mpv reports completion 4 ms *before* the `ao` error; `e8cc8d8b`, #106; `PlaybackEventContext.outputDeviceFailureMark`/`prematureEndRetryMark`).
- **Bounded waits everywhere**: `PlaybackTimeoutBudget` (T1 resolution 25 s, T2 media open 8 s, T3 starvation 15 s, total cap; `lib/core/constants/app_constants.dart` `PlaybackTimeoutBudget`), injectable for tests. `b952ccdf`: the restore path had an unbounded wait → spinner forever.
- **Pause cancellation windows**: `eef6f1bb` (desktop pause during open undone by `_ensurePlayback`), `349e20d0` (stream drop while paused must not auto-retry → mark and reopen on play; decision lives in router `DeferTransportFailureUntilPlay`).
- Position-check fallback timer exists because Android loses `completed` in background (`e9f07c3d`); it must go quiet once the queue is exhausted (`ecbaeb91`, 82 re-entries measured) and must not log every second (`e1bf1712`).
- Buffer-starvation rescue is once per track (`_bufferStarvationTrackKey`, `audio_provider.dart:~305`); cleared only on track change / give-up (`e981b7c3`, `7c0517a8`).

---

## 3. Download pipeline

- **Isolates**: each download runs `_isolateDownload` (top-level function, `download_service.dart:1784`) via `Isolate.spawn(..., onError: receivePort.sendPort, onExit: receivePort.sendPort)` (`:818-831`). Reason in code: avoids Windows "Failed to post message to main thread"; `onError`/`onExit` exist because an isolate killed outside try/catch sends nothing and the main isolate would wait forever, leaking the concurrency slot (`3a413e56`).
- Message protocol: `_IsolateMessage(_IsolateMessageType.{ready,progress,completed,error}, data)`; `ready` carries the cancel `SendPort`; errors are JSON `{'type': timeout|network|http|filesystem|unknown, 'message', 'path', 'access'}` mapped back to typed exceptions on the main side (`:1355-1372`).
- **Setup-window bookkeeping**: `_tasksInSetupWindow`, `_setupAbortedTasks`, `_externallyCleaned`, `_discardedTaskIds` (`:80-92`) with `_shouldAbortBeforeRegistration(task.id)` checks after every await before the isolate is registered (`:788-840`). Deleted tasks must not have resume progress saved in `finally` (`_discardedTaskIds`).
- **Media Handoff per hop** (CONTEXT.md): inside the isolate, `followRedirects = false`, manual loop ≤5 redirects, headers recomputed each hop through `const DefaultMediaHandoff().prepareDownloadHop(MediaHandoffRequest(sourceType:, url:, streamResolutionAuth:, rangeStart:))` (`:1848-1860`). Refuses scheme ≠ http(s) and public→private/loopback redirects (`SourceUrlPolicy.isLocalOrPrivateHost`, `:1823-1846`).
- **No credentials on media bytes**: `DefaultMediaHandoff._prepareHeaders` uses only `SourceHttpPolicy.mediaHeaders(sourceType)` + `Range` (`lib/services/media/media_handoff.dart:52-61`); `streamResolutionAuth` is carried but intentionally unused (dartdoc `:15-21`). Netease media-cookie path removed in `c09aec10` (never ran in prod).
- **Resume**: `rangeStart = resumePosition` when > 0; if server answers 200 instead of 206 restart from 0 (`shouldRestartFromZero`, `:1893-1895`); temp file `.downloading`; open with `File.open(mode: append|write)` — **not `openWrite()`** (eager open error kills isolate; comment `:1897-1902`, `3a413e56`). Per-chunk `response.timeout(networkReceiveTimeout)` because `HttpClient` has no read timeout (`:1911-1917`, explicitly untested). Startup: `resetDownloadingToPaused()` then orphan `.downloading` sweep by basename (`:196-270`, `c75ba23b`).
- **Progress**: isolate sends every 5 % (`AppConstants.downloadProgressUpdateThreshold`); main isolate batches into `_pendingProgressUpdates` (cap 256) and a periodic flush timer emits to `progressStream` only — **not written to Isar** to avoid watch-triggered rebuilds (`:317-320`). `_knownTotalBytes` needed for resume after flush (`f16e4de3`).
- **Paths** (ADR 0004): `DownloadPathUtils.computeDownloadPath` → `{baseDir}/{playlistName}/{sourceId}_{parentTitle}/P{n}.m4a`; `hasConfiguredPath()` gate before enqueue; Android `MANAGE_EXTERNAL_STORAGE` via `StoragePermissionService` MethodChannel (no `permission_handler`). Category deletion only deletes "proven FMP-owned files" (`4cdf64d0`).
- HLS rejected with a dedicated `UnsupportedDownloadStreamException` (`b9007f29`, `:1719-1734`).
- The download `Dio` sets only `SourceHttpPolicy.mediaUserAgent` (`:189-194`); it's on the header-literal allowlist in `test/support/source_http_policy_static_rule_test.dart:96-98`.
- Stored failure reason is a **translated sentence** (`_failureMessageFor` → `userMessageFor`, `:1374-1385`, `3cf68582`); raw text only in logs.

---

## 4. Account / auth

- **Credential storage**: JSON DTOs (`BilibiliCredentials`, `YouTubeCredentials`, `NeteaseCredentials`) in secure storage under keys `account_<source>_credentials`, through `SecureKeyValueStore` (`lib/core/secure_key_value_store.dart`), which converts `PlatformException`/`MissingPluginException` into `SecureStorageUnavailable(operation, code)` — code only, never message (may leak key alias/path). Introduced in `38837a9e` (#72); UI degradation `4378c4dc` (#35).
- Account services accept an injectable store (`SecureKeyValueStore? secureStorage` default `FlutterSecureKeyValueStore()`; `netease_account_service.dart:41-44`).
- `_loadCredentials` pattern (all three services, e.g. `bilibili_account_service.dart:551-575`): cache → read with `on SecureStorageUnavailable` → `logWarning` fixed message, return null (degrade to logged-out, **don't set the loaded flag** so it can recover) → `jsonDecode` with `on FormatException`/`on TypeError` → `_discardMalformedCredentials()` deletes the key, marks account logged out, logs a fixed message. Comment: "credential-related logs only write sanitized fixed messages: raw JSON, cookie strings, exceptions with tokens must not reach AppLogger".
- `AccountService` interface (`account/account_service.dart`): `platform`, `isLoggedIn`, `getCurrentAccount`, `logout` (deletes row) vs `markSessionExpired` (keeps row with `sessionExpired = true`), `refreshCredentials`, `needsRefresh`, `checkAccountStatus`, `getAuthHeaders` (shape per platform).
- Login-then-validate with snapshot/restore on failure: `NeteaseAccountService.loginWithCookiesAndValidate` (`:84-108`).
- **Dio interceptors** (`bilibili_auth_interceptor.dart`, `youtube_auth_interceptor.dart`, `netease_auth_interceptor.dart`) are built inside services and can't reach Riverpod: they only write `Account.sessionExpired`; the toast is raised by `accountSessionExpiryWatcherProvider`, de-duplicated per platform per session by `SessionExpiryNotifier` (`account/session_expiry_notifier.dart`).
- **Source Auth Context** (`account/source_auth_context.dart`): `authForPlay(sourceType)` returns creds only if `Settings.useAuthForPlay(sourceType)` (Auth For Play) (`:133-137`); playlist import/refresh use their own flags (`playlistImportAuth(useAuth:)`, `playlistRefreshAuth(useAuthForRefresh:)`) — Auth For Play does not gate import/refresh/search (CONTEXT.md). `AccountServiceAuthLoader.load` returns null for a source with no account service and must not fall back to another platform's cookies (`:31-35`).
- Media byte requests: `playbackNetworkRequest(track, url)` → `MediaHandoff.preparePlayback` → headers = `SourceHttpPolicy.mediaHeaders(sourceType)` only.
- All API Dio instances come from `SourceHttpPolicy.createApiDio(SourceIds.x, ...)` (e.g. `netease_account_service.dart:46-50`, `bilibili_favorites_service.dart:47-51`). **Gated**: `test/support/source_http_policy_static_rule_test.dart` (any file naming `SourceIds.x` that builds a raw client; per-file allowlist for hand-written Referer/Origin/UA with a `why`).
- Tests: `test/services/account/source_auth_context_test.dart`, `account_secure_storage_failure_test.dart`, `account_credentials_redaction_test.dart` (sentinel secrets must not appear in `AppLogger.logs`), `account_session_expiry_test.dart`.

---

## 5. Platform branching

- **Audio layer uses an injectable abstraction**: `AudioRuntimePlatform {mobile, desktop}` + `audioRuntimePlatformProvider` (`audio/audio_runtime_platform.dart`); `NowPlayingPublisher` takes it in the constructor and "does not import `dart:io`" (`now_playing_publisher.dart:48-60`) — it absorbed 12 `Platform.isX` checks from `AudioController` and 10 from `RadioController`. Tests pass `platform:` explicitly (`test/support/now_playing.dart`).
- **Elsewhere, direct `Platform.isWindows/isAndroid` with early return** is the norm: `WindowsDesktopService` (`if (!Platform.isWindows) return;` ×7, `platform/windows_desktop_service.dart:51-423`), `WindowsSmtcHandler.initialize` (`:104`), `UpdateService` (×14), `DownloadPathManager`/`DownloadPathUtils` (Android default dir), `BackupService` (import keeps device-specific Windows settings, `backup_service.dart:693-707`), `UrlLauncherService`.
- Testable override seams where a branch must be tested: `StoragePermissionService.debugIsAndroidOverride` + `debug*` function statics + `resetDebugOverrides()` (`platform/storage_permission_service.dart:30-60`); `LyricsWindowService.isWindows` getter (`lyrics/lyrics_window_service.dart:54`).
- UI/other code uses `isDesktopPlatform` (`lib/core/utils/platform_utils.dart`), and `FmpAudioService` dartdoc tells UI to use it rather than "device list empty".
- Android-only behaviour (audio focus, becoming-noisy) lives only in `JustAudioService.initialize()`; don't write MediaKit tests asserting it (`audio_service.dart:9-13`).
- **No static rule gates `Platform.is*`** — convention only.

---

## 6. Error handling

- **Source errors**: adapters wrap Dio errors into `SourceApiException` subclasses (`lib/data/sources/source_exception.dart`) with `SourceErrorKind` and policy getters `isRetryable` (network/timeout), `shouldSkipTrack` (unavailable/geo/vip), `canFallbackToLowerAudioQuality`. Services branch on `kind`, not on message strings.
- **Classification by type, never substring**: `PlaybackErrorPresenter.isRetryable` (`playback_error_presenter.dart:57-76`): `PlaybackTimeoutException` → no; `SourceApiException` → `kind.isRetryable`; `SocketException/HttpException/TlsException/TimeoutException` → yes; anything else → **logWarning and do not retry** ("silently guessing it's a network error is where issue #41 came from"). Same stance in `userMessageFor` (unlisted types → "unknown error").
- **User-visible text**: always via `userMessageFor(error)` / `sourceErrorReason` (`lib/core/errors/user_message.dart`) — never `e.toString()`. `failureMessage(error, stack, what, tag:)` logs + returns the translated sentence for `state.error` (`search_service.dart:109-114`). Import: `_updateProgress(status: failed, error: userMessageFor(e))` (`import_service.dart:321,400,533`). Radio: `t.radio.playFailed(error: userMessageFor(e))`. **Gated** (scans all `lib/`): `test/ui/static_rules/error_presentation_static_rule_test.dart` "no i18n error template is filled with raw exception text" (the case that motivated it came from `lib/services`: raw `ClientException` with URL on the search page, `a8eb4304`).
- **How errors reach UI from services**:
  - Toast via `ToastService` instance methods (`showError/showWarning/...`) — a broadcast stream consumed by the app shell. Only 4 service files toast directly: `audio_provider.dart` (12), `mix_session_coordinator.dart`, `queue_commands.dart`, `session_expiry_notifier.dart`. Others emit events/state and let the provider toast (`download_providers.dart:71-76`).
  - `state.error` on Notifier-state (`AudioController`, `RadioController`), progress objects with `error` (`ImportProgress`), result objects (`MultiSourceSearchResult.error`), persisted translated reason (`DownloadTask.errorMessage`).
  - Typed results instead of exceptions for expected outcomes: `PlaybackSessionResult`, `DownloadResult` enum, `QueueCommands` result, `RemotePlaylistEditResult`.
- **Degrade, don't throw, on infrastructure failure** in paths used by playback/startup: credential store (§4), `QueueRepository` writes after DB close (`5f3bec68`), `readOptional(ref, provider)` swallows provider-construction exceptions so optional collaborators become null (`playback_side_effects.dart:250-270`), side-effect fan-out wraps each consumer in try/catch (`_guard`, `:116`).
- **Partial results**: `searchSourcesInParallel` (`search/source_search_fanout.dart`) — per-source failures go to `onSourceError`; must not be silently swallowed (the old `SourceManager.searchAll` did).
- **`await` inside `try`**: returning an un-awaited future from a `try` bypasses its `catch` (`ca54669c`, fixed in `bilibili_source.dart`, `youtube_source.dart`, `import_service.dart`).
- **Retry / backoff ladders** (all in constants or class statics, each with its reason):
  - Playback: `NetworkRetryConfig.retryDelays` 1/2/4/8/16 s, max 5 (`app_constants.dart`), driven by `PlaybackRecoveryCoordinator`; network recovery event restarts it.
  - Stream resolution: retry once — 3 s if `isRateLimited` (`streamResolutionRateLimitRetryDelay`, B站 -352 window), else 1 s; other `SourceApiException`s rethrow (`stream_resolution_service.dart:206-245`, `50a55552`).
  - Ranking: `RankingCacheService.defaultFailureRetryDelays` 5 s, 30 s, 2 min, 10 min then hand back to periodic (`88cf0b60`).
  - Radio polling: `interval × 2^n` capped at 30 min on risk-control, paused in background (`RadioRefreshService.maxBackoff`, `0110b397`, #95); `RadioReconnectConfig` 1/3/10 s.
  - Mix: `mixRetryDelay`, `mixMaxLoadAttempts`.
- Media-open errors: wait `_mediaOpenRecoveryDelay` (2 s) to see if the backend self-recovers (position advanced > 0.5 s) before declaring terminal (`playback_request_session.dart:343-414`).
- Output-device failure must **not** blame the track (`056f20c3`, #41) and must stop retries (#106).

---

## 7. Logging

- Logger: `lib/core/logger.dart`. Services use `with Logging` (51 files) → `logDebug/logInfo/logWarning/logError(msg, [error, stack])`; tag = `runtimeType` (no class overrides `logTag`). Static `AppLogger.x(msg, tag)` is used where there's no instance: `UpdateService` (21, with `_tag`), `ToastService.failure`, `failureMessage(..., tag:)`, `remote_playlist_edit_controller.dart` (1). No `print`/`debugPrint` in services.
- Levels as used: `logDebug` = flow detail (resolution timings, "Task already downloading"); `logInfo` = lifecycle milestones ("AudioController initialized successfully", "Media control owner -> radio", login success); `logWarning` = degraded/recoverable (credential store unavailable, unclassified error, retry scheduled, rate limited); `logError(msg, e, stack)` = failures with stack. Release min level is `info` (`AppLogger._minLevel`).
- **Redaction** is centralized: every message and `error.toString()` goes through `AppLogger.redactSensitive` (Authorization, Bearer, SAPISIDHASH, Cookie header, and a key list incl. `SESSDATA`, `bili_jct`, `csrf`, `MUSIC_U`, `SAPISID`, `__Secure-*PSID`, `refresh_token`, `access_token`, `apiKey`, `eparams`, `password`, `token`) before buffer/file/console (`logger.dart:80-195`). Adding a new secret name means adding it here (`1cf2989c` added `eparams`/`apiKey`). Tested in `test/services/account/account_credentials_redaction_test.dart` ("AppLogger redacts complete auth header values").
- **Never log**: raw credential JSON, cookie strings, token-bearing exceptions (fixed sanitized messages only — `bilibili_account_service.dart:557-563`); `SecureStorageUnavailable` carries code not message.
- Log identifiers: resolution/download logs use `TrackKey.formatGroup(sourceType, sourceId)` via a private `_describe(track)`, not the title (`stream_resolution_service.dart:392-398`, `audio_stream_manager.dart:169-172`, `download_path_sync_service.dart:275`, `download_path_maintenance_service.dart:314`).
- **Caveat (factual)**: signed stream URLs are **not** redacted — backends log `media.debugUrl` (the full URL) at debug level (`just_audio_service.dart:259,706`, `media_kit_audio_service.dart:303,989`); `docs/development.md` only asks humans not to paste signed URLs/cookies. No test gates URL logging.
- Don't log per-second polls (`e1bf1712`: the file sink keeps 3 files; idle spam would evict everything useful). Log timings as `in ${stopwatch.elapsedMilliseconds}ms`.

---

## 8. Async conventions

- **Check disposal/staleness after every `await`**: `if (_isDisposed) return;` sequences in `AudioController._runInitialization` (`audio_provider.dart:346-433`), `DownloadService.initialize` (`:200-224`); generation checks in `AutoRefreshService`; `ref.mounted` after awaits in Notifiers (`radio_controller.dart:311-319, 399, 831`; `a43fddbe` — Riverpod 3 throws `UnmountedRefException` in release; preferred fix is hoisting reads above the await).
- **`unawaited(...)` is explicit** (24 sites) and failure-bearing ones attach `.catchError` with a log: `unawaited(_audioService.dispose().catchError(... logError ...))` (`audio_provider.dart:475-479`), `setNextMedia(null).catchError(logWarning)` (`:1713-1716`). Sync stream handlers call `unawaited(_apply(PlaybackEventRouter.routeX(...)))` (`:1320, 2365, 2668`). Note: `unawaited_futures` lint is **not** enabled (`analysis_options.yaml` has only `flutter_lints` + `always_use_package_imports`, `comment_references`, `deprecated_member_use_from_same_package`, const lints).
- Just_audio `play()` is deliberately not awaited (`just_audio_service.dart:575, 631`) because it blocks until the platform request finishes (dartdoc on `FmpAudioService.playMedia`).
- **Timers, not `Future.delayed`, for anything that must be cancellable** (`5f3bec68`: a `Future.delayed` orphan sweep fired against a closed Isar). `Future.delayed` is used for in-flow waits (`AutoRefreshService` 5 s spacing, stream-resolution retry) and injected as `delay` in `PlaybackRequestSession`.
- **Every `Timer.periodic`/`Stream.periodic` is registered** with purpose, source commit/issue and whether the user can turn it off — **gated** by `test/support/periodic_timer_static_rule_test.dart` `_timers` (services listed: connectivity DNS poll, ranking refresh, auto refresh, radio refresh, radio controller ×2, audio position check, queue position save, download progress flush + scheduler). A self-rescheduling `Future.delayed` loop is invisible to the rule and should be a `Timer.periodic` instead (rule dartdoc).
- Every hard-coded host must be on `test/support/outbound_hosts_static_rule_test.dart` `_hosts`; DNS lookup targets on `_dnsLookups`.
- Debounce: `DebounceDurations.standard` passed into `DownloadEventHandler` (`download_providers.dart:77`); notification/SMTC position throttled in controller (`_lastNotificationPosition`).
- Event-driven scheduling + periodic safety net: `DownloadService._scheduleController` broadcast trigger plus `_schedulerTimer` (`:118-131`).
- Cancellation: no Dio `CancelToken` in services (grep: none); cancellation is flags (`ImportService._isCancelled`, `import_service.dart:115-124`), generation counters, or isolate cancel ports.

---

## 9. Comments & dartdoc

- Traditional Chinese for new/edited comments; tree is mixed (≈32 of 100 service files still contain Simplified, 59 contain Traditional). Convert only lines you touch (AGENTS.md). Examples: `queue_manager.dart` (Simplified header), `download_service.dart` (mixed), `audio_provider.dart` / `playback_*` (Traditional).
- Dartdoc idioms repeated across the audio layer:
  - **"What it deliberately does not own"** paragraph (`它刻意**不擁有**` / `**它不碰 PlayerState**` / `**它不啟動播放**`): `NowPlayingPublisher` (`:60-63`), `PlaybackSideEffect` (`:50-54`), `PlaybackHandoffGate`, `PlaybackErrorPresenter`, `MixSessionCoordinator`, `TemporaryPlayHandler`, `QueueCommands`.
  - **Measured facts with dates/numbers** ("實測"/"measured": 26 occurrences in `lib/services`), e.g. `PlaybackTimeoutBudget` fields, `audio_service.dart` buffer sizes.
  - **Commit hashes and issue numbers** inline for why a line exists (e.g. `audio_service.dart` "`16318b87` 修過", `playback_error_presenter.dart` issue #41, 18 issue refs in services).
  - Backend differences on `FmpAudioService` members (ADR 0003).
  - Library-level `/// ... library;` docs for rule files (`playback_event_router.dart`, `playback_end_reason_rules.dart`).
- `comment_references: true` lint → `[Identifier]` references in dartdoc are checked; that's why rationale lives in dartdoc rather than markdown (`analysis_options.yaml` comment).
- `// ignore:` is rare (1 in services: `radio_refresh_service.dart:66`).

---

## 10. Static-rule gates vs convention (services-relevant)

| Rule | Gate |
|---|---|
| `isar.` only in `lib/data/repositories/` (+2 db files) | `test/data/static_rules/isar_boundary_static_rule_test.dart` |
| core/data don't import services/providers; new cross-feature import edge must be recorded | `test/support/layer_boundary_static_rule_test.dart` |
| Only `playback_event_router.dart` pattern-matches `PlaybackEndReason` | `test/services/static_rules/playback_event_routing_static_rule_test.dart` |
| Completion/keyword rules exist once; all backends delegate | `test/services/static_rules/audio_backend_shared_rules_static_rule_test.dart` |
| `PlayerState` ∩ `QueueState` = ∅; `PlaybackRequestStreamAccess` members fixed; only 2 files name wide `SourceAuthContext` | `test/services/static_rules/audio_seam_static_rule_test.dart` |
| `audio_provider.dart` code-line ratchet (both directions) | `test/support/audio_provider_size_static_rule_test.dart` |
| Every persisted `Settings` field backed up or explicitly excluded with reason | `test/services/static_rules/settings_backup_coverage_static_rule_test.dart` |
| Lyrics child-window strings all pushed | `test/services/static_rules/lyrics_window_strings_static_rule_test.dart` |
| Every periodic timer listed | `test/support/periodic_timer_static_rule_test.dart` |
| Every hard-coded host listed | `test/support/outbound_hosts_static_rule_test.dart` |
| Source API clients via `SourceHttpPolicy`; header literals allowlisted | `test/support/source_http_policy_static_rule_test.dart` |
| Owner table: bilibili live API only in live client; no `sourceManagerProvider`/source calls in UI; playlist invalidation via coordinator | `test/support/call_site_ownership_static_rule_test.dart` |
| Source-id branch budget outside `lib/data/sources/` | `test/support/source_branch_points_static_rule_test.dart` |
| No raw exception in i18n error templates (all `lib/`) | `test/ui/static_rules/error_presentation_static_rule_test.dart` |
| No legacy Riverpod; side-effect providers anchored in `FMPApp.build` | `test/providers/static_rules/riverpod3_static_rule_test.dart` |
| `pumpEventQueue` only in `pump_until.dart` | `test/support/wait_convention_static_rule_test.dart` |
| Tests that construct real network sources are tagged `live` | `test/support/live_source_tag_static_rule_test.dart` |
| Static-rule tests named `*_static_rule_test.dart` in `test/support/` or `test/<layer>/static_rules/` | `test/support/static_rule_placement_static_rule_test.dart` |
| `android:allowBackup="false"` | `test/support/android_manifest_static_rule_test.dart` |
| Dependabot excludes 0.x deps; `flutter_secure_storage` major ignored | `test/workflows/dependabot_group_static_rule_test.dart` |

Static-rule tests share a shape: parse with `test/support/dart_source.dart` (`stripDartComments`), compare **sets not string presence**, assert the scan itself found something (e.g. `expect(sources.length, greaterThan(300))`), and include a synthetic-violation test plus a "reformat/rename/comment does not trip it" test.

**Convention only (no gate)**: UI → `AudioController` not `FmpAudioService` (AGENTS.md says so explicitly); `Platform.is*` placement; `_isDisposed` checks after await; provider-owns-dispose; not logging signed URLs; "add a router variant, not an `if`" beyond the pattern-match rule; raw `playUrl` only for radio; comment language; `unawaited` + `catchError`.

---

## 11. How service tests are written

- **No mocking library** (dev_dependencies: `flutter_test`, `build_runner`, `isar_community_generator`, `flutter_lints`, `slang`, `http`, `yaml`; grep finds no mockito/mocktail/fake_async). Hand-written fakes:
  - Shared fakes in `test/support/fakes/`: `FakeAudioService` (implements `FmpAudioService`; broadcast controllers; call logs `playMediaCalls`, `setNextMediaCalls`, `seekCalls`; `emitEndReason/emitCompleted/emitOutputDeviceFailure/...`; `waitForPlayUrlCallCount` via `CountWaiters`; `playUrlSettlesReady` knob), `FakeSourceAuthContext` (logged-out, other members via `noSuchMethod` so unexpected calls throw), `MemorySecureKeyValueStore` / `UnavailableSecureKeyValueStore`, `FakeIsar extends Fake implements Isar`, `FakeSettingsRepository`, `secure_storage_channel.dart`.
  - File-local fakes named `_FakeX`, `_RecordingX`, `_StubX` implementing the narrow interface (`_RecordingAccountAuthLoader`, `_RecordingMediaHandoff` in `source_auth_context_test.dart:250-261`; `_StubSourceManager` in audio controller tests; `_RecordingBilibiliSource extends BilibiliSource` in download tests). `FakeSourceAuthContext` dartdoc: test-specific variations belong in the test file, not as switches on the shared fake.
- **Real Isar in a temp dir** rather than fake repositories (ADR 0002): `setUpAll(initializeIsarForTests)` (`test/support/isar_test_harness.dart`), `Directory.systemTemp.createTemp('<name>_')`, `Isar.open([...Schemas], directory:, name: '<test name>')`, `tearDown` → `isar.close(deleteFromDisk: true)` + delete dir (e.g. `test/services/account/account_secure_storage_failure_test.dart:22-45`).
- **AudioController** is built through `buildTestAudioController(...)` / `buildTestAudioControllerIn(...)` (`test/support/audio_controller_harness.dart`), which translates collaborators into provider overrides on a `ProviderContainer` (`addTearDown(container.dispose)`), silences connectivity, and always overrides `optionalLyricsAutoMatchServiceProvider` (else it drags in secure storage). `testNowPlayingPublisher()` uses real `FmpAudioHandler` + uninitialized `WindowsSmtcHandler` (safe even on Windows).
- **Time**: no fake clock; timing is controlled by injection — `PlaybackTimeoutBudget` (short values in tests), `delay:` in `PlaybackRequestSession`, `timerFactory:` in `PlaybackRecoveryCoordinator`/`BufferStarvationWatchdog`, `stabilizationDelay:` in `PlaybackHandoffGate`, `PlaybackEventContext.now`. Download isolate timeouts are explicitly untested ("can't drive a fake clock in an isolate").
- **Waiting**: `pumpUntil(condition, reason:)` for a condition false on entry; `drainEventQueue(reason:)` for asserting absence; `CountWaiters` in fakes for "N calls happened"; direct `pumpEventQueue` is banned (#43, #55). Waiting on a monotonic counter instead of pump counts (`5f3bec68`).
- `@visibleForTesting` debug hooks on production classes where needed: `DownloadService.debugStartDownloadForTesting`, `debugKillDownloadIsolateForTesting`, `debugFlushPendingProgressUpdatesForTesting` (`download_service.dart:1624-1680`); `StoragePermissionService.debug*` statics with `resetDebugOverrides()`.
- Local `HttpServer.bind` for download isolate tests (`test/services/download/download_service_progress_and_disposal_test.dart`); tests that hit real APIs must be tagged `live` and are excluded in CI (`flutter test --exclude-tags live`).
- Regression tests open with a `///` doc naming the issue and pasting the measured log that motivated it (e.g. `test/services/audio/audio_controller_output_device_failure_test.dart:13-36` for #106). Pure rule collaborators get pure-function tests (`playback_event_router_test.dart`, `backend_contract_test.dart`, `playback_handoff_gate_test.dart`).
- Assertions on logs use `AppLogger.logs` and `AppLogger.clearLogs()` in setUp/tearDown (`account_*_test.dart`).
- `test/workflows/` tests read `.github/workflows/*.yml` / `.github/dependabot.yml` / `pubspec.yaml` with the `yaml` package and run `tool/release/verify_release_assets.dart` against fake artifacts; they're structural checks on CI config, not service tests.

---

## Caveats / Not Found

- The "three request ids, don't add a fourth" rule and the `playUrl`-only-for-radio rule exist only in the deleted `lib/services/audio/AGENTS.md` (`e0e6c0c7^`); current code has a fourth counter (`_mixStartRequestId`). Treat as history, not a live rule.
- Signed stream URLs are logged at debug level by both backends; nothing redacts or gates this.
- `unawaited_futures` / `discarded_futures` lints are off; explicit `unawaited` is a habit, not enforced.
- Services with a static `instance` singleton exist as one-offs (`RadioRefreshService.instance`, `LyricsWindowService.instance`, `UrlLauncherService.instance`) plus `main.dart` globals `audioHandler` / `windowsSmtcHandler` imported by `now_playing_publisher.dart`.
- `lib/core/services/image_loading_service.dart` and `network_image_cache_service.dart` were only skimmed (mostly widget/cache code, Simplified comments); image rules are UI-gated (`ui_consistency_static_rule_test.dart`) and out of this scope.
- Not every service subdirectory was read line-by-line (lyrics, library remote-edit, update, backup internals were sampled); patterns above are those confirmed in ≥2 places or explicitly documented.
