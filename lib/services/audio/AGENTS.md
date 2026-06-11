# lib/services/audio AGENTS.md

Audio-specific guidance for `AudioController`, playback backends, queue, stream
handoff, temporary playback, Mix mode, and network error recovery.

## Architecture

```text
UI playback controls
        |
        v
AudioController (audio_provider.dart)
  - PlayerState
  - business logic
  - temporary/mix/detached playback modes
  - mute memory
  - notification/SMTC coordination
        |                         |
        v                         v
FmpAudioService (abstract)    QueueManager
  |                           - queue order
  |                           - shuffle/loop
  v                           - navigation
JustAudioService (Android)    - persistence hooks
MediaKitAudioService (Desktop)
```

Key rule: UI must call `AudioController` methods, never `FmpAudioService`
directly. This is an architectural convention rather than a compile-time
boundary; use `rg` when reviewing UI playback changes.

Radio is the intentional non-UI exception: `RadioController` uses the shared
backend directly while ownership hooks make `AudioController` ignore radio-owned
backend events.

## Audio Internals Ownership

- `AudioController` (`audio_provider.dart`) owns user-facing state,
  temporary/mix/detached modes, notification/SMTC coordination, queue-visible
  playback decisions, history/lyrics side effects, and source-error UI
  decisions.
- `PlaybackRequestSession` owns playback request tokens, supersession, active
  loading request state, backend stop/handoff, queue restore handoff, fallback
  handoff, and media-open pending recovery.
- `PlaybackRecoveryCoordinator` owns playback network retry generation,
  scheduled retry state, manual retry, network-recovered retry, and premature
  completion recovery.
- `StreamResolutionService` owns stream URL resolution, local-file selection and
  stale download-path cleanup, quality fallback, alternative stream lookup, URL
  expiry persistence, and prefetch dedupe. It asks
  `SourceAuthContext.authForPlay()` for source auth used during stream
  resolution.
- `AudioStreamManager` owns playback selection and prepares
  `PreparedPlaybackMedia` for music playback. It depends on the narrow
  `PlaybackMediaRequestContext` interface for remote-stream handoff before
  producing `RemotePlaybackMedia`. `SourceAuthContext` owns the Auth For Play
  gate; the byte-request URL/header policy is delegated to `MediaHandoff`.
- `PlaybackRequestStreamAccess` is the session-facing interface and should stay
  limited to playback selection, fallback selection, and prefetch. Do not expose
  intermediate stream-resolution or network-handoff phases through that
  interface.
- Music playback opens media through `FmpAudioService.playMedia()` /
  `setMedia()`. Direct `playUrl()` / `setUrl()` remain for radio and
  compatibility-only paths; do not add new music playback callers for raw URL
  methods.
- `QueueManager` owns queue order, shuffle/loop state, navigation, and
  persistence hooks.
- `QueuePersistenceManager` owns persisted queue snapshots, saved
  position/volume, and Mix metadata restore.

## Platform Split

- Android: `JustAudioService` (ExoPlayer via `just_audio`, smaller binary).
- Desktop: `MediaKitAudioService` (libmpv via `media_kit`, supports device
  switching).
- `audioServiceProvider` selects implementation through
  `audioRuntimePlatformProvider`.
- `MediaKit.ensureInitialized()` is called only on desktop platforms.
- Mobile notification state is owned by `AudioController`/`FmpAudioHandler`.
  During controller-owned load phases such as queue next/previous URL
  resolution, backend `idle` events from `FmpAudioService.stop()` must not
  overwrite notification `loading` state or clear the next track media item.

Custom types:
- `audio_types.dart`: backend processing/device types such as
  `FmpAudioProcessingState`, `FmpPlayerState`, `FmpAudioDevice`
- `player_state.dart`: `PlayerState`
- `audio_playback_types.dart`: playback request/mode DTOs

Volume conversion:
- `media_kit`: 0-100
- `just_audio`: 0-1

## Temporary Play

Clicking a song in search/playlist plays temporarily without modifying queue.
After completion, original queue position is restored with a rewind offset.

- Uses `playTemporary()`, not `playTrack()`.
- Saved state in `_PlaybackContext`: `savedQueueIndex`, `savedPosition`,
  `savedWasPlaying`.
- Uses `_executePlayRequest()` with `mode: PlayMode.temporary`.
- Position restore is controlled by `Settings.rememberPlaybackPosition`.

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
session handle/cancellation check. Do not add new raw request-id counters in
`AudioController`.

