# lib/services/audio AGENTS.md

Audio guidance for `AudioController`, playback backends, queue, stream handoff,
temporary playback, Mix mode, and network error recovery.

## Preferred Audio Device

`setAudioDevice` / `setAudioDeviceAuto` persist the choice into
`Settings.preferredAudioDeviceId` / `preferredAudioDeviceName`, and
`_restorePreferredAudioDevice` reapplies it **once**, the first time the
device list arrives.

Two deliberate behaviours, both easy to break:

- It restores once per session. The device list changes whenever something is
  plugged in or out; reapplying every time would overwrite whatever the user
  just chose.
- A remembered device that is not currently connected is left in Settings, not
  cleared. The user plugs the headphones back in and expects them selected.

Desktop only — Android exposes no device picker.

Both behaviours are pinned by
`test/services/audio/audio_device_preference_test.dart`; the fake's
`emitAudioDevices` is what stands in for a plug event.

## Architecture

```text
UI playback controls
        |
        v
AudioController (audio_provider.dart)
  - PlayerState, business logic
  - temporary/mix/detached playback modes
  - mute memory, notification/SMTC coordination
        |            |            |
        v            v            v
FmpAudioService  QueueCommands  QueueManager
  (abstract)     - mix gate     - queue order, shuffle/loop
  |              - full/throw   - navigation, persistence hooks
  v                 -> result
JustAudioService (Android)
MediaKitAudioService (Desktop)
```

`QueueCommands` (`queue_commands.dart`) is the first collaborator pulled out of
the controller. It owns the template the seven queue methods used to repeat —
the mix-mode gate, the queue-full toast, and turning an exception into a
`QueueMutation` instead of letting it escape — and returns
`applied` / `blocked` / `failed`. It deliberately touches neither `PlayerState`
nor the playback context: **projection stays in `AudioController`**, and mix
mode is passed in rather than inferred.

`clearQueue` is the one command with controller-side after-effects (leaving mix
mode, dropping the still-playing track into detached mode); those stay in
`AudioController` because they are session state, not queue state. `playAt` was
deliberately left behind too — it starts playback, so it belongs with the
transport commands, not with the queue mutations.

**Key rule: UI must call `AudioController` methods, never `FmpAudioService`
directly.** This is an architectural convention rather than a compile-time
boundary — use `rg` when reviewing UI playback changes.

Radio is the intentional non-UI exception: `RadioController` uses the shared
backend directly while ownership hooks make `AudioController` ignore radio-owned
backend events.

## Ownership

- `AudioController` (`audio_provider.dart`) — user-facing state,
  temporary/mix/detached modes, notification/SMTC coordination, queue-visible
  playback decisions, history/lyrics side effects, source-error UI decisions.
- `PlaybackRequestSession` — playback request tokens, supersession, active
  loading request state, backend stop/handoff, queue restore handoff, fallback
  handoff, media-open pending recovery.
- `PlaybackRecoveryCoordinator` — playback network retry generation, scheduled
  retry state, manual retry, network-recovered retry, premature completion
  recovery.
- `StreamResolutionService` — stream URL resolution, local-file selection and
  stale download-path cleanup, quality fallback, alternative stream lookup, URL
  expiry persistence, prefetch dedupe, and in-process reuse of an already
  resolved stream. Reuse requires a still-fresh `Track.audioUrl`, a cached
  `AudioStreamResult` whose URL still matches it, and an unchanged stream config
  and auth header set; downloads never reuse. `invalidateStream()` must be
  called whenever playback fails on a URL — an unexpired URL is not necessarily
  a working one, and without that call a dead CDN URL is handed back on every
  retry. Asks `SourceAuthContext.authForPlay()`
  for the auth used during stream resolution.
- `AudioStreamManager` — playback selection; prepares `PreparedPlaybackMedia`.
  Depends on the narrow `PlaybackMediaRequestContext` interface for remote-stream
  handoff before producing `RemotePlaybackMedia`. `SourceAuthContext` owns the
  Auth For Play gate; byte-request URL/header policy is delegated to
  `MediaHandoff` (see `lib/data/sources/AGENTS.md` § Auth For Playback And
  Headers).
- `QueueManager` — queue order, shuffle/loop state, navigation, persistence hooks.
- `QueuePersistenceManager` — persisted queue snapshots, saved position/volume,
  Mix metadata restore.

`PlaybackRequestStreamAccess` is the session-facing interface and should stay
limited to playback selection, fallback selection, and prefetch. Do not expose
intermediate stream-resolution or network-handoff phases through it.

