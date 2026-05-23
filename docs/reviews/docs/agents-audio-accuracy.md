# AGENTS.md Audio Accuracy Review

Date: 2026-05-21

Scope reviewed: `AGENTS.md` audio-related claims for Audio System, Playback Network Error Recovery, Temporary Play, Queue/Shuffle, Mix Mode, and Radio ownership where it intersects shared audio services. `AGENTS.md` was treated as claims to verify, not as ground truth.

## Summary

No clearly outdated or directly contradicted claims were found in the reviewed scope. The main audio architecture claims match the current implementation: `AudioController` coordinates queue playback, platform-specific `FmpAudioService` implementations are selected by runtime platform, temporary play restores queue state through request-locked playback paths, network errors are retried from the current track/position, and Mix mode blocks queue mutations while persisting Mix metadata.

The docs are thinner than the implementation in a few places: radio directly shares the same `FmpAudioService`, paused/resumed expired URLs are refreshed before playback, Mix load-more currently triggers at the last track rather than "near" the end, and "shuffle" means both playback shuffle mode and destructive queue shuffle depending on UI entry point.

## Confirmed Accurate Claims

### [accurate] Audio System: platform split and service selection

AGENTS.md paragraph: `C:/Users/Roxy/Documents/VSCode/FMP/AGENTS.md:54-91`

Evidence:
- `C:/Users/Roxy/Documents/VSCode/FMP/lib/services/audio/audio_provider.dart:2913-2922` selects `JustAudioService` for `AudioRuntimePlatform.mobile` and `MediaKitAudioService` otherwise.
- `C:/Users/Roxy/Documents/VSCode/FMP/lib/services/audio/audio_runtime_platform.dart:7-18` maps Android/iOS to mobile and Windows/Linux/macOS to desktop.
- `C:/Users/Roxy/Documents/VSCode/FMP/lib/main.dart:113-116` calls `MediaKit.ensureInitialized()` only on desktop platforms.
- `C:/Users/Roxy/Documents/VSCode/FMP/lib/services/audio/just_audio_service.dart:13-15` identifies the Android `just_audio`/ExoPlayer implementation and the memory saving claim.
- `C:/Users/Roxy/Documents/VSCode/FMP/lib/services/audio/media_kit_audio_service.dart:14-18` identifies the Windows/Linux `media_kit` implementation.

### [accurate] Audio System: notification loading state is protected during controller-owned loads

AGENTS.md paragraph: `C:/Users/Roxy/Documents/VSCode/FMP/AGENTS.md:91`

Evidence:
- `C:/Users/Roxy/Documents/VSCode/FMP/lib/services/audio/audio_provider.dart:1755-1767` enters loading state, clears stale position/duration/stream metadata, increments the play request id, and publishes mobile loading state.
- `C:/Users/Roxy/Documents/VSCode/FMP/lib/services/audio/audio_provider.dart:1770-1792` publishes mobile `FmpAudioHandler` playback state from `AudioController`.
- `C:/Users/Roxy/Documents/VSCode/FMP/lib/services/audio/audio_provider.dart:2582-2609` maps backend `idle` events during controller loading to effective `loading`, preventing old backend idle from overriding controller-owned loading state.

### [accurate] Temporary Play: temporary playback preserves and restores queue context

AGENTS.md paragraph: `C:/Users/Roxy/Documents/VSCode/FMP/AGENTS.md:300-306`

Evidence:
- `C:/Users/Roxy/Documents/VSCode/FMP/lib/services/audio/audio_provider.dart:656-693` implements `playTemporary()` with `PlayMode.temporary`, `persist: false`, and no prefetch.
- `C:/Users/Roxy/Documents/VSCode/FMP/lib/services/audio/audio_provider.dart:664-679` saves queue index, position, and playing state into `_context`.
- `C:/Users/Roxy/Documents/VSCode/FMP/lib/services/audio/audio_provider.dart:832-849` reads restore settings and restores queue playback.
- `C:/Users/Roxy/Documents/VSCode/FMP/lib/services/audio/temporary_play_handler.dart:76-92` applies `rememberPlaybackPosition`; when enabled it uses the configured rewind seconds.
- `C:/Users/Roxy/Documents/VSCode/FMP/lib/data/models/settings.dart:100-107` defaults `rememberPlaybackPosition = true` and `tempPlayRewindSeconds = 10`.

### [accurate] Playback Network Error Recovery: controller owns retry/recovery from backend errors

AGENTS.md paragraph: `C:/Users/Roxy/Documents/VSCode/FMP/AGENTS.md:328-336`

