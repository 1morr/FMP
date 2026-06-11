# Typed Playback Media Request Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace music playback's raw `url + headers` handoff with typed prepared playback media while preserving current playback behavior.

**Architecture:** Add `PreparedPlaybackMedia` as the music playback seam. `AudioStreamManager` prepares local or remote media, `PlaybackRequestSession` opens typed media through `FmpAudioService`, and platform backend adapters internally dispatch typed media to the existing URL/file loaders. Radio remains on direct `playUrl()` / `setUrl()` and is not refactored in this plan.

**Tech Stack:** Flutter/Dart, Riverpod-adjacent audio services, `flutter_test`, existing `SourceAuthContext`, `MediaHandoff`, and audio backend adapters.

---

## Repository Rules

- Do not commit, amend, rebase, or push unless explicitly requested.
- Use TDD: write a failing test, run it red, then implement minimal production code.
- Preserve radio direct backend usage.
- Preserve existing backend comments that explain non-obvious playback behavior.
- Preserve unrelated working-tree changes.

## File Structure

- Create `lib/services/audio/playback_media.dart`
  - Owns `PreparedPlaybackMedia`, `LocalPlaybackMedia`, and `RemotePlaybackMedia`.
- Create `test/services/audio/playback_media_test.dart`
  - Tests typed media value behavior and `debugUrl`.
- Modify `lib/services/audio/audio_service.dart`
  - Adds `playMedia()` and `setMedia()` to the backend interface.
  - Keeps `playUrl()` / `setUrl()` for radio and compatibility.
- Modify `test/support/fakes/fake_audio_service.dart`
  - Records typed media calls.
  - Delegates typed media to existing fake URL/file loaders so broad controller tests keep their existing observable call lists.
- Modify `lib/services/audio/just_audio_service.dart`
  - Adds typed media dispatch to existing `playUrl()` / `playFile()` and `setUrl()` / `setFile()`.
- Modify `lib/services/audio/media_kit_audio_service.dart`
  - Adds typed media dispatch to existing URL/file loaders.
- Modify `lib/services/audio/audio_stream_manager.dart`
  - Changes `PlaybackSelection` to carry `PreparedPlaybackMedia`.
  - Changes `prepareNetworkPlayback()` to return `RemotePlaybackMedia`.
  - Removes `getPlaybackHeaders()` from the playback request interface.
- Modify `lib/services/audio/playback_request_session.dart`
  - Uses `playMedia()` / `setMedia()` and `media.debugUrl`.
  - Stops calling `playUrl()` / `setUrl()` directly in music playback.
- Modify `test/services/audio/audio_stream_manager_test.dart`
  - Tests local and remote typed media selection.
  - Replaces direct header tests with remote media tests.
- Modify `test/services/audio/playback_request_session_test.dart`
  - Updates fake stream access and session expectations to typed media.
  - Adds static structure test for no direct `playUrl()` / `setUrl()` in session.
- Modify `lib/services/audio/AGENTS.md`
  - Documents the typed music playback media seam and radio exception.

## Task 1: Add Prepared Playback Media Value Types

**Files:**
- Create: `test/services/audio/playback_media_test.dart`
- Create: `lib/services/audio/playback_media.dart`

- [ ] **Step 1: Write the failing value tests**

Create `test/services/audio/playback_media_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/models/track.dart';
import 'package:fmp/services/audio/playback_media.dart';

void main() {
  group('PreparedPlaybackMedia', () {
    test('local media exposes track and debug path', () {
      final track = _track('local');

      final media = LocalPlaybackMedia(
        path: '/music/local.m4a',
        track: track,
      );

      expect(media.track, same(track));
      expect(media.path, '/music/local.m4a');
      expect(media.debugUrl, '/music/local.m4a');
    });

    test('remote media exposes track headers and debug URL', () {
      final track = _track('remote');

      final media = RemotePlaybackMedia(
        url: Uri.parse('https://cdn.example.com/remote.m4a'),
        headers: const {'X-Test': 'yes'},
        track: track,
      );

      expect(media.track, same(track));
      expect(media.url.toString(), 'https://cdn.example.com/remote.m4a');
      expect(media.headers, {'X-Test': 'yes'});
      expect(media.debugUrl, 'https://cdn.example.com/remote.m4a');
    });
  });
}

Track _track(String sourceId) {
  return Track()
    ..sourceId = sourceId
    ..sourceType = SourceType.youtube
    ..title = 'Track $sourceId'
    ..artist = 'Tester';
}
```

- [ ] **Step 2: Run the test and verify RED**

Run:

```bash
flutter test test/services/audio/playback_media_test.dart
```

Expected: FAIL with an import error because `package:fmp/services/audio/playback_media.dart` does not exist.