## Playback Network Error Recovery

`AudioController` owns recovery for `FmpAudioService.errorStream` playback
failures.

- Runtime backend network errors, including media_kit `tcp:` / `ffurl_read`
  errors, must retry or refetch the current track URL from the saved position,
  not advance the queue.
- Runtime backend media-open errors such as media_kit `Failed to open https://`
  must not be silently ignored. Delay briefly to allow backend self-recovery;
  if playback does not advance, stop and surface a playback error to the user.
- Backend error-stream retry suppression must be generation/current-track aware.
  A fresh backend network error during manual or automatic retry handoff
  schedules a new retry generation; stale handoff completion must not clear the
  fresh retry state.
- `completedStream` is not always natural song completion. media_kit can emit
  completed around stream read failures or network transitions such as VPN
  changes. Ignore completion while loading/retrying/network-error state. If
  completion arrives while current position is not close to duration, schedule
  retry for the current track from the saved position.
- Only source availability failures marked with
  `SourceErrorKind.shouldSkipTrack` should auto-skip to the next queue item.
- Playback-visible stream metadata (`currentBitrate`, `currentContainer`,
  `currentCodec`, `currentStreamType`, duration, buffered position) belongs to
  the active playback request. Entering a controller-owned load or clearing the
  playing track must clear stale values first; successful playback then replaces
  them from that request's `AudioStreamResult`.
- Detail providers must clear stale `VideoDetail` when the current track
  changes so the detail panel never shows metadata from the previous successful
  song during loading or failure.
- On resume after long pause, refresh expired audio URLs before playing and seek
  back to the prior position when appropriate.

Desktop `MediaKitAudioService` intentionally uses an aggressive network buffer
profile for online music playback:
- 32MB player buffer
- 24MB demuxer forward buffer
- 8MB demuxer back buffer
- 7200s mpv cache/readahead
- FFmpeg/lavf reconnect options (`reconnect=1`,
  `reconnect_streamed=1`, `reconnect_on_network_error=1`,
  `reconnect_delay_max=2`, `reconnect_max_retries=3`)

Keep `vid=no` and `sid=no` enabled so muxed fallback streams do not decode video
while the larger buffer absorbs VPN/CDN stalls.

Android `JustAudioService` intentionally uses a smaller ExoPlayer load-control
profile to avoid live or muxed high-bitrate streams buffering hundreds of MB:
- 10s min buffer
- 20s max buffer
- 3s back buffer
- 2MB `targetBufferBytes` fallback

Do not restore just_audio's default 50s/50s Android buffers without measuring
RSS/external memory and stall behavior on Android profile builds.

Fire-and-forget backend cleanup futures must catch and log errors. Provider
dispose can cancel controller subscriptions synchronously, but async
`FmpAudioService.dispose()` failures must not become unhandled async errors.

## Queue, Shuffle, And Mix

- Shuffle is managed in `QueueManager` with `_shuffleOrder`.
- UI must use `upcomingTracks` / provider state instead of calculating next
  track order manually.
- `Settings.rememberPlaybackPosition` defaults to `true`.
- Saving playback position is always active (every 10s + on seek).
- Restoring playback position is controlled by the setting (app restart +
  temporary play restore).

YouTube Mix/Radio playlists are dynamic infinite playlists:
- IDs start with `RD`; `AudioController.startMixFromPlaylist()` currently trusts
  stored Mix metadata and does not validate the prefix itself.
- Shuffle is disabled.
- `addToQueue`, `addAll`, and `addNext` are blocked in Mix mode.
- Loads more tracks near queue end using
  `AppConstants.mixLoadMoreRemainingThreshold`.
- If the final queued track completes while Mix load-more is pending, completion
  handling waits for the pending load and advances into newly appended tracks.
- Mix state is persisted through `PlayQueue` fields.

## Mute And Progress

- Use `controller.toggleMute()`, not `setVolume(0)`. Mute remembers previous
  volume in `_volumeBeforeMute`.
- Progress slider `onChanged` must not call `seekToProgress()`. Only call seek
  in `onChangeEnd`.
- User seeks during a playback request handoff, or during the short
  post-navigation seek stabilization window, must stay in `AudioController` as a
  current-track-checked pending seek. Do not send these seeks directly to the
  backend; stale pending seeks must be discarded when another request supersedes
  the target track.

## Verification

For audio changes, start with:

```bash
flutter test test/services/audio
```

If stream resolution, source fallback, or auth headers changed, also run the
relevant source tests under `test/data/sources`.