Evidence:
- `C:/Users/Roxy/Documents/VSCode/FMP/lib/services/audio/audio_provider.dart:399-407` subscribes to `completedStream` and `errorStream`.
- `C:/Users/Roxy/Documents/VSCode/FMP/lib/services/audio/audio_provider.dart:2119-2138` classifies network-like errors, including `tcp:` and `ffurl_read`.
- `C:/Users/Roxy/Documents/VSCode/FMP/lib/services/audio/audio_provider.dart:2662-2715` handles `AudioService.errorStream` network errors by stopping playback and scheduling retry for the same track and saved position.
- `C:/Users/Roxy/Documents/VSCode/FMP/lib/services/audio/audio_provider.dart:2141-2186` stores retry generation, track key, and recovery position before scheduling retry.
- `C:/Users/Roxy/Documents/VSCode/FMP/lib/services/audio/audio_provider.dart:2199-2204` and `C:/Users/Roxy/Documents/VSCode/FMP/lib/services/audio/audio_provider.dart:2683-2689` suppress only duplicate retrying errors for the same generation/track.
- `C:/Users/Roxy/Documents/VSCode/FMP/lib/services/audio/audio_provider.dart:2718-2753` ignores completion during loading/retry/network-error state and retries premature completion from the current position.
- `C:/Users/Roxy/Documents/VSCode/FMP/lib/services/audio/audio_provider.dart:2024-2055` skips to the next queue item only for `_shouldSkipSourceError`.
- `C:/Users/Roxy/Documents/VSCode/FMP/lib/services/audio/audio_provider.dart:2113-2117` maps retry/skip decisions to `SourceErrorKind`.

### [accurate] Playback Network Error Recovery: desktop media_kit uses aggressive audio-only buffering

AGENTS.md paragraph: `C:/Users/Roxy/Documents/VSCode/FMP/AGENTS.md:334`

Evidence:
- `C:/Users/Roxy/Documents/VSCode/FMP/lib/services/audio/media_kit_audio_service.dart:19-26` defines 32MB player buffer, 24MB demuxer forward buffer, 8MB back buffer, and 7200 second buffer horizon.
- `C:/Users/Roxy/Documents/VSCode/FMP/lib/services/audio/media_kit_audio_service.dart:248-291` sets `vid=no`, `sid=no`, demuxer buffer limits, readahead, `cache=yes`, and `cache-secs`.

### [accurate] Playback Network Error Recovery: stale stream metadata and detail data are cleared on new loads

AGENTS.md paragraph: `C:/Users/Roxy/Documents/VSCode/FMP/AGENTS.md:336`

Evidence:
- `C:/Users/Roxy/Documents/VSCode/FMP/lib/services/audio/audio_provider.dart:1755-1763` clears position, buffered position, duration, error, and current stream metadata on load entry.
- `C:/Users/Roxy/Documents/VSCode/FMP/lib/services/audio/audio_provider.dart:1816-1825` replaces current stream metadata only from the successful active request.
- `C:/Users/Roxy/Documents/VSCode/FMP/lib/services/audio/player_state.dart:206-217` implements replacement semantics for bitrate/container/codec/stream type.
- `C:/Users/Roxy/Documents/VSCode/FMP/lib/providers/track_detail_provider.dart:71-76` clears detail state when loading a different track.
- `C:/Users/Roxy/Documents/VSCode/FMP/lib/providers/track_detail_provider.dart:204-208` reloads details when `currentTrackProvider` changes.

### [accurate] Queue/Shuffle: playback shuffle and upcoming tracks are owned by QueueManager/AudioController state

AGENTS.md paragraph: `C:/Users/Roxy/Documents/VSCode/FMP/AGENTS.md:349-350`

Evidence:
- `C:/Users/Roxy/Documents/VSCode/FMP/lib/services/audio/queue_manager.dart:31-33` stores playback shuffle order and current shuffle index.
- `C:/Users/Roxy/Documents/VSCode/FMP/lib/services/audio/queue_manager.dart:91-137` computes upcoming tracks using shuffle order and loop mode.
- `C:/Users/Roxy/Documents/VSCode/FMP/lib/services/audio/audio_provider.dart:2855-2888` gets `upcomingTracks` and navigation availability from `QueueManager`.
- `C:/Users/Roxy/Documents/VSCode/FMP/lib/ui/pages/home/home_page.dart:1553-1557` uses `upcomingTracks` for the home queue preview.
- `C:/Users/Roxy/Documents/VSCode/FMP/lib/ui/widgets/player/mini_player.dart:329` and `C:/Users/Roxy/Documents/VSCode/FMP/lib/ui/widgets/player/mini_player.dart:398-403` use controller-provided `canPlayNext` and `controller.next()` rather than calculating the next item in UI.