- [ ] **Step 3: Create the typed media module**

Create `lib/services/audio/playback_media.dart`:

```dart
import '../../data/models/track.dart';

sealed class PreparedPlaybackMedia {
  const PreparedPlaybackMedia();

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

- [ ] **Step 4: Run the test and verify GREEN**

Run:

```bash
flutter test test/services/audio/playback_media_test.dart
```

Expected: PASS.

## Task 2: Add Typed Backend Interface And Fake Support

**Files:**
- Modify: `lib/services/audio/audio_service.dart`
- Modify: `test/support/fakes/fake_audio_service.dart`
- Test: `test/services/audio/playback_request_session_test.dart`

- [ ] **Step 1: Write the failing fake support test**

In `test/services/audio/playback_request_session_test.dart`, add this import:

```dart
import 'package:fmp/services/audio/playback_media.dart';
```

Add this group after the `PlaybackSessionCommand` group setup or before the session behavior tests:

```dart
  group('FakeAudioService typed media support', () {
    test('playMedia records typed remote media and delegates to URL loader',
        () async {
      final audioService = FakeAudioService();
      final track = _track('typed-remote');
      final media = RemotePlaybackMedia(
        url: Uri.parse('https://example.com/typed-remote.m4a'),
        headers: const {'X-Typed': 'remote'},
        track: track,
      );

      await audioService.playMedia(media);

      expect(audioService.playMediaCalls.single.media, same(media));
      expect(audioService.playUrlCalls.single.url,
          'https://example.com/typed-remote.m4a');
      expect(audioService.playUrlCalls.single.headers, {'X-Typed': 'remote'});
      expect(audioService.playUrlCalls.single.track, same(track));
    });

    test('setMedia records typed local media and delegates to file loader',
        () async {
      final audioService = FakeAudioService();
      final track = _track('typed-local');
      final media = LocalPlaybackMedia(
        path: '/music/typed-local.m4a',
        track: track,
      );

      await audioService.setMedia(media);

      expect(audioService.setMediaCalls.single.media, same(media));
      expect(audioService.setFileCalls.single.filePath,
          '/music/typed-local.m4a');
      expect(audioService.setFileCalls.single.track, same(track));
    });
  });
```

- [ ] **Step 2: Run the test and verify RED**

Run:

```bash
flutter test test/services/audio/playback_request_session_test.dart
```

Expected: FAIL because `FakeAudioService` and `FmpAudioService` do not expose `playMedia()` / `setMedia()`.

- [ ] **Step 3: Add typed methods to the backend interface**

In `lib/services/audio/audio_service.dart`, add the import:

```dart
import 'playback_media.dart';
```

Then add these methods above the existing URL/file source methods:

```dart
  Future<Duration?> playMedia(PreparedPlaybackMedia media);
  Future<Duration?> setMedia(PreparedPlaybackMedia media);
```

Keep the existing methods:

```dart
  Future<Duration?> playUrl(String url,
      {Map<String, String>? headers, Track? track});
  Future<Duration?> setUrl(String url,
      {Map<String, String>? headers, Track? track});
  Future<Duration?> playFile(String filePath, {Track? track});
  Future<Duration?> setFile(String filePath, {Track? track});
```

- [ ] **Step 4: Add typed call recording to the fake**

In `test/support/fakes/fake_audio_service.dart`, add:

```dart
import 'package:fmp/services/audio/playback_media.dart';
```

Add this call record type after `AudioFileCall`:

```dart
class AudioMediaCall {
  AudioMediaCall({required this.media});

  final PreparedPlaybackMedia media;
}
```

Add these fields near the existing call lists:

```dart
  final List<AudioMediaCall> playMediaCalls = [];
  final List<AudioMediaCall> setMediaCalls = [];
```

Add these methods before `playUrl()`:

```dart
  @override
  Future<Duration?> playMedia(PreparedPlaybackMedia media) {
    playMediaCalls.add(AudioMediaCall(media: media));
    return switch (media) {
      LocalPlaybackMedia(:final path, :final track) =>
        playFile(path, track: track),
      RemotePlaybackMedia(:final url, :final headers, :final track) =>
        playUrl(url.toString(), headers: headers, track: track),
    };
  }

  @override
  Future<Duration?> setMedia(PreparedPlaybackMedia media) {
    setMediaCalls.add(AudioMediaCall(media: media));
    return switch (media) {
      LocalPlaybackMedia(:final path, :final track) =>
        setFile(path, track: track),
      RemotePlaybackMedia(:final url, :final headers, :final track) =>
        setUrl(url.toString(), headers: headers, track: track),
    };
  }