Music playback opens media through `FmpAudioService.playMedia()` / `setMedia()`.
Direct `playUrl()` / `setUrl()` remain for radio and compatibility-only paths —
do not add new music playback callers for raw URL methods.

## Platform Split

- Android: `JustAudioService` (ExoPlayer via `just_audio`, smaller binary).
- Desktop: `MediaKitAudioService` (libmpv via `media_kit`, supports device
  switching). `MediaKit.ensureInitialized()` is called only on desktop.
- `audioServiceProvider` selects the implementation through
  `audioRuntimePlatformProvider`.
- Mobile notification state is owned by `AudioController`/`FmpAudioHandler`.
  During controller-owned load phases such as queue next/previous URL
  resolution, backend `idle` events from `FmpAudioService.stop()` must not
  overwrite notification `loading` state or clear the next track media item.
- Volume conversion: `media_kit` uses 0–100, `just_audio` uses 0–1.

Custom types: `audio_types.dart` (backend processing/device types such as
`FmpAudioProcessingState`, `FmpPlayerState`, `FmpAudioDevice`),
`player_state.dart` (`PlayerState`), `audio_playback_types.dart` (playback
request/mode DTOs).

## Playback Context And Play Lock

`AudioController` uses `_PlaybackContext` to manage playback state and prevent
race conditions.

```dart
enum PlayMode { queue, temporary, detached, mix }

class _PlaybackContext {
  final PlayMode mode;
  final int activeRequestId; // > 0 = loading
  final int? savedQueueIndex;
  final Duration? savedPosition;
  final bool? savedWasPlaying;
}
```

Any method that starts backend playback or fetches playback URLs outside
`PlaybackRequestSession` must either move into the session or use an explicit
session handle/cancellation check. **Do not add new raw request-id counters in
`AudioController`.**

## Temporary Play

Clicking a song in search/playlist plays temporarily without modifying the
queue. After completion, the original queue position is restored with a rewind
offset.

- Uses `playTemporary()`, not `playTrack()`, via `_executePlayRequest()` with
  `mode: PlayMode.temporary`.
- Saved state in `_PlaybackContext`: `savedQueueIndex`, `savedPosition`,
  `savedWasPlaying`.
- Position restore is controlled by `Settings.rememberPlaybackPosition`.

## Playback End Reasons

`FmpAudioService` exposes a single `Stream<PlaybackEndReason> endReasons`
(`audio_types.dart`). It replaced the old `Stream<void> completedStream` plus
`Stream<String> errorStream` pair.

**Backends translate; `AudioController` only dispatches.** Each backend turns its
engine's native message into a `PlaybackEndReason`, because only the backend
knows whether it is looking at mpv or ExoPlayer. Never re-introduce error-string
matching in `AudioController` — that is what produced issue #41: mpv's
`Could not open/initialize audio device -> no sound.` matched the `could not
open` keyword meant for *media* open failures, so a dead audio device was
reported to the user as `播放失敗: <song>`.

The variants and who must produce them:

| Variant | Backend must emit it when | Controller does |
|---|---|---|
| `EndedNaturally` | position is within `AppConstants.completionTolerance` of duration | advance the queue |
| `EndedPrematurely` | engine says completed but position is far from duration, **or duration was never reported** | retry the current track from the saved position |
| `TransportFailed` | connection reset/timeout/DNS/TLS (mpv `tcp:` / `ffurl_read`, ExoPlayer `Source error`) | retry or refetch the URL, **not** advance |
| `OutputDeviceFailed` | the audio *output* failed — nothing to do with the media | stop and show the audio-output message; **must not** blame the track |
| `MediaUnopenable` / `DecoderFailed` | the media itself cannot be opened or decoded | delay briefly for self-recovery, then surface a terminal playback error |
| `UnclassifiedFailure` | anything the backend cannot place | log it and ignore — but visibly |

`duration == null` counts as `EndedPrematurely`, not as a natural end. A stream
that connects but delivers zero bytes reports exactly that shape, and treating it
as "finished" makes the player skip through the whole queue in silence.

`MediaKitAudioService` must subscribe to **both** `player.stream.error` and
`player.stream.log`: media_kit only forwards log messages whose prefix is
`file` / `ffmpeg` / `vd` / `ad` / `cplayer` / `stream` to its error stream, so
`ao`-prefixed audio-output failures never reach `errorStream` at all.

Other rules that survive the change:

- Retry suppression must be generation/current-track aware. A fresh backend
  network error during manual or automatic retry handoff schedules a new retry
  generation; stale handoff completion must not clear the fresh retry state.