### [accurate] Mix Mode: blocks shuffle/add operations, loads more, and persists state

AGENTS.md paragraph: `C:/Users/Roxy/Documents/VSCode/FMP/AGENTS.md:352-356`

Evidence:
- `C:/Users/Roxy/Documents/VSCode/FMP/lib/services/audio/audio_provider.dart:942-1011` starts Mix playback with `PlayMode.mix`, clears the old queue, turns shuffle off, seeds Mix state, and persists Mix metadata.
- `C:/Users/Roxy/Documents/VSCode/FMP/lib/services/audio/audio_provider.dart:1129-1133`, `C:/Users/Roxy/Documents/VSCode/FMP/lib/services/audio/audio_provider.dart:1158-1162`, and `C:/Users/Roxy/Documents/VSCode/FMP/lib/services/audio/audio_provider.dart:1182-1186` block add-to-queue, add-all, and add-next in Mix mode.
- `C:/Users/Roxy/Documents/VSCode/FMP/lib/services/audio/audio_provider.dart:1281-1284` blocks shuffle toggle in Mix mode.
- `C:/Users/Roxy/Documents/VSCode/FMP/lib/services/audio/audio_provider.dart:1408-1413` triggers Mix load-more at the queue end.
- `C:/Users/Roxy/Documents/VSCode/FMP/lib/services/audio/audio_provider.dart:1615-1734` loads and deduplicates additional Mix tracks.
- `C:/Users/Roxy/Documents/VSCode/FMP/lib/services/audio/queue_persistence_manager.dart:114-127` persists `isMixMode`, playlist id, seed video id, and title.
- `C:/Users/Roxy/Documents/VSCode/FMP/lib/services/audio/audio_provider.dart:430-467` restores persisted Mix mode on startup.

### [accurate] Radio Ownership: retained station context differs from active shared-player ownership

AGENTS.md paragraph: `C:/Users/Roxy/Documents/VSCode/FMP/AGENTS.md:338-344`

Evidence:
- `C:/Users/Roxy/Documents/VSCode/FMP/lib/services/radio/radio_controller.dart:128-147` implements `hasCurrentStation`, `hasActivePlaybackOwnership`, and resumable context.
- `C:/Users/Roxy/Documents/VSCode/FMP/lib/services/radio/radio_controller.dart:1134-1137` exposes `isRadioPlayingProvider` from active ownership.
- `C:/Users/Roxy/Documents/VSCode/FMP/lib/services/radio/radio_controller.dart:394-405` wires `AudioController.onPlaybackStarting` and `AudioController.isRadioPlaying` to radio ownership.
- `C:/Users/Roxy/Documents/VSCode/FMP/lib/services/radio/radio_controller.dart:434-441` pauses music before setting radio loading state.
- `C:/Users/Roxy/Documents/VSCode/FMP/lib/ui/pages/home/home_page.dart:1448-1475` uses retained radio context for Now Playing tap actions.

## Missing Important Behaviors

### [missing] Audio System/Radio Ownership: RadioController directly shares the same FmpAudioService

AGENTS.md paragraph: `C:/Users/Roxy/Documents/VSCode/FMP/AGENTS.md:54-91` and `C:/Users/Roxy/Documents/VSCode/FMP/AGENTS.md:338-344`

The Audio System diagram shows `AudioController` as the coordinator over `AudioService`, while the radio section describes ownership conceptually. The current implementation also has `RadioController` consume the same `audioServiceProvider` and call `_audioService.playUrl()` directly while using ownership hooks to keep `AudioController` from reacting to radio playback events. This is not a code bug by itself, but the docs should make the shared-player exception explicit.

Evidence:
- `C:/Users/Roxy/Documents/VSCode/FMP/lib/services/radio/radio_controller.dart:1120-1131` injects `audioServiceProvider` into `RadioController`.
- `C:/Users/Roxy/Documents/VSCode/FMP/lib/services/radio/radio_controller.dart:484-489` plays the radio stream via `_audioService.playUrl`.
- `C:/Users/Roxy/Documents/VSCode/FMP/lib/services/audio/audio_provider.dart:2577-2581`, `C:/Users/Roxy/Documents/VSCode/FMP/lib/services/audio/audio_provider.dart:2662-2667`, and `C:/Users/Roxy/Documents/VSCode/FMP/lib/services/audio/audio_provider.dart:2787-2795` show `AudioController` ignoring shared-player events while radio has active ownership.

### [missing] Playback Network Error Recovery: expired URL resume path is separate from backend error retry

AGENTS.md paragraph: `C:/Users/Roxy/Documents/VSCode/FMP/AGENTS.md:328-336`