```

- [ ] **Step 5: Run the fake support tests and verify GREEN**

Run:

```bash
flutter test test/services/audio/playback_request_session_test.dart
```

Expected: PASS. At this point no production music path uses typed media yet.

## Task 3: Add Typed Backend Dispatch To Platform Adapters

**Files:**
- Modify: `lib/services/audio/just_audio_service.dart`
- Modify: `lib/services/audio/media_kit_audio_service.dart`
- Test: `test/services/audio/audio_backend_static_test.dart`

- [ ] **Step 1: Write the failing static backend test**

Create `test/services/audio/audio_backend_static_test.dart`:

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('audio backend typed media dispatch', () {
    test('FmpAudioService exposes typed media methods', () {
      final source = File('lib/services/audio/audio_service.dart')
          .readAsStringSync();

      expect(source, contains('playMedia(PreparedPlaybackMedia media)'));
      expect(source, contains('setMedia(PreparedPlaybackMedia media)'));
    });

    test('JustAudioService dispatches typed media internally', () {
      final source = File('lib/services/audio/just_audio_service.dart')
          .readAsStringSync();

      expect(source, contains('Future<Duration?> playMedia('));
      expect(source, contains('Future<Duration?> setMedia('));
      expect(source, contains('LocalPlaybackMedia'));
      expect(source, contains('RemotePlaybackMedia'));
      expect(source, contains('playFile(path, track: track)'));
      expect(source, contains('playUrl(url.toString(), headers: headers, track: track)'));
    });

    test('MediaKitAudioService dispatches typed media internally', () {
      final source = File('lib/services/audio/media_kit_audio_service.dart')
          .readAsStringSync();

      expect(source, contains('Future<Duration?> playMedia('));
      expect(source, contains('Future<Duration?> setMedia('));
      expect(source, contains('LocalPlaybackMedia'));
      expect(source, contains('RemotePlaybackMedia'));
      expect(source, contains('playFile(path, track: track)'));
      expect(source, contains('playUrl(url.toString(), headers: headers, track: track)'));
    });
  });
}
```

- [ ] **Step 2: Run the static backend test and verify RED**

Run:

```bash
flutter test test/services/audio/audio_backend_static_test.dart
```

Expected: FAIL because platform adapters do not implement `playMedia()` / `setMedia()` yet.

- [ ] **Step 3: Add typed dispatch to JustAudioService**

In `lib/services/audio/just_audio_service.dart`, add:

```dart
import 'playback_media.dart';
```

Add these methods immediately before `playUrl()`:

```dart
  @override
  Future<Duration?> playMedia(PreparedPlaybackMedia media) {
    return switch (media) {
      LocalPlaybackMedia(:final path, :final track) =>
        playFile(path, track: track),
      RemotePlaybackMedia(:final url, :final headers, :final track) =>
        playUrl(url.toString(), headers: headers, track: track),
    };
  }

  @override
  Future<Duration?> setMedia(PreparedPlaybackMedia media) {
    return switch (media) {
      LocalPlaybackMedia(:final path, :final track) =>
        setFile(path, track: track),
      RemotePlaybackMedia(:final url, :final headers, :final track) =>
        setUrl(url.toString(), headers: headers, track: track),
    };
  }
```

- [ ] **Step 4: Add typed dispatch to MediaKitAudioService**

In `lib/services/audio/media_kit_audio_service.dart`, add:

```dart
import 'playback_media.dart';
```

Add these methods immediately before `playUrl()`:

```dart
  @override
  Future<Duration?> playMedia(PreparedPlaybackMedia media) {
    return switch (media) {
      LocalPlaybackMedia(:final path, :final track) =>
        playFile(path, track: track),
      RemotePlaybackMedia(:final url, :final headers, :final track) =>
        playUrl(url.toString(), headers: headers, track: track),
    };
  }

  @override
  Future<Duration?> setMedia(PreparedPlaybackMedia media) {
    return switch (media) {
      LocalPlaybackMedia(:final path, :final track) =>
        setFile(path, track: track),
      RemotePlaybackMedia(:final url, :final headers, :final track) =>
        setUrl(url.toString(), headers: headers, track: track),
    };
  }
```

- [ ] **Step 5: Run backend static test and verify GREEN**

Run:

```bash
flutter test test/services/audio/audio_backend_static_test.dart
```

Expected: PASS.

## Task 4: Make AudioStreamManager Produce Typed Playback Selections

**Files:**
- Modify: `lib/services/audio/audio_stream_manager.dart`
- Modify: `test/services/audio/audio_stream_manager_test.dart`
- Test: `test/services/audio/audio_stream_manager_test.dart`

- [ ] **Step 1: Add failing typed selection tests**

In `test/services/audio/audio_stream_manager_test.dart`, add this import:

```dart
import 'package:fmp/services/audio/playback_media.dart';
```