- Ignore every end reason while in loading/retrying/network-error state.
- Only source availability failures marked with `SourceErrorKind.shouldSkipTrack`
  should auto-skip to the next queue item.
- Playback-visible stream metadata (`currentBitrate`, `currentContainer`,
  `currentCodec`, `currentStreamType`, duration, buffered position) belongs to
  the active playback request. Entering a controller-owned load or clearing the
  playing track must clear stale values first; successful playback then replaces
  them from that request's `AudioStreamResult`.
- Detail providers must clear stale `VideoDetail` when the current track changes,
  so the detail panel never shows metadata from the previous successful song
  during loading or failure.
- On resume after a long pause, refresh expired audio URLs before playing and
  seek back to the prior position when appropriate.
- Fire-and-forget backend cleanup futures must catch and log errors. Provider
  dispose can cancel controller subscriptions synchronously, but async
  `FmpAudioService.dispose()` failures must not become unhandled async errors.

### Timeout budget

`PlaybackTimeoutBudget` (`lib/core/constants/app_constants.dart`) puts an upper
bound on each loading stage. Without it the wait is decided entirely by the
engine: a stream that connects but sends nothing measured 6.1s of *apparent
success* on Windows and a 37.7s block on Android, and a YouTube fall back to
muxed took 9.9-20s.

| Budget | Bounds | Enforced in |
|---|---|---|
| `streamResolution` (T1) | turning a track into a playable URL | `PlaybackRequestSession._withBudget` around `selectPlayback` / `selectFallbackPlayback` |
| `mediaOpen` (T2) | handing that URL to the backend | `_waitForRequestOperation(phase: mediaOpen)` |
| `bufferStarvation` (T3) | continuous re-buffering during playback | `BufferStarvationWatchdog`, fed from `_onPlayerStateChanged` |

Exceeding a budget throws `PlaybackTimeoutException`, **not** `TimeoutException`.
The distinction carries the policy: a budget overrun means FMP chose to stop
waiting, so it gets one fallback stream and then stops with a message; a
`TimeoutException` from an adapter is one network hiccup and goes through the
1/2/4/8/16s ladder. `_isRetryableError` must keep checking
`PlaybackTimeoutException` **before** `TimeoutException`, or every timeout turns
into five full re-resolutions.

A superseded request never reports a timeout — being replaced is not a failure.

**Re-buffering is a substate of playing.** `BufferStarvationWatchdog` never tears
playback down; it only reports that buffering has been *continuous* for longer
than T3, which is the backstop for the case where the engine says nothing at all
(a stream that connects and sends zero bytes reports `playing: true`, no
duration, and never emits an error). The countdown starts when buffering begins
and is not restarted by further buffering events — restarting it on every event
means it never fires. It is disarmed by leaving buffering, by a seek, by a new
playback request, by radio taking over, and by dispose.

Starvation recovery follows the same policy as T1/T2: discard the reusable
resolution, re-issue the request once through `retryPlayback` (whose `_execute`
supplies the one fallback attempt), and stop with a timeout message if that
fails too. It deliberately does **not** call
`PlaybackRecoveryCoordinator.scheduleRetry`, so it never enters the backoff
ladder. A track is rescued at most once; the guard clears when the playing track
changes, not when a request starts, or the rescue attempt would clear its own
guard and loop.

Every request also carries a single deadline of `budget.total` (T1+T2), so the
fallback attempt spends what is left rather than starting a fresh budget.
Without it the worst case is (T1+T2)x2, which at the current T1 would be worse
than the 37.7s Android block this work exists to remove.

T1 is a backstop against waiting forever, not a gate to force speed — P0-2 asked
for *bounded*, not *short*. It has to clear the slowest path that still works:
when YouTube's androidVr audio-only is refused by the bot check, falling back to
muxed measured 21.3-22.7s on the Android emulator and 9.9s on a desktop host,
and that refusal is the common case rather than the exception. A T1 that cannot
cover it does not make playback fast, it makes those videos unplayable, so the
value is set generously. The common path — audio-only succeeding — takes 1-2s
and never approaches it.

T1 is what stops the three retry layers from multiplying. The inner resolution
retry (once, after `AppConstants.streamResolutionRetryDelay`) and the
high/medium/low quality ladder both run *inside* `selectPlayback`, so T1 caps
their combined cost rather than each of them separately. The third layer, the
backoff ladder in `PlaybackRecoveryCoordinator`, is deliberately outside it: it
answers a different question (playback failed after it had started), and
timeouts never reach it.

