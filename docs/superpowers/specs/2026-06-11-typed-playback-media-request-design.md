# Typed Playback Media Request Design

Date: 2026-06-11
Status: Approved design, pending implementation

## Summary

Deepen the music playback handoff from raw `url + headers` into a typed
playback media module. The goal is to keep Media Request Credentials hidden
behind a small interface after `SourceAuthContext` and `MediaHandoff` prepare
them.

This refactor applies to the music playback path owned by `AudioController`,
`AudioStreamManager`, and `PlaybackRequestSession`. Radio remains out of scope
because it is an intentional exception that directly owns the shared backend for
Bilibili live playback.

## Goals

- Add one typed module for prepared music playback media.
- Stop music playback orchestration from passing raw media headers through
  `PlaybackSelection` and `PlaybackRequestSession`.
- Keep `SourceAuthContext.playbackNetworkRequest()` as the Auth For Play and
  Media Handoff entry for playback byte requests.
- Let audio backend adapters open one typed media value.
- Preserve current local-file playback, remote stream playback, fallback,
  queue restore, retry, and attempted-URL behavior.
- Keep direct `playUrl()` / `setUrl()` available for radio and compatibility
  during this refactor.

## Non-Goals

- Do not refactor radio playback in this change.
- Do not change Media Request Credentials policy, Netease allowlist behavior,
  Source Auth Context gates, or Media Handoff redirect behavior.
- Do not change stream resolution, quality fallback, retry classification, or
  queue semantics.
- Do not remove `FmpAudioService.playUrl()` / `setUrl()` yet.
- Do not alter user-visible playback behavior.

## Existing Friction

The Media Handoff module is now deep, but the music playback backend seam still
exposes byte-request details:

- `FmpAudioService.playUrl()` / `setUrl()` take raw `String url` and optional
  headers.
- `PlaybackSelection` carries `url`, `localPath`, and `headers`.
- Queue restore manually calls `prepareNetworkPlayback()` and passes headers to
  `setUrl()`.
- Playback session tests assert raw headers even though header policy should be
  tested at `SourceAuthContext` / `MediaHandoff`.

Deleting the current raw-header plumbing would push complexity back into the
same callers. A typed playback media module should concentrate the distinction
between local files and remote streams at one seam.

## Chosen Approach

Add `PreparedPlaybackMedia` in `lib/services/audio/playback_media.dart`.

The interface is a sealed type:

```dart
sealed class PreparedPlaybackMedia {
  Track get track;
  String get debugUrl;
}

final class LocalPlaybackMedia extends PreparedPlaybackMedia {
  const LocalPlaybackMedia({
    required this.path,
    required this.track,
  });

  final String path;

  @override
  final Track track;

  @override
  String get debugUrl => path;
}

final class RemotePlaybackMedia extends PreparedPlaybackMedia {
  const RemotePlaybackMedia({
    required this.url,
    required this.headers,
    required this.track,
  });

  final Uri url;
  final Map<String, String>? headers;

  @override
  final Track track;

  @override
  String get debugUrl => url.toString();
}
```

`debugUrl` preserves logging, fallback, recovery, and
`PlaybackSessionResult.attemptedUrl` without making request orchestration know
how to open local or remote media.

`PlaybackSelection` shrinks to:

```dart
class PlaybackSelection {
  const PlaybackSelection({
    required this.media,
    required this.streamResult,
  });

  final PreparedPlaybackMedia media;
  final AudioStreamResult? streamResult;
}
```

`FmpAudioService` gains typed methods:

```dart
Future<Duration?> playMedia(PreparedPlaybackMedia media);
Future<Duration?> setMedia(PreparedPlaybackMedia media);
```

Backend adapters dispatch internally:

- `LocalPlaybackMedia` -> existing local-file load behavior.
- `RemotePlaybackMedia` -> existing URL load behavior with headers.

Existing `playUrl()` / `setUrl()` remain for radio and compatibility. Music
playback code should stop calling them directly.

## Data Flow

### Normal Playback

1. `PlaybackRequestSession.start()` calls
   `AudioStreamManager.selectPlayback(track)`.
2. `AudioStreamManager` calls `StreamResolutionService.resolvePrimary()`.
3. Local resolution becomes `LocalPlaybackMedia`.
4. Remote resolution calls `SourceAuthContext.playbackNetworkRequest()` and
   becomes `RemotePlaybackMedia`.
5. `PlaybackRequestSession` calls
   `FmpAudioService.playMedia(selection.media)`.
6. The platform backend adapter opens the typed media.

### Queue Restore

1. `PlaybackRequestSession.restore()` asks the stream manager for prepared
   media.
2. It calls `FmpAudioService.setMedia(media)`.
3. It seeks and resumes as it does today.

Queue restore should no longer manually prepare network playback or pass raw
headers.

### Fallback

If opening media fails:

1. `PlaybackRequestSession` calls
   `selectFallbackPlayback(track, failedUrl: media.debugUrl)`.
2. The fallback selection returns another `PreparedPlaybackMedia`.
3. `playMedia()` opens that typed media.
4. `PlaybackSessionResult.attemptedUrl` uses `media.debugUrl`.

## Error Behavior

- Source adapter errors remain source errors.
- Stream resolution fallback remains in `StreamResolutionService`.
- Media open errors remain owned by `PlaybackRequestSession`.
- Runtime retry classification remains in `PlaybackRecoveryCoordinator` and
  `AudioController`.
- Media Request Credentials are still created by `MediaHandoff` through
  `SourceAuthContext`; the typed media module only prevents those credentials
  from leaking through orchestration.

## Test Plan

Add or update focused tests before production changes:

- `test/services/audio/audio_stream_manager_test.dart`
  - `selectPlayback()` returns `LocalPlaybackMedia` for local files.
  - `selectPlayback()` returns `RemotePlaybackMedia` for remote streams.
  - `selectFallbackPlayback()` returns remote typed media and preserves failed
    URL behavior.
- `test/services/audio/playback_request_session_test.dart`
  - `start()` calls `playMedia()`.
  - fallback passes `failedUrl: media.debugUrl`.
  - queue restore calls `setMedia()` and does not manually call
    `prepareNetworkPlayback()`.
- `test/support/fakes/fake_audio_service.dart`
  - record `playMediaCalls` and `setMediaCalls`.
  - keep existing `playUrlCalls` and `setUrlCalls` for radio and compatibility
    tests.
- Backend adapter coverage
  - remote typed media maps to existing URL loading with headers.
  - local typed media maps to existing file loading.
- Static structure coverage
  - music playback modules no longer call `playUrl()` / `setUrl()` directly.
  - radio direct `playUrl()` remains allowed.

Minimum verification:

```bash
flutter test test/services/audio/audio_stream_manager_test.dart test/services/audio/playback_request_session_test.dart
flutter test test/services/audio
flutter analyze
```

## Documentation Updates

After implementation, update `lib/services/audio/AGENTS.md`:

- Music playback opens `PreparedPlaybackMedia` through `FmpAudioService`.
- `AudioStreamManager` owns preparing local or remote playback media.
- `PlaybackRequestSession` owns request ordering and backend handoff, not raw
  media headers.
- `playUrl()` / `setUrl()` are retained for radio and compatibility-only use.

## Implementation Notes

- Use TDD for each behavior change.
- Keep the first pass behavior-preserving.
- Do not refactor radio in the same change.
- Prefer small compatibility steps over deleting `playUrl()` / `setUrl()`
  immediately.
- Keep comments that explain backend-specific non-obvious playback behavior.