Add these tests inside `group('AudioStreamManager Task 2 regression', () {` after the existing auth tests at the top:

```dart
    test('selectPlayback returns local typed media for downloaded files',
        () async {
      final audioFile = File('${tempDir.path}/typed-local.m4a');
      await audioFile.writeAsString('audio-bytes');
      final savedTrack = await trackRepository.save(
        _track('typed-local', title: 'Typed Local')
          ..playlistInfo = [
            PlaylistDownloadInfo()
              ..playlistId = 1
              ..playlistName = 'Library'
              ..downloadPath = audioFile.path,
          ],
      );

      final selection = await manager.selectPlayback(savedTrack);

      expect(selection.media, isA<LocalPlaybackMedia>());
      final media = selection.media as LocalPlaybackMedia;
      expect(media.path, audioFile.path);
      expect(media.track.sourceId, 'typed-local');
      expect(media.debugUrl, audioFile.path);
      expect(selection.streamResult, isNull);
    });

    test('selectPlayback returns remote typed media with prepared headers',
        () async {
      sourceAuthContext.authHeaders = const {
        'Authorization': 'Bearer sentinel',
      };

      final selection = await manager.selectPlayback(
        _track('typed-remote', title: 'Typed Remote'),
      );

      expect(selection.media, isA<RemotePlaybackMedia>());
      final media = selection.media as RemotePlaybackMedia;
      expect(media.url.toString(),
          'https://example.com/typed-remote-high.m4a');
      expect(media.headers?['Origin'], SourceHttpPolicy.youtubeOrigin);
      expect(media.debugUrl, 'https://example.com/typed-remote-high.m4a');
      expect(selection.streamResult?.url,
          'https://example.com/typed-remote-high.m4a');
    });

    test('prepareNetworkPlayback returns remote typed media', () async {
      final prepared = await manager.prepareNetworkPlayback(
        _track('typed-prepared', title: 'Typed Prepared'),
        'https://example.com/typed-prepared.m4a',
      );

      expect(prepared, isA<RemotePlaybackMedia>());
      expect(prepared.url.toString(),
          'https://example.com/typed-prepared.m4a');
      expect(prepared.track.sourceId, 'typed-prepared');
      expect(prepared.headers?['Referer'], SourceHttpPolicy.youtubeReferer);
    });
```

- [ ] **Step 2: Run stream manager tests and verify RED**

Run:

```bash
flutter test test/services/audio/audio_stream_manager_test.dart
```

Expected: FAIL because `PlaybackSelection` has no `media` field and `prepareNetworkPlayback()` still returns `PlaybackNetworkRequest`.

- [ ] **Step 3: Update AudioStreamManager imports and interface**

In `lib/services/audio/audio_stream_manager.dart`, add:

```dart
import 'playback_media.dart';
```

Update `PlaybackRequestStreamAccess` to remove `getPlaybackHeaders()` and change `prepareNetworkPlayback()`:

```dart
abstract class PlaybackRequestStreamAccess {
  Future<PlaybackSelection> selectPlayback(
    Track track, {
    bool persist = true,
  });

  Future<PlaybackSelection?> selectFallbackPlayback(
    Track track, {
    String? failedUrl,
  });

  Future<(Track, String?, AudioStreamResult?)> ensureAudioStream(
    Track track, {
    int retryCount = 0,
    bool persist = true,
  });

  Future<RemotePlaybackMedia> prepareNetworkPlayback(
    Track track,
    String url,
  );

  Future<void> prefetchTrack(Track track);
}
```

Update `PlaybackSelection`:

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

- [ ] **Step 4: Update selectPlayback and fallback construction**

Replace `selectPlayback()` with:

```dart
  @override
  Future<PlaybackSelection> selectPlayback(
    Track track, {
    bool persist = true,
  }) async {
    final (trackWithUrl, localPath, streamResult) =
        await ensureAudioStream(track, persist: persist);
    final url = localPath ?? trackWithUrl.audioUrl;
    if (url == null) {
      throw Exception('No audio URL available for: ${track.title}');
    }

    final media = localPath == null
        ? await prepareNetworkPlayback(trackWithUrl, url)
        : LocalPlaybackMedia(path: localPath, track: trackWithUrl);
    return PlaybackSelection(
      media: media,
      streamResult: streamResult,
    );
  }
```

Replace `selectFallbackPlayback()`'s return block with:

```dart
    final media =
        await prepareNetworkPlayback(fallback.track, fallback.stream.url);
    return PlaybackSelection(
      media: media,
      streamResult: fallback.stream,
    );
```

Replace `prepareNetworkPlayback()` with:

```dart
  @override
  Future<RemotePlaybackMedia> prepareNetworkPlayback(
    Track track,
    String url,
  ) async {
    final prepared = await _sourceAuthContext.playbackNetworkRequest(
      track,
      url,
    );
    return RemotePlaybackMedia(
      url: Uri.parse(prepared.url),
      headers: prepared.headers,
      track: track,
    );
  }
```

Delete the `getPlaybackHeaders()` method from `AudioStreamManager`.

- [ ] **Step 5: Update stream manager tests that read old fields**

In `test/services/audio/audio_stream_manager_test.dart`, replace old field assertions:

```dart
expect(selection.localPath, isNull);
expect(selection.track.playlistInfo.single.downloadPath, isEmpty);
```

with:

```dart
expect(selection.media, isA<RemotePlaybackMedia>());
expect(selection.media.track.playlistInfo.single.downloadPath, isEmpty);
```

Replace old fallback field assertions:

```dart
expect(selection!.localPath, isNull);
```

with:

```dart
expect(selection!.media, isA<RemotePlaybackMedia>());
```

Replace the old `getPlaybackHeaders()` tests with `prepareNetworkPlayback()` or `selectPlayback()` assertions. For example, replace:

```dart
final enabledHeaders = await managerWithNetease.getPlaybackHeaders(track);
expect(enabledHeaders?['Cookie'], 'MUSIC_U=music-u; __csrf=csrf');
```

with:

```dart
final enabledMedia = await managerWithNetease.prepareNetworkPlayback(
  track,
  track.audioUrl!,
);
expect(enabledMedia.headers?['Cookie'], 'MUSIC_U=music-u; __csrf=csrf');
```

And replace:

```dart
expect(prepared.url, 'https://attacker.example/netease-song.m4a');
expect(prepared.headers, isNot(contains('Cookie')));
expect(prepared.headers?['Origin'], SourceHttpPolicy.neteaseOrigin);
```

with:

```dart
expect(prepared.url.toString(), 'https://attacker.example/netease-song.m4a');
expect(prepared.headers, isNot(contains('Cookie')));
expect(prepared.headers?['Origin'], SourceHttpPolicy.neteaseOrigin);
```

- [ ] **Step 6: Run stream manager tests and verify GREEN**

Run:

```bash
flutter test test/services/audio/audio_stream_manager_test.dart
```

Expected: PASS.

## Task 5: Move PlaybackRequestSession To Typed Media Handoff

**Files:**
- Modify: `lib/services/audio/playback_request_session.dart`
- Modify: `test/services/audio/playback_request_session_test.dart`
- Test: `test/services/audio/playback_request_session_test.dart`

- [ ] **Step 1: Update playback session fake stream access to typed media**

In `test/services/audio/playback_request_session_test.dart`, keep:

```dart
import 'package:fmp/services/audio/playback_media.dart';
```

In `_FakeStreamAccess`, replace callback fields:

```dart
  Future<PlaybackSelection> Function(Track track, bool persist)?
      onSelectPlayback;
  Future<PlaybackSelection?> Function(Track track, String? failedUrl)?
      onSelectFallbackPlayback;
  Future<RemotePlaybackMedia> Function(Track track, String url)?
      onPrepareNetworkPlayback;
  Future<(Track, String?, AudioStreamResult?)> Function(
    Track track,
    bool persist,
  )? onEnsureAudioStream;
```

Remove `headerRequests`, `_headerRequestWaiters`, `onGetPlaybackHeaders`, `waitForHeaderRequest()`, and `getPlaybackHeaders()`.

Replace `_FakeStreamAccess.selectPlayback()` with:

```dart
  @override
  Future<PlaybackSelection> selectPlayback(
    Track track, {
    bool persist = true,
  }) async {
    selectionRequests.add(track.sourceId);
    final custom = await onSelectPlayback?.call(track, persist);
    if (custom != null) return custom;
    final (trackWithUrl, localPath, streamResult) =
        await ensureAudioStream(track, persist: persist);
    final url = localPath ?? trackWithUrl.audioUrl;
    if (url == null) {
      throw StateError('No playback URL available for ${track.sourceId}');
    }
    final media = localPath == null
        ? await prepareNetworkPlayback(trackWithUrl, url)
        : LocalPlaybackMedia(path: localPath, track: trackWithUrl);
    return PlaybackSelection(
      media: media,
      streamResult: streamResult,
    );
  }
```

Replace `_FakeStreamAccess.prepareNetworkPlayback()` with:

```dart
  @override
  Future<RemotePlaybackMedia> prepareNetworkPlayback(
    Track track,
    String url,
  ) async {
    final custom = await onPrepareNetworkPlayback?.call(track, url);
    if (custom != null) return custom;
    return RemotePlaybackMedia(
      url: Uri.parse(url),
      headers: const {'Referer': 'https://example.com'},
      track: track,
    );
  }
```