The docs cover backend runtime errors and premature completion, but the implementation also refreshes an expired audio URL when the user resumes after a long pause, then seeks back to the prior position. This is important because it prevents a manual resume from becoming a backend decode error.

Evidence:
- `C:/Users/Roxy/Documents/VSCode/FMP/lib/services/audio/audio_provider.dart:531-535` calls `_resumeWithFreshUrlIfNeeded()` before `play()`.
- `C:/Users/Roxy/Documents/VSCode/FMP/lib/services/audio/audio_provider.dart:569-571` does the same before toggling from paused to playing.
- `C:/Users/Roxy/Documents/VSCode/FMP/lib/services/audio/audio_provider.dart:2460-2495` checks URL expiry, excludes local files, refetches through `_playTrack()`, and seeks back to the previous position.

## Unclear Items Needing Human Decision

### [unclear] Mix Mode: "near queue end" currently means the last queue item

AGENTS.md paragraph: `C:/Users/Roxy/Documents/VSCode/FMP/AGENTS.md:352-356`

The doc says Mix mode "Auto-loads more tracks near queue end." Code triggers load-more only when `currentIndex == tracks.length - 1`. If "near" is intentional prefetch language, code is more conservative than the doc. If the current behavior is intended, the doc should say "when playback reaches the last track."

Evidence:
- `C:/Users/Roxy/Documents/VSCode/FMP/lib/services/audio/audio_provider.dart:1408-1413` checks for exactly the last queue item before loading more.
- `C:/Users/Roxy/Documents/VSCode/FMP/lib/services/audio/audio_provider.dart:1615-1734` performs the load-more work once triggered.

### [unclear] Queue/Shuffle: docs do not distinguish playback shuffle mode from destructive queue shuffle

AGENTS.md paragraph: `C:/Users/Roxy/Documents/VSCode/FMP/AGENTS.md:349-350`

The "Shuffle Mode" paragraph accurately describes playback shuffle mode backed by `_shuffleOrder`, but the app also has a queue-page shuffle action that destructively shuffles `_tracks` and resets the current item to index 0. The docs should distinguish these two controls because they have different persistence and user-visible behavior.

Evidence:
- `C:/Users/Roxy/Documents/VSCode/FMP/lib/services/audio/queue_manager.dart:667-700` implements playback shuffle mode through `_shuffleOrder`.
- `C:/Users/Roxy/Documents/VSCode/FMP/lib/services/audio/queue_manager.dart:595-618` implements destructive queue shuffling by mutating `_tracks`.
- `C:/Users/Roxy/Documents/VSCode/FMP/lib/ui/pages/queue/queue_page.dart:301-307` exposes the destructive shuffle action from the queue page.

### [unclear] Mix Mode: RD-prefix source invariant is documented but not enforced at startMixFromPlaylist

AGENTS.md paragraph: `C:/Users/Roxy/Documents/VSCode/FMP/AGENTS.md:352-353`

The doc states YouTube Mix/Radio playlists have IDs starting with `RD`. `startMixFromPlaylist()` currently trusts `mixPlaylistId` and `mixSeedVideoId` metadata and only checks for null values. This may be fine if import/storage guarantees the invariant elsewhere, but the audio docs should say whether `AudioController` is expected to validate the RD prefix.

Evidence:
- `C:/Users/Roxy/Documents/VSCode/FMP/lib/services/audio/audio_provider.dart:913-940` checks only that Mix playlist id and seed video id are present before fetching tracks.
- `C:/Users/Roxy/Documents/VSCode/FMP/lib/services/audio/audio_provider.dart:942-1011` starts Mix playback without validating the playlist id prefix.

## Outdated Or Contradicted Claims

No outdated or directly contradicted claims were found in the reviewed sections.

## Expected Architecture Rules Not Currently Followed

No production UI-to-`FmpAudioService` violations were found in the reviewed audio player UI surface. Reviewed UI controls call `AudioController` or `RadioController`; the direct shared-service use outside `AudioController` is `RadioController`, which appears intentional and is covered by active radio ownership.

Evidence:
- `C:/Users/Roxy/Documents/VSCode/FMP/lib/ui/widgets/player/mini_player.dart:331-347` reads `AudioController` and calls controller methods for playback mode controls.
- `C:/Users/Roxy/Documents/VSCode/FMP/lib/ui/widgets/player/mini_player.dart:398-403` calls `controller.next()`.
- `C:/Users/Roxy/Documents/VSCode/FMP/lib/services/radio/radio_controller.dart:1120-1131` is the intentional non-UI direct consumer of `audioServiceProvider`.