### Buffer profiles (deliberate, do not revert casually)

Desktop `MediaKitAudioService` uses an aggressive network buffer profile for
online music playback: 32MB player buffer, 24MB demuxer forward buffer, 8MB
demuxer back buffer, 7200s mpv cache/readahead, and FFmpeg/lavf reconnect
options (`reconnect=1`, `reconnect_streamed=1`, `reconnect_on_network_error=1`,
`reconnect_delay_max=2`, `reconnect_max_retries=3`). Keep `vid=no` and `sid=no`
enabled so muxed fallback streams do not decode video while the larger buffer
absorbs VPN/CDN stalls.

`_configureForAudioOnly()` also sets four properties that are easy to drop by
accident because their purpose is not obvious from the name:

| Property | Why |
|---|---|
| `cache=yes` | Required for `cache-secs` to take effect at all |
| `cache-pause-initial=no` | Start playing immediately instead of waiting for the 7200s cache target to fill |
| `demuxer-donate-buffer=no` | Stops the demuxer handing used buffers to other threads, which fragments the heap |
| `demuxer-lavf-o=icy=0` | Disables ICY metadata parsing; FMP never reads it |
| `network-timeout` | mpv's own default is 60s, far above every FMP budget. Set deliberately *above* T2 so FMP's budget expires first and the failure comes back as a typed `PlaybackTimeoutException` instead of an mpv message that would have to be guessed at from its text |

The method applies these unconditionally — it carries no platform check. That is
safe only because `audioServiceProvider`
(`lib/services/audio/audio_provider.dart:3267`) hands mobile to
`JustAudioService`, so `MediaKitAudioService` never initializes on Android. The
`Platform.isAndroid || Platform.isIOS` branch at `media_kit_audio_service.dart:150`
is therefore unreachable in production; keep it as a guard, but do not read it as
evidence that this backend is exercised on mobile.

Android `JustAudioService` uses a smaller ExoPlayer load-control profile to
avoid live or muxed high-bitrate streams buffering hundreds of MB: 10s min
buffer, 20s max buffer, 3s back buffer, 2MB `targetBufferBytes` fallback. Do not
restore just_audio's default 50s/50s Android buffers without measuring RSS,
external memory, and stall behavior on Android profile builds.

## Queue, Shuffle, And Mix

- Shuffle is managed in `QueueManager` with `_shuffleOrder`.
- UI must use `upcomingTracks` / provider state instead of calculating next
  track order manually.
- `Settings.rememberPlaybackPosition` defaults to `true`. Saving position is
  always active (every 10s + on seek); *restoring* is what the setting controls
  (app restart + temporary play restore).

YouTube Mix/Radio playlists are dynamic infinite playlists:

- IDs start with `RD`. `AudioController.startMixFromPlaylist()` currently trusts
  stored Mix metadata and does not validate the prefix itself.
- Shuffle is disabled; `addToQueue`, `addAll`, and `addNext` are blocked.
- Loads more tracks near the queue end using
  `AppConstants.mixLoadMoreRemainingThreshold`. If the final queued track
  completes while load-more is pending, completion handling waits for the
  pending load and advances into newly appended tracks.
- Mix state is persisted through `PlayQueue` fields.

## Mute And Seek

- Use `controller.toggleMute()`, not `setVolume(0)` — mute remembers the
  previous volume in `_volumeBeforeMute`.
- Progress slider `onChanged` must not call `seekToProgress()`. Only seek in
  `onChangeEnd`.
- User seeks during a playback request handoff, or during the short
  post-navigation seek stabilization window, must stay in `AudioController` as a
  current-track-checked pending seek. Do not send these seeks directly to the
  backend; stale pending seeks must be discarded when another request supersedes
  the target track.

## Verification

```bash
flutter test test/services/audio
```

If stream resolution, source fallback, or auth headers changed, also run the
relevant tests under `test/data/sources`.

Loading, timeout and recovery behaviour cannot be covered by unit tests alone —
what is under test is how mpv and ExoPlayer react to a sick connection, which
FMP cannot fake and a real CDN will not perform on request. Use the two
deliberately broken servers instead:

```bash
dart run test/manual/pathological_stream_servers.dart
```

`hold` connects and then sends nothing forever; `stall` sends four seconds of
audio and cuts the socket, refusing every reconnect. See `test/manual/README.md`
for the URLs and `docs/review/02-playback-sources.md` §12.14 for the per-platform
baselines a change has to improve on.