- [ ] **Step 2: Update session tests to expect typed backend calls**

Replace `start stops backend and plays selected stream` assertions:

```dart
      expect(audioService.playUrlCalls.single.url,
          'https://example.com/session-start.m4a');
```

with:

```dart
      expect(audioService.playMediaCalls.single.media, isA<RemotePlaybackMedia>());
      expect(audioService.playUrlCalls.single.url,
          'https://example.com/session-start.m4a');
```

Replace the local custom selection:

```dart
        return PlaybackSelection(
          track: track,
          url: '/music/local-session.m4a',
          localPath: '/music/local-session.m4a',
          headers: null,
          streamResult: null,
        );
```

with:

```dart
        return PlaybackSelection(
          media: LocalPlaybackMedia(
            path: '/music/local-session.m4a',
            track: track,
          ),
          streamResult: null,
        );
```

Replace the header test setup:

```dart
      streamManager.onGetPlaybackHeaders = (_) async {
        return const {'X-Test-Header': 'owned-by-manager'};
      };
```

with:

```dart
      streamManager.onPrepareNetworkPlayback = (track, url) async {
        return RemotePlaybackMedia(
          url: Uri.parse(url),
          headers: const {'X-Test-Header': 'owned-by-manager'},
          track: track,
        );
      };
```

Replace the fallback custom selection:

```dart
        return PlaybackSelection(
          track: track,
          url: 'https://example.com/fallback-session-fallback.m3u8',
          localPath: null,
          headers: const {'X-Fallback': 'yes'},
          streamResult: const AudioStreamResult(
            url: 'https://example.com/fallback-session-fallback.m3u8',
            container: 'm3u8',
            codec: 'aac',
            streamType: StreamType.muxed,
          ),
        );
```

with:

```dart
        return PlaybackSelection(
          media: RemotePlaybackMedia(
            url: Uri.parse(
              'https://example.com/fallback-session-fallback.m3u8',
            ),
            headers: const {'X-Fallback': 'yes'},
            track: track,
          ),
          streamResult: const AudioStreamResult(
            url: 'https://example.com/fallback-session-fallback.m3u8',
            container: 'm3u8',
            codec: 'aac',
            streamType: StreamType.muxed,
          ),
        );
```

Replace the restore prepared callback:

```dart
        return const PlaybackNetworkRequest(
          url: 'https://cdn.example.com/restore-prepared.m4a',
          headers: {'X-Prepared': 'yes'},
        );
```

with:

```dart
        return RemotePlaybackMedia(
          url: Uri.parse('https://cdn.example.com/restore-prepared.m4a'),
          headers: const {'X-Prepared': 'yes'},
          track: track,
        );
```

Replace:

```dart
expect(streamManager.headerRequests, isEmpty);
```

with:

```dart
expect(streamManager.selectionRequests, contains('restore-prepared'));
```

- [ ] **Step 3: Add a failing structure test for music session handoff**

Add this import:

```dart
import 'dart:io';
```

Add this test near the end of the file:

```dart
  test('PlaybackRequestSession opens typed media instead of raw URL methods',
      () {
    final source = File('lib/services/audio/playback_request_session.dart')
        .readAsStringSync();

    expect(source, contains('_audioService.playMedia('));
    expect(source, contains('_audioService.setMedia('));
    expect(source, isNot(contains('_audioService.playUrl(')));
    expect(source, isNot(contains('_audioService.setUrl(')));
    expect(source, isNot(contains('_audioService.playFile(')));
    expect(source, isNot(contains('_audioService.setFile(')));
    expect(source, isNot(contains('headers: selection.headers')));
    expect(source, isNot(contains('headers: networkRequest.headers')));
  });
```

- [ ] **Step 4: Run session tests and verify RED**

Run:

```bash
flutter test test/services/audio/playback_request_session_test.dart
```

Expected: FAIL because production `PlaybackRequestSession` still calls `playUrl()` / `setUrl()` / `playFile()` / `setFile()`.

- [ ] **Step 5: Update PlaybackRequestSession restore path**

In `lib/services/audio/playback_request_session.dart`, replace `_executeQueueRestore()` body from URL preparation through backend set calls with typed selection:

```dart
    logDebug('Restoring queue track: ${track.title}');
    final selection = await _audioStreamManager.selectPlayback(
      track,
      persist: true,
    );

    if (isSuperseded(requestId)) {
      logDebug(
        'Queue restore request $requestId superseded after playback selection, aborting',
      );
      return null;
    }

    final attemptedUrl = selection.media.debugUrl;
    await _waitForRequestOperation<void>(
      requestId: requestId,
      operation: _audioService.setMedia(selection.media),
      description: 'setMedia',
    );
```

Keep the existing supersession check, seek block, resume block, and result return. Update the result return to use typed media:

```dart
    return _PlaybackRequestExecution(
      track: selection.media.track,
      attemptedUrl: attemptedUrl,
      streamResult: selection.streamResult,
    );
```

- [ ] **Step 6: Update PlaybackRequestSession play path**

In `_execute()`, replace `selection.track` and `selection.url` usages:

```dart
          final fallbackSelection =
              await _audioStreamManager.selectFallbackPlayback(
            selection.media.track,
            failedUrl: selection.media.debugUrl,
          );
```

Replace fallback logging's failed URL:

```dart
            'Attempting manager-selected fallback playback for: ${track.title} (failed URL: ${selection.media.debugUrl})',
```

Replace fallback result:

```dart
              track: fallbackSelection.media.track,
              attemptedUrl: fallbackSelection.media.debugUrl,
              streamResult: fallbackSelection.streamResult,
```

Replace normal result:

```dart
      track: selection.media.track,
      attemptedUrl: selection.media.debugUrl,
      streamResult: selection.streamResult,
```

Replace `_playSelection()` with:

```dart
  Future<void> _playSelection(
      int requestId, PlaybackSelection selection) async {
    final media = selection.media;
    final urlType = media is LocalPlaybackMedia ? 'downloaded' : 'stream';
    logDebug(
      'Playing track: ${media.track.title}, URL type: $urlType, source: ${media.track.sourceType}',
    );

    if (isSuperseded(requestId)) {
      logDebug(
        'Play request $requestId superseded before playback handoff, aborting',
      );
      return;
    }

    await _waitForRequestOperation<void>(
      requestId: requestId,
      operation: _audioService.playMedia(media),
      description: 'playMedia',
    );
  }
```

Add this import at the top:

```dart
import 'playback_media.dart';
```

- [ ] **Step 7: Run session tests and verify GREEN**

Run:

```bash
flutter test test/services/audio/playback_request_session_test.dart
```

Expected: PASS.

## Task 6: Update Remaining Audio Tests For Typed Media Compatibility

**Files:**
- Modify: `test/services/audio/audio_controller_phase1_test.dart`
- Modify: `test/services/audio/audio_auth_retry_phase4_test.dart`
- Modify: `test/services/audio/audio_controller_mix_boundary_test.dart`
- Modify: `test/services/audio/temporary_play_handler_test.dart`
- Modify: `test/services/audio/audio_queue_state_provider_test.dart`
- Modify: `test/services/audio/mix_session_handler_test.dart`
- Modify: `test/services/audio/audio_service_dispose_test.dart`
- Modify: `test/ui/pages/queue/queue_page_reorder_test.dart`
- Test: `test/services/audio`

- [ ] **Step 1: Run the audio test suite and record compile failures**

Run:

```bash
flutter test test/services/audio
```

Expected: FAIL initially because helper fakes and assertions still reference old `PlaybackSelection` fields or `PlaybackNetworkRequest` return types.

- [ ] **Step 2: Update fake SourceAuthContext imports only when needed**

For tests that only fake `SourceAuthContext.playbackNetworkRequest()`, no production signature changes are required. Keep returning `PlaybackNetworkRequest` from the fake because `SourceAuthContext` still owns playback network request preparation.

If a test imports `audio_stream_manager.dart` only to get `PlaybackNetworkRequest`, replace the import with:

```dart
import 'package:fmp/services/account/source_auth_context.dart'
    show PlaybackNetworkRequest;
```

- [ ] **Step 3: Update old `PlaybackSelection` constructors**

For every compile failure that constructs `PlaybackSelection` with `track`, `url`, `localPath`, and `headers`, import:

```dart
import 'package:fmp/services/audio/playback_media.dart';
```

Replace remote selections:

```dart
return PlaybackSelection(
  track: track,
  url: 'https://example.com/song.m4a',
  localPath: null,
  headers: const {'Referer': 'https://example.com'},
  streamResult: const AudioStreamResult(
    url: 'https://example.com/song.m4a',
    streamType: StreamType.audioOnly,
  ),
);
```

with:

```dart
return PlaybackSelection(
  media: RemotePlaybackMedia(
    url: Uri.parse('https://example.com/song.m4a'),
    headers: const {'Referer': 'https://example.com'},
    track: track,
  ),
  streamResult: const AudioStreamResult(
    url: 'https://example.com/song.m4a',
    streamType: StreamType.audioOnly,
  ),
);
```

Replace local selections:

```dart
return PlaybackSelection(
  track: track,
  url: '/music/song.m4a',
  localPath: '/music/song.m4a',
  headers: null,
  streamResult: null,
);
```

with:

```dart
return PlaybackSelection(
  media: LocalPlaybackMedia(
    path: '/music/song.m4a',
    track: track,
  ),
  streamResult: null,
);
```

- [ ] **Step 4: Update assertions that inspect URL/file calls**

Keep broad controller assertions against `playUrlCalls` / `setUrlCalls` when they are testing end-to-end behavior through `FakeAudioService`, because fake typed media delegates to old call records.

For tests specifically about `PlaybackRequestSession` handoff, assert `playMediaCalls` / `setMediaCalls`.

- [ ] **Step 5: Run audio test suite and verify GREEN**

Run:

```bash
flutter test test/services/audio
```

Expected: PASS.

## Task 7: Update Documentation Guidance

**Files:**
- Modify: `lib/services/audio/AGENTS.md`
- Test: `git diff --check -- lib/services/audio/AGENTS.md`

- [ ] **Step 1: Update audio internals ownership guidance**

In `lib/services/audio/AGENTS.md`, replace the `AudioStreamManager` bullet:

```markdown
- `AudioStreamManager` owns playback selection and calls
  `SourceAuthContext.playbackNetworkRequest()` before handing a URL to the
  backend. `SourceAuthContext` owns the Auth For Play gate; the byte-request
  URL/header policy is delegated to `MediaHandoff`.
```

with:

```markdown
- `AudioStreamManager` owns playback selection and prepares
  `PreparedPlaybackMedia` for music playback. It calls
  `SourceAuthContext.playbackNetworkRequest()` for remote streams before
  producing `RemotePlaybackMedia`. `SourceAuthContext` owns the Auth For Play
  gate; the byte-request URL/header policy is delegated to `MediaHandoff`.
- Music playback opens media through `FmpAudioService.playMedia()` /
  `setMedia()`. Direct `playUrl()` / `setUrl()` remain for radio and
  compatibility-only paths; do not add new music playback callers for raw URL
  methods.
```

- [ ] **Step 2: Run documentation whitespace check**

Run:

```bash
git diff --check -- lib/services/audio/AGENTS.md
```

Expected: no output and exit code 0.

## Task 8: Final Verification And Call-Site Inspection

**Files:**
- Verifies all touched files.

- [ ] **Step 1: Run focused tests**

Run:

```bash
flutter test test/services/audio/playback_media_test.dart test/services/audio/audio_backend_static_test.dart test/services/audio/audio_stream_manager_test.dart test/services/audio/playback_request_session_test.dart
```

Expected: PASS.

- [ ] **Step 2: Run audio test suite**

Run:

```bash
flutter test test/services/audio
```

Expected: PASS.

- [ ] **Step 3: Run static analysis**

Run:

```bash
flutter analyze
```

Expected: no new analyzer errors.

- [ ] **Step 4: Inspect music playback call sites**

Run:

```bash
rg -n "playUrl\\(|setUrl\\(|playFile\\(|setFile\\(|playMedia\\(|setMedia\\(|PlaybackSelection\\(" lib/services/audio lib/services/radio test/services/audio test/support/fakes
```

Expected:

- `lib/services/audio/playback_request_session.dart` contains `playMedia(` and `setMedia(` only.
- `lib/services/audio/just_audio_service.dart` and `lib/services/audio/media_kit_audio_service.dart` contain typed dispatch plus existing URL/file methods.
- `lib/services/radio/radio_controller.dart` may still call `playUrl(` directly.
- `test/support/fakes/fake_audio_service.dart` contains typed dispatch plus existing URL/file records.
- No `PlaybackSelection(` call uses `track:`, `url:`, `localPath:`, or `headers:`.

- [ ] **Step 5: Run diff hygiene**

Run:

```bash
git diff --check
```

Expected: no whitespace errors.

- [ ] **Step 6: Status checkpoint**

Run:

```bash
git status --short
```

Expected changed files include only the intended spec/plan, audio implementation, audio tests, fake audio service, and `lib/services/audio/AGENTS.md`. Do not commit unless the user explicitly asks.

## Self-Review

- Spec coverage:
  - Typed prepared playback media: Task 1.
  - Backend interface and adapters open one typed media value: Tasks 2 and 3.
  - AudioStreamManager prepares local/remote media: Task 4.
  - PlaybackRequestSession stops raw URL/header handoff: Task 5.
  - Compatibility with broad audio tests: Task 6.
  - Documentation update: Task 7.
  - Verification and call-site inspection: Task 8.
- Placeholder scan:
  - This plan contains no unfinished markers or unspecified implementation steps.
- Type consistency:
  - `PreparedPlaybackMedia`, `LocalPlaybackMedia`, `RemotePlaybackMedia`, `playMedia()`, `setMedia()`, and the new `PlaybackSelection.media` shape are used consistently across tasks.
