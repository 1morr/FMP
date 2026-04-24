# Review-Driven Refactor Phase 2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement Phase 2 logic unification and duplicate cleanup from the review-driven refactor roadmap without changing playback queue semantics or database schema.

**Architecture:** Keep each subsystem change isolated: download media request headers become a small helper, import selection copies `Track` objects before tagging original IDs, remote playlist mutations move out of the page into a service, provider event glue gets a testable coordinator, and file existence checks gain bounded negative caching. Phase 1 already removed the unused `searchHistoryProvider`, so this plan excludes that completed item.

**Tech Stack:** Flutter, Dart, Riverpod, Isar, `flutter_test`, `package:path`, existing fake services and source-code/static tests.

---

## Scope and File Map

- Create `lib/services/download/download_media_headers.dart`: source-specific media-download headers that mirror playback headers and only merge NetEase auth headers into NetEase media requests.
- Modify `lib/services/download/download_service.dart`: use the helper for isolate download request headers.
- Test `test/services/download/download_media_headers_test.dart`: unit coverage for header composition and auth leakage prevention.
- Modify `lib/services/import/playlist_import_service.dart`: copy selected tracks before setting `originalSongId` / `originalSource`.
- Test `test/services/import/playlist_import_service_test.dart`: selected-track copy behavior.
- Modify `test/services/lyrics/lyrics_auto_match_service_phase4_test.dart`: direct fetch and existing-match regression coverage.
- Modify `test/support/fakes/fake_audio_service.dart` and `test/services/audio/playback_request_executor_test.dart`: local-file handoff coverage.
- Create `lib/providers/download/download_event_handler.dart`: testable coordinator for download completion/failure provider side effects.
- Modify `lib/providers/download/download_providers.dart`: delegate stream handlers to the coordinator.
- Test `test/providers/download/download_event_handler_test.dart`: completion/failure glue without real downloads.
- Create `lib/services/library/remote_playlist_actions_service.dart`: remove-from-remote logic for Bilibili, YouTube, and NetEase.
- Modify `lib/providers/account_provider.dart`: expose `remotePlaylistActionsServiceProvider`.
- Modify `lib/ui/pages/library/playlist_detail_page.dart`: replace duplicated remote removal switch blocks with service calls.
- Test `test/services/library/remote_playlist_actions_service_test.dart`: parsing/filtering/callback behavior.
- Modify `lib/providers/download/file_exists_cache.dart`: add bounded negative cache for missing paths.
- Test `test/providers/download/file_exists_cache_phase4_test.dart`: negative-cache behavior.

---

### Task 1: Unify Download Media Headers

**Files:**
- Create: `lib/services/download/download_media_headers.dart`
- Modify: `lib/services/download/download_service.dart:656-667`
- Test: `test/services/download/download_media_headers_test.dart`

- [ ] **Step 1: Write the failing header helper tests**

Create `test/services/download/download_media_headers_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/models/track.dart';
import 'package:fmp/services/audio/audio_stream_manager.dart';
import 'package:fmp/services/download/download_media_headers.dart';

void main() {
  group('buildDownloadMediaHeaders', () {
    test('bilibili media headers do not leak auth cookies', () {
      final headers = buildDownloadMediaHeaders(
        SourceType.bilibili,
        authHeaders: const {'Cookie': 'SESSDATA=secret'},
      );

      expect(headers['Referer'], 'https://www.bilibili.com');
      expect(headers['User-Agent'], AudioStreamManager.defaultPlaybackUserAgent);
      expect(headers.containsKey('Cookie'), isFalse);
    });

    test('youtube media headers do not leak authorization headers', () {
      final headers = buildDownloadMediaHeaders(
        SourceType.youtube,
        authHeaders: const {'Authorization': 'Bearer secret'},
      );

      expect(headers['Origin'], 'https://www.youtube.com');
      expect(headers['Referer'], 'https://www.youtube.com/');
      expect(headers['User-Agent'], AudioStreamManager.defaultPlaybackUserAgent);
      expect(headers.containsKey('Authorization'), isFalse);
    });

    test('netease media headers preserve netease auth for media requests', () {
      final headers = buildDownloadMediaHeaders(
        SourceType.netease,
        authHeaders: const {
          'Cookie': 'MUSIC_U=token',
          'Origin': 'https://music.163.com',
          'Referer': 'https://music.163.com/',
          'User-Agent': 'NetEase-UA',
          'X-Api-Only': 'drop-me',
        },
      );

      expect(headers['Cookie'], 'MUSIC_U=token');
      expect(headers['Origin'], 'https://music.163.com');
      expect(headers['Referer'], 'https://music.163.com/');
      expect(headers['User-Agent'], 'NetEase-UA');
      expect(headers.containsKey('X-Api-Only'), isFalse);
    });
  });
}
```

- [ ] **Step 2: Run the new test to verify it fails**

Run: `flutter test test/services/download/download_media_headers_test.dart`
Expected: FAIL because `download_media_headers.dart` does not exist.

- [ ] **Step 3: Add the header helper**

Create `lib/services/download/download_media_headers.dart`:

```dart
import '../../data/models/track.dart';
import '../audio/audio_stream_manager.dart';

Map<String, String> buildDownloadMediaHeaders(
  SourceType sourceType, {
  Map<String, String>? authHeaders,
}) {
  final headers = switch (sourceType) {
    SourceType.bilibili => <String, String>{
        'Referer': 'https://www.bilibili.com',
        'User-Agent': AudioStreamManager.defaultPlaybackUserAgent,
      },
    SourceType.youtube => <String, String>{
        'Origin': 'https://www.youtube.com',
        'Referer': 'https://www.youtube.com/',
        'User-Agent': AudioStreamManager.defaultPlaybackUserAgent,
      },
    SourceType.netease => <String, String>{
        'Origin': 'https://music.163.com',
        'Referer': 'https://music.163.com/',
        'User-Agent': AudioStreamManager.defaultPlaybackUserAgent,
      },
  };

  if (sourceType == SourceType.netease && authHeaders != null) {
    for (final key in const ['Cookie', 'Origin', 'Referer', 'User-Agent']) {
      final value = authHeaders[key];
      if (value != null && value.isNotEmpty) {
        headers[key] = value;
      }
    }
  }

  return headers;
}
```

- [ ] **Step 4: Use the helper in `DownloadService`**

In `lib/services/download/download_service.dart`, add the import near the other download imports:

```dart
import 'download_media_headers.dart';
```

Replace the local header construction at `lib/services/download/download_service.dart:659-667`:

```dart
final referer = switch (track.sourceType) {
  SourceType.bilibili => 'https://www.bilibili.com',
  SourceType.youtube => 'https://www.youtube.com',
  SourceType.netease => 'https://music.163.com',
};
final headers = {
  'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
  'Referer': referer,
};
```

with:

```dart
final headers = buildDownloadMediaHeaders(
  track.sourceType,
  authHeaders: authHeaders,
);
```

- [ ] **Step 5: Verify and commit**

Run: `dart format lib/services/download/download_media_headers.dart lib/services/download/download_service.dart test/services/download/download_media_headers_test.dart`
Expected: files are formatted.

Run: `flutter test test/services/download/download_media_headers_test.dart test/services/download/download_service_phase1_test.dart`
Expected: all tests pass.

Run: `git add lib/services/download/download_media_headers.dart lib/services/download/download_service.dart test/services/download/download_media_headers_test.dart && git commit -m "refactor(download): unify media request headers"`
Expected: commit succeeds.

---

### Task 2: Copy External Import Selected Tracks

**Files:**
- Modify: `lib/services/import/playlist_import_service.dart:67-78`
- Test: `test/services/import/playlist_import_service_test.dart`

- [ ] **Step 1: Write the failing selected-track copy test**

Create `test/services/import/playlist_import_service_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/models/track.dart';
import 'package:fmp/data/sources/base_source.dart';
import 'package:fmp/data/sources/playlist_import/playlist_import_source.dart';
import 'package:fmp/services/import/playlist_import_service.dart';

void main() {
  group('PlaylistImportResult.selectedTracks', () {
    test('copies selected tracks before writing original platform metadata', () {
      final selected = Track()
        ..id = 42
        ..sourceId = 'matched-bv'
        ..sourceType = SourceType.bilibili
        ..title = 'Matched Song'
        ..artist = 'Matched Artist';

      final result = PlaylistImportResult(
        playlist: const ImportedPlaylist(
          name: 'QQ Playlist',
          sourceUrl: 'https://y.qq.com/n/ryqq/playlist/123',
          source: PlaylistSource.qqMusic,
          tracks: [],
          totalCount: 1,
        ),
        matchedTracks: [
          MatchedTrack(
            original: const ImportedTrack(
              title: 'Original Song',
              artists: ['Original Artist'],
              sourceId: 'qq-songmid-1',
              source: PlaylistSource.qqMusic,
            ),
            selectedTrack: selected,
            status: MatchStatus.userSelected,
          ),
        ],
      );

      final tracks = result.selectedTracks;

      expect(tracks, hasLength(1));
      expect(identical(tracks.single, selected), isFalse);
      expect(tracks.single.id, selected.id);
      expect(tracks.single.sourceId, selected.sourceId);
      expect(tracks.single.originalSongId, 'qq-songmid-1');
      expect(tracks.single.originalSource, 'qqmusic');
      expect(selected.originalSongId, isNull);
      expect(selected.originalSource, isNull);
    });
  });
}
```

- [ ] **Step 2: Run the new test to verify it fails**

Run: `flutter test test/services/import/playlist_import_service_test.dart`
Expected: FAIL on `identical(tracks.single, selected)` or mutated `selected.originalSongId`, because `selectedTracks` currently mutates and returns `selectedTrack` directly.

- [ ] **Step 3: Copy the selected track before tagging original metadata**

In `lib/services/import/playlist_import_service.dart`, replace the `selectedTracks` getter with:

```dart
  /// 获取已匹配的歌曲（用于创建歌单）
  List<Track> get selectedTracks => matchedTracks
      .where((t) => t.isIncluded && t.selectedTrack != null)
      .map((t) {
        final track = t.selectedTrack!.copy();
        if (t.original.sourceId != null) {
          track.originalSongId = t.original.sourceId;
          track.originalSource = _mapSourceToString(t.original.source);
        }
        return track;
      })
      .toList();
```

- [ ] **Step 4: Verify and commit**

Run: `dart format lib/services/import/playlist_import_service.dart test/services/import/playlist_import_service_test.dart`
Expected: files are formatted.

Run: `flutter test test/services/import/playlist_import_service_test.dart test/providers/import_playlist_provider_phase2_test.dart`
Expected: all tests pass.

Run: `git add lib/services/import/playlist_import_service.dart test/services/import/playlist_import_service_test.dart && git commit -m "fix(import): copy selected playlist tracks"`
Expected: commit succeeds.

---

### Task 3: Protect Lyrics Direct-Fetch Behavior

**Files:**
- Modify: `test/services/lyrics/lyrics_auto_match_service_phase4_test.dart`

- [ ] **Step 1: Extend fake lyrics sources to record direct fetches**

In `test/services/lyrics/lyrics_auto_match_service_phase4_test.dart`, replace `_FakeNeteaseSource` with:

```dart
class _FakeNeteaseSource extends NeteaseSource {
  final List<String> searchCalls = [];
  final List<String> directFetchCalls = [];
  final Completer<void> _searchCalled = Completer<void>();
  List<LyricsResult> searchResults = [];
  final Map<String, LyricsResult?> directResults = {};
  Future<List<LyricsResult>> Function()? onSearch;

  Future<void> waitForSearchCall() => _searchCalled.future;

  @override
  Future<List<LyricsResult>> searchLyrics({
    String? query,
    String? trackName,
    String? artistName,
    int limit = 10,
  }) async {
    final effectiveQuery =
        query ?? [trackName, artistName].whereType<String>().join(' ');
    searchCalls.add(effectiveQuery);
    if (!_searchCalled.isCompleted) {
      _searchCalled.complete();
    }
    return onSearch != null ? await onSearch!() : searchResults;
  }

  @override
  Future<LyricsResult?> getLyricsResult(String songId) async {
    directFetchCalls.add(songId);
    return directResults[songId];
  }
}
```

Replace `_FakeQQMusicSource` with:

```dart
class _FakeQQMusicSource extends QQMusicSource {
  final List<String> searchCalls = [];
  final List<String> directFetchCalls = [];
  List<LyricsResult> searchResults = [];
  final Map<String, LyricsResult?> directResults = {};

  @override
  Future<List<LyricsResult>> searchLyrics({
    String? query,
    String? trackName,
    String? artistName,
    int limit = 10,
  }) async {
    final effectiveQuery =
        query ?? [trackName, artistName].whereType<String>().join(' ');
    searchCalls.add(effectiveQuery);
    return searchResults;
  }

  @override
  Future<LyricsResult?> getLyricsResult(String songmid) async {
    directFetchCalls.add(songmid);
    return directResults[songmid];
  }
}
```

- [ ] **Step 2: Add direct-fetch regression tests**

Add these tests inside the `LyricsAutoMatchService phase 4` group:

```dart
    test('tryAutoMatch short-circuits when a lyrics match already exists', () async {
      await repo.save(
        LyricsMatch()
          ..trackUniqueKey = 'youtube:existing'
          ..lyricsSource = 'netease'
          ..externalId = 'old-id'
          ..offsetMs = 0
          ..matchedAt = DateTime.now(),
      );

      final matched = await service.tryAutoMatch(
        _track('existing'),
        enabledSources: const ['netease', 'qqmusic'],
      );

      expect(matched, isFalse);
      expect(netease.directFetchCalls, isEmpty);
      expect(netease.searchCalls, isEmpty);
      expect(qqmusic.searchCalls, isEmpty);
      expect(cache.savedKeys, isEmpty);
    });

    test('tryAutoMatch fetches netease lyrics directly by sourceId', () async {
      netease.directResults['netease-song-1'] = _lyricsResult(
        id: 'netease-song-1',
        source: 'netease',
      );
      final track = _track('netease-song-1')..sourceType = SourceType.netease;

      final matched = await service.tryAutoMatch(
        track,
        enabledSources: const ['qqmusic', 'netease'],
      );

      expect(matched, isTrue);
      expect(netease.directFetchCalls, ['netease-song-1']);
      expect(qqmusic.searchCalls, isEmpty);
      final saved = await repo.getByTrackKey('netease:netease-song-1');
      expect(saved, isNotNull);
      expect(saved!.lyricsSource, 'netease');
      expect(saved.externalId, 'netease-song-1');
      expect(cache.savedKeys, ['netease:netease-song-1']);
    });

    test('tryAutoMatch fetches qqmusic lyrics directly by originalSongId', () async {
      qqmusic.directResults['qq-songmid-1'] = _lyricsResult(
        id: 'qq-songmid-1',
        source: 'qqmusic',
      );
      final track = _track('matched-from-import')
        ..originalSongId = 'qq-songmid-1'
        ..originalSource = 'qqmusic';

      final matched = await service.tryAutoMatch(
        track,
        enabledSources: const ['netease', 'qqmusic'],
      );

      expect(matched, isTrue);
      expect(qqmusic.directFetchCalls, ['qq-songmid-1']);
      expect(netease.searchCalls, isEmpty);
      expect(qqmusic.searchCalls, isEmpty);
      final saved = await repo.getByTrackKey('youtube:matched-from-import');
      expect(saved, isNotNull);
      expect(saved!.lyricsSource, 'qqmusic');
      expect(saved.externalId, 'qq-songmid-1');
    });

    test('tryAutoMatch falls back to search for spotify original IDs', () async {
      netease.searchResults = [
        _lyricsResult(id: 'netease-search-1', source: 'netease'),
      ];
      final track = _track('spotify-import')
        ..originalSongId = 'spotify-track-1'
        ..originalSource = 'spotify';

      final matched = await service.tryAutoMatch(
        track,
        enabledSources: const ['netease'],
      );

      expect(matched, isTrue);
      expect(netease.directFetchCalls, isEmpty);
      expect(qqmusic.directFetchCalls, isEmpty);
      expect(netease.searchCalls, ['Song Name Singer']);
      final saved = await repo.getByTrackKey('youtube:spotify-import');
      expect(saved, isNotNull);
      expect(saved!.lyricsSource, 'netease');
      expect(saved.externalId, 'netease-search-1');
    });
```

- [ ] **Step 3: Run the lyrics tests**

Run: `dart format test/services/lyrics/lyrics_auto_match_service_phase4_test.dart`
Expected: file is formatted.

Run: `flutter test test/services/lyrics/lyrics_auto_match_service_phase4_test.dart`
Expected: PASS. If a direct-fetch assertion fails, fix only `lib/services/lyrics/lyrics_auto_match_service.dart` so existing-match, NetEase direct fetch, imported QQ direct fetch, and Spotify search fallback match the tests.

- [ ] **Step 4: Commit**

Run: `git add test/services/lyrics/lyrics_auto_match_service_phase4_test.dart lib/services/lyrics/lyrics_auto_match_service.dart && git commit -m "test(lyrics): cover import direct fetch"`
Expected: commit succeeds; if `lib/services/lyrics/lyrics_auto_match_service.dart` is unchanged, Git commits only the test file.

---

### Task 4: Protect Local-File Playback Handoff

**Files:**
- Modify: `test/support/fakes/fake_audio_service.dart`
- Modify: `test/services/audio/playback_request_executor_test.dart`

- [ ] **Step 1: Record file handoff calls in the fake audio service**

In `test/support/fakes/fake_audio_service.dart`, add this class after `AudioUrlCall`:

```dart
class AudioFileCall {
  AudioFileCall({required this.filePath, this.track});

  final String filePath;
  final Track? track;
}
```

Add these fields inside `FakeAudioService` near `playUrlCalls` and `setUrlCalls`:

```dart
  final List<AudioFileCall> playFileCalls = [];
  final List<AudioFileCall> setFileCalls = [];
```

Replace `playFile` and `setFile` at the bottom with:

```dart
  @override
  Future<Duration?> playFile(String filePath, {Track? track}) async {
    playFileCalls.add(AudioFileCall(filePath: filePath, track: track));
    _isPlaying = true;
    _processingState = FmpAudioProcessingState.ready;
    _emitState();
    return _duration;
  }

  @override
  Future<Duration?> setFile(String filePath, {Track? track}) async {
    setFileCalls.add(AudioFileCall(filePath: filePath, track: track));
    _processingState = FmpAudioProcessingState.ready;
    _emitState();
    return _duration;
  }
```

- [ ] **Step 2: Make the executor test harness able to return a local path**

In `_HarnessPlaybackRequestStreamAccess`, add this field near `onGetPlaybackHeaders`:

```dart
  Future<(Track, String?, AudioStreamResult?)> Function(
    Track track,
    bool persist,
  )? onEnsureAudioStream;
```

At the start of `ensureAudioStream`, before setting `trackWithUrl.audioUrl`, add:

```dart
    final customEnsure = onEnsureAudioStream;
    if (customEnsure != null) {
      return customEnsure(track, persist);
    }
```

- [ ] **Step 3: Add the local-file handoff test**

Add this test inside `PlaybackRequestExecutor Task 1 regression`:

```dart
    test('execute plays local selections with playFile and skips URL headers', () async {
      final localTrack = _track('downloaded-local', title: 'Downloaded Local')
        ..downloadPath = '/music/fmp/downloaded-local.m4a';
      final streamManager = _HarnessPlaybackRequestStreamAccess(
        trackBySourceId: {localTrack.sourceId: localTrack},
      );
      streamManager.onEnsureAudioStream = (track, persist) async {
        expect(persist, isTrue);
        return (localTrack, localTrack.downloadPath, null);
      };
      streamManager.onGetPlaybackHeaders = (_) async {
        fail('Local file playback must not request network headers.');
      };
      streamManager.onSelectFallbackPlayback = (_, __) async {
        fail('Local file playback must not request stream fallback.');
      };
      final audioService = FakeAudioService();
      final executor = PlaybackRequestExecutor(
        audioService: audioService,
        audioStreamManager: streamManager,
        getNextTrack: () => null,
        isSuperseded: (_) => false,
      );

      final result = await executor.execute(
        requestId: 11,
        track: localTrack,
        stopBeforePlay: false,
        prefetchNext: false,
      );

      expect(result, isNotNull);
      expect(result!.attemptedUrl, '/music/fmp/downloaded-local.m4a');
      expect(audioService.playFileCalls.single.filePath,
          '/music/fmp/downloaded-local.m4a');
      expect(audioService.playFileCalls.single.track?.sourceId, 'downloaded-local');
      expect(audioService.playUrlCalls, isEmpty);
      expect(streamManager.headerRequests, isEmpty);
      expect(streamManager.fallbackSelectionTracks, isEmpty);
    });
```

- [ ] **Step 4: Verify and commit**

Run: `dart format test/support/fakes/fake_audio_service.dart test/services/audio/playback_request_executor_test.dart`
Expected: files are formatted.

Run: `flutter test test/services/audio/playback_request_executor_test.dart`
Expected: all tests pass.

Run: `git add test/support/fakes/fake_audio_service.dart test/services/audio/playback_request_executor_test.dart && git commit -m "test(audio): cover local file handoff"`
Expected: commit succeeds.

---

### Task 5: Extract Download Provider Event Handling

**Files:**
- Create: `lib/providers/download/download_event_handler.dart`
- Modify: `lib/providers/download/download_providers.dart:59-122`
- Test: `test/providers/download/download_event_handler_test.dart`

- [ ] **Step 1: Write tests for completion and failure side effects**

Create `test/providers/download/download_event_handler_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/providers/download/download_event_handler.dart';
import 'package:fmp/services/download/download_service.dart';

void main() {
  group('DownloadEventHandler', () {
    test('completion marks cache, removes progress, and batches invalidations', () async {
      final existingPaths = <String>[];
      final removedProgress = <int>[];
      var categoryInvalidations = 0;
      final trackInvalidations = <String>[];
      final refreshedPlaylists = <int>[];
      final handler = DownloadEventHandler(
        markFileExisting: existingPaths.add,
        removeProgress: removedProgress.add,
        invalidateCategories: () => categoryInvalidations++,
        invalidateCategoryTracks: trackInvalidations.add,
        refreshPlaylist: refreshedPlaylists.add,
        showFailure: (_) => fail('Completion must not show failure.'),
        debounceDuration: Duration.zero,
      );
      addTearDown(handler.dispose);

      handler.handleCompletion(DownloadCompletionEvent(
        taskId: 7,
        trackId: 9,
        playlistId: 11,
        savePath: '/downloads/Playlist A/Video 1/audio.m4a',
      ));

      expect(existingPaths, ['/downloads/Playlist A/Video 1/audio.m4a']);
      expect(removedProgress, [7]);
      await Future<void>.delayed(Duration.zero);

      expect(categoryInvalidations, 1);
      expect(trackInvalidations, ['/downloads/Playlist A']);
      expect(refreshedPlaylists, [11]);
    });

    test('failure delegates to failure presenter', () {
      final failures = <DownloadFailureEvent>[];
      final handler = DownloadEventHandler(
        markFileExisting: (_) => fail('Failure must not mark files.'),
        removeProgress: (_) => fail('Failure must not remove progress.'),
        invalidateCategories: () => fail('Failure must not invalidate categories.'),
        invalidateCategoryTracks: (_) => fail('Failure must not invalidate tracks.'),
        refreshPlaylist: (_) => fail('Failure must not refresh playlists.'),
        showFailure: failures.add,
        debounceDuration: Duration.zero,
      );
      addTearDown(handler.dispose);

      final event = DownloadFailureEvent(
        taskId: 3,
        trackId: 4,
        trackTitle: 'Broken Song',
        errorMessage: 'network failed',
      );
      handler.handleFailure(event);

      expect(failures, [event]);
    });
  });
}
```

- [ ] **Step 2: Run the new test to verify it fails**

Run: `flutter test test/providers/download/download_event_handler_test.dart`
Expected: FAIL because `download_event_handler.dart` does not exist.

- [ ] **Step 3: Add the event handler**

Create `lib/providers/download/download_event_handler.dart`:

```dart
import 'dart:async';

import 'package:path/path.dart' as p;

import '../../services/download/download_service.dart';

class DownloadEventHandler {
  DownloadEventHandler({
    required void Function(String path) markFileExisting,
    required void Function(int taskId) removeProgress,
    required void Function() invalidateCategories,
    required void Function(String categoryPath) invalidateCategoryTracks,
    required void Function(int playlistId) refreshPlaylist,
    required void Function(DownloadFailureEvent event) showFailure,
    required Duration debounceDuration,
  })  : _markFileExisting = markFileExisting,
        _removeProgress = removeProgress,
        _invalidateCategories = invalidateCategories,
        _invalidateCategoryTracks = invalidateCategoryTracks,
        _refreshPlaylist = refreshPlaylist,
        _showFailure = showFailure,
        _debounceDuration = debounceDuration;

  final void Function(String path) _markFileExisting;
  final void Function(int taskId) _removeProgress;
  final void Function() _invalidateCategories;
  final void Function(String categoryPath) _invalidateCategoryTracks;
  final void Function(int playlistId) _refreshPlaylist;
  final void Function(DownloadFailureEvent event) _showFailure;
  final Duration _debounceDuration;

  final Set<int> _pendingPlaylistIds = <int>{};
  final Set<String> _pendingCategoryPaths = <String>{};
  bool _categoriesNeedRefresh = false;
  Timer? _debounceTimer;

  void handleCompletion(DownloadCompletionEvent event) {
    _markFileExisting(event.savePath);
    _removeProgress(event.taskId);

    _categoriesNeedRefresh = true;
    _pendingCategoryPaths.add(p.dirname(p.dirname(event.savePath)));
    final playlistId = event.playlistId;
    if (playlistId != null) {
      _pendingPlaylistIds.add(playlistId);
    }

    _debounceTimer?.cancel();
    _debounceTimer = Timer(_debounceDuration, flushInvalidations);
  }

  void handleFailure(DownloadFailureEvent event) {
    _showFailure(event);
  }

  void flushInvalidations() {
    if (_categoriesNeedRefresh) {
      _invalidateCategories();
      _categoriesNeedRefresh = false;
    }
    for (final categoryPath in _pendingCategoryPaths) {
      _invalidateCategoryTracks(categoryPath);
    }
    _pendingCategoryPaths.clear();

    for (final playlistId in _pendingPlaylistIds) {
      _refreshPlaylist(playlistId);
    }
    _pendingPlaylistIds.clear();
  }

  void dispose() {
    _debounceTimer?.cancel();
  }
}
```

- [ ] **Step 4: Delegate provider stream handling to the event handler**

In `lib/providers/download/download_providers.dart`, add:

```dart
import 'download_event_handler.dart';
```

Inside `downloadServiceProvider`, replace `debounceTimer`, `pendingPlaylistIds`, `pendingCategoryPaths`, `categoriesNeedRefresh`, and `flushInvalidations()` with:

```dart
  final eventHandler = DownloadEventHandler(
    markFileExisting: ref.read(fileExistsCacheProvider.notifier).markAsExisting,
    removeProgress: progressState.remove,
    invalidateCategories: () => ref.invalidate(downloadedCategoriesProvider),
    invalidateCategoryTracks: (categoryPath) {
      ref.invalidate(downloadedCategoryTracksProvider(categoryPath));
    },
    refreshPlaylist: (playlistId) {
      final notifier = ref.read(playlistDetailProvider(playlistId).notifier);
      notifier.refreshTracks();
    },
    showFailure: (event) {
      ref.read(toastServiceProvider).showError(
            t.library.downloadFailed(title: event.trackTitle),
          );
    },
    debounceDuration: DebounceDurations.standard,
  );
```

Replace the completion subscription body with:

```dart
  completionSubscription = service.completionStream.listen(
    eventHandler.handleCompletion,
  );
```

Replace the failure subscription body with:

```dart
  failureSubscription = service.failureStream.listen(eventHandler.handleFailure);
```

In `ref.onDispose`, replace `debounceTimer?.cancel();` with:

```dart
    eventHandler.dispose();
```

- [ ] **Step 5: Verify and commit**

Run: `dart format lib/providers/download/download_event_handler.dart lib/providers/download/download_providers.dart test/providers/download/download_event_handler_test.dart`
Expected: files are formatted.

Run: `flutter test test/providers/download/download_event_handler_test.dart test/providers/download_providers_phase2_test.dart`
Expected: all tests pass.

Run: `git add lib/providers/download/download_event_handler.dart lib/providers/download/download_providers.dart test/providers/download/download_event_handler_test.dart && git commit -m "refactor(download): extract provider event handling"`
Expected: commit succeeds.

---

### Task 6: Extract Remote Playlist Removal Service

**Files:**
- Create: `lib/services/library/remote_playlist_actions_service.dart`
- Modify: `lib/providers/account_provider.dart:113-118`
- Modify: `lib/ui/pages/library/playlist_detail_page.dart:636-738` and `lib/ui/pages/library/playlist_detail_page.dart:1668-1755`
- Test: `test/services/library/remote_playlist_actions_service_test.dart`

- [ ] **Step 1: Write service tests for platform-specific removal**

Create `test/services/library/remote_playlist_actions_service_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/models/track.dart';
import 'package:fmp/data/sources/base_source.dart';
import 'package:fmp/services/library/remote_playlist_actions_service.dart';

void main() {
  group('RemotePlaylistActionsService', () {
    test('batch bilibili removal filters tracks and uses parsed folder id', () async {
      final aidsRequested = <String>[];
      final batchCalls = <({int folderId, List<int> videoAids})>[];
      final service = _service(
        getBilibiliAid: (track) async {
          aidsRequested.add(track.sourceId);
          return int.parse(track.sourceId.replaceFirst('BV', ''));
        },
        removeBilibiliTracks: ({required folderId, required videoAids}) async {
          batchCalls.add((folderId: folderId, videoAids: videoAids));
        },
      );

      await service.removeTracksFromRemote(
        sourceUrl: 'https://space.bilibili.com/1/favlist?fid=456',
        importSourceType: SourceType.bilibili,
        tracks: [_track(SourceType.bilibili, 'BV101'), _track(SourceType.youtube, 'yt-1')],
      );

      expect(aidsRequested, ['BV101']);
      expect(batchCalls.single.folderId, 456);
      expect(batchCalls.single.videoAids, [101]);
    });

    test('single bilibili removal uses update favorite callback', () async {
      final singleCalls = <({int videoAid, int folderId})>[];
      final service = _service(
        getBilibiliAid: (_) async => 202,
        removeBilibiliTrack: ({required videoAid, required folderId}) async {
          singleCalls.add((videoAid: videoAid, folderId: folderId));
        },
      );

      await service.removeTrackFromRemote(
        sourceUrl: 'https://space.bilibili.com/1/favlist?fid=789',
        importSourceType: SourceType.bilibili,
        track: _track(SourceType.bilibili, 'BV202'),
      );

      expect(singleCalls.single.videoAid, 202);
      expect(singleCalls.single.folderId, 789);
    });

    test('youtube removal skips tracks without setVideoId', () async {
      final removed = <String>[];
      final service = _service(
        getYoutubeSetVideoId: (playlistId, videoId) async =>
            videoId == 'yt-keep' ? 'set-1' : null,
        removeYoutubeTrack: (playlistId, videoId, setVideoId) async {
          removed.add('$playlistId:$videoId:$setVideoId');
        },
      );

      await service.removeTracksFromRemote(
        sourceUrl: 'https://www.youtube.com/playlist?list=PL123',
        importSourceType: SourceType.youtube,
        tracks: [_track(SourceType.youtube, 'yt-keep'), _track(SourceType.youtube, 'yt-missing')],
      );

      expect(removed, ['PL123:yt-keep:set-1']);
    });

    test('netease removal sends normalized source ids', () async {
      final calls = <({String playlistId, List<String> trackIds})>[];
      final service = _service(
        removeNeteaseTracks: (playlistId, trackIds) async {
          calls.add((playlistId: playlistId, trackIds: trackIds));
        },
      );

      await service.removeTracksFromRemote(
        sourceUrl: 'https://music.163.com/#/playlist?id=9988',
        importSourceType: SourceType.netease,
        tracks: [_track(SourceType.netease, '100'), _track(SourceType.netease, '200')],
      );

      expect(calls.single.playlistId, '9988');
      expect(calls.single.trackIds, ['100', '200']);
    });
  });
}

Track _track(SourceType sourceType, String sourceId) {
  return Track()
    ..sourceType = sourceType
    ..sourceId = sourceId
    ..title = sourceId
    ..artist = 'Artist';
}

RemotePlaylistActionsService _service({
  Future<int> Function(Track track)? getBilibiliAid,
  Future<void> Function({required int folderId, required List<int> videoAids})?
      removeBilibiliTracks,
  Future<void> Function({required int videoAid, required int folderId})?
      removeBilibiliTrack,
  Future<String?> Function(String playlistId, String videoId)? getYoutubeSetVideoId,
  Future<void> Function(String playlistId, String videoId, String setVideoId)?
      removeYoutubeTrack,
  Future<void> Function(String playlistId, List<String> trackIds)? removeNeteaseTracks,
}) {
  return RemotePlaylistActionsService(
    getBilibiliAid: getBilibiliAid ?? (_) async => 1,
    removeBilibiliTracks:
        removeBilibiliTracks ?? ({required folderId, required videoAids}) async {},
    removeBilibiliTrack:
        removeBilibiliTrack ?? ({required videoAid, required folderId}) async {},
    getYoutubeSetVideoId: getYoutubeSetVideoId ?? (_, __) async => null,
    removeYoutubeTrack: removeYoutubeTrack ?? (_, __, ___) async {},
    removeNeteaseTracks: removeNeteaseTracks ?? (_, __) async {},
  );
}
```

- [ ] **Step 2: Run the service test to verify it fails**

Run: `flutter test test/services/library/remote_playlist_actions_service_test.dart`
Expected: FAIL because `remote_playlist_actions_service.dart` does not exist.

- [ ] **Step 3: Add the remote playlist actions service**

Create `lib/services/library/remote_playlist_actions_service.dart`:

```dart
import '../../data/models/track.dart';
import '../../data/sources/bilibili_source.dart';

class RemotePlaylistActionsService {
  RemotePlaylistActionsService({
    required Future<int> Function(Track track) getBilibiliAid,
    required Future<void> Function({
      required int folderId,
      required List<int> videoAids,
    }) removeBilibiliTracks,
    required Future<void> Function({
      required int videoAid,
      required int folderId,
    }) removeBilibiliTrack,
    required Future<String?> Function(String playlistId, String videoId)
        getYoutubeSetVideoId,
    required Future<void> Function(
      String playlistId,
      String videoId,
      String setVideoId,
    ) removeYoutubeTrack,
    required Future<void> Function(String playlistId, List<String> trackIds)
        removeNeteaseTracks,
  })  : _getBilibiliAid = getBilibiliAid,
        _removeBilibiliTracks = removeBilibiliTracks,
        _removeBilibiliTrack = removeBilibiliTrack,
        _getYoutubeSetVideoId = getYoutubeSetVideoId,
        _removeYoutubeTrack = removeYoutubeTrack,
        _removeNeteaseTracks = removeNeteaseTracks;

  final Future<int> Function(Track track) _getBilibiliAid;
  final Future<void> Function({
    required int folderId,
    required List<int> videoAids,
  }) _removeBilibiliTracks;
  final Future<void> Function({
    required int videoAid,
    required int folderId,
  }) _removeBilibiliTrack;
  final Future<String?> Function(String playlistId, String videoId)
      _getYoutubeSetVideoId;
  final Future<void> Function(String playlistId, String videoId, String setVideoId)
      _removeYoutubeTrack;
  final Future<void> Function(String playlistId, List<String> trackIds)
      _removeNeteaseTracks;

  Future<void> removeTrackFromRemote({
    required String sourceUrl,
    required SourceType importSourceType,
    required Track track,
  }) async {
    switch (importSourceType) {
      case SourceType.bilibili:
        if (track.sourceType != SourceType.bilibili) return;
        final folderId = _parseBilibiliFolderId(sourceUrl);
        if (folderId == null) return;
        final aid = await _getBilibiliAid(track);
        await _removeBilibiliTrack(videoAid: aid, folderId: folderId);
      case SourceType.youtube:
        if (track.sourceType != SourceType.youtube) return;
        final playlistId = parseYoutubePlaylistId(sourceUrl);
        if (playlistId == null) return;
        final setVideoId = await _getYoutubeSetVideoId(playlistId, track.sourceId);
        if (setVideoId == null) return;
        await _removeYoutubeTrack(playlistId, track.sourceId, setVideoId);
      case SourceType.netease:
        if (track.sourceType != SourceType.netease) return;
        final playlistId = parseNeteasePlaylistId(sourceUrl);
        if (playlistId == null) return;
        await _removeNeteaseTracks(playlistId, [track.sourceId]);
    }
  }

  Future<void> removeTracksFromRemote({
    required String sourceUrl,
    required SourceType importSourceType,
    required List<Track> tracks,
  }) async {
    switch (importSourceType) {
      case SourceType.bilibili:
        final folderId = _parseBilibiliFolderId(sourceUrl);
        if (folderId == null) return;
        final biliTracks = tracks
            .where((track) => track.sourceType == SourceType.bilibili)
            .toList();
        final aids = <int>[];
        for (final track in biliTracks) {
          aids.add(await _getBilibiliAid(track));
        }
        if (aids.isEmpty) return;
        await _removeBilibiliTracks(folderId: folderId, videoAids: aids);
      case SourceType.youtube:
        final playlistId = parseYoutubePlaylistId(sourceUrl);
        if (playlistId == null) return;
        final ytTracks = tracks.where((track) => track.sourceType == SourceType.youtube);
        for (final track in ytTracks) {
          final setVideoId = await _getYoutubeSetVideoId(playlistId, track.sourceId);
          if (setVideoId != null) {
            await _removeYoutubeTrack(playlistId, track.sourceId, setVideoId);
          }
        }
      case SourceType.netease:
        final playlistId = parseNeteasePlaylistId(sourceUrl);
        if (playlistId == null) return;
        final trackIds = tracks
            .where((track) => track.sourceType == SourceType.netease)
            .map((track) => track.sourceId)
            .toList();
        if (trackIds.isEmpty) return;
        await _removeNeteaseTracks(playlistId, trackIds);
    }
  }

  int? _parseBilibiliFolderId(String sourceUrl) {
    final id = BilibiliSource.parseFavoritesId(sourceUrl);
    return id == null ? null : int.tryParse(id);
  }

  String? parseYoutubePlaylistId(String url) {
    final uri = Uri.tryParse(url);
    return uri?.queryParameters['list'];
  }

  String? parseNeteasePlaylistId(String url) {
    final uri = Uri.tryParse(url);
    final id = uri?.queryParameters['id'];
    if (id != null) return id;
    final match = RegExp(r'/playlist[?/].*?(\d{5,})').firstMatch(url);
    return match?.group(1);
  }
}
```

- [ ] **Step 4: Add the provider**

In `lib/providers/account_provider.dart`, import the service:

```dart
import '../services/library/remote_playlist_actions_service.dart';
```

Add this provider after `neteasePlaylistServiceProvider`:

```dart
final remotePlaylistActionsServiceProvider =
    Provider<RemotePlaylistActionsService>((ref) {
  final bilibiliService = ref.watch(bilibiliFavoritesServiceProvider);
  final youtubeService = ref.watch(youtubePlaylistServiceProvider);
  final neteaseService = ref.watch(neteasePlaylistServiceProvider);

  return RemotePlaylistActionsService(
    getBilibiliAid: bilibiliService.getVideoAid,
    removeBilibiliTracks: ({required folderId, required videoAids}) {
      return bilibiliService.batchRemoveFromFolder(
        folderId: folderId,
        videoAids: videoAids,
      );
    },
    removeBilibiliTrack: ({required videoAid, required folderId}) {
      return bilibiliService.updateVideoFavorites(
        videoAid: videoAid,
        removeFolderIds: [folderId],
      );
    },
    getYoutubeSetVideoId: youtubeService.getSetVideoId,
    removeYoutubeTrack: youtubeService.removeFromPlaylist,
    removeNeteaseTracks: neteaseService.removeTracksFromPlaylist,
  );
});
```

- [ ] **Step 5: Use the service from playlist detail page**

In `_confirmAndBatchRemoveFromRemote`, replace the full `switch (sourceType) { ... }` block with:

```dart
      final remoteActions = ref.read(remotePlaylistActionsServiceProvider);
      await remoteActions.removeTracksFromRemote(
        sourceUrl: sourceUrl,
        importSourceType: sourceType,
        tracks: tracks,
      );
```

In `_confirmAndRemoveFromRemote`, replace the full `switch (sourceType) { ... }` block with:

```dart
      final remoteActions = ref.read(remotePlaylistActionsServiceProvider);
      await remoteActions.removeTrackFromRemote(
        sourceUrl: sourceUrl,
        importSourceType: sourceType,
        track: track,
      );
```

Remove the private helpers `_parseYoutubePlaylistId` and `_parseNeteasePlaylistId` from `playlist_detail_page.dart` after the single-track removal method, because parsing now lives in `RemotePlaylistActionsService`.

Remove `import '../../../data/sources/bilibili_source.dart';` from `playlist_detail_page.dart` if no remaining references use it.

- [ ] **Step 6: Verify and commit**

Run: `dart format lib/services/library/remote_playlist_actions_service.dart lib/providers/account_provider.dart lib/ui/pages/library/playlist_detail_page.dart test/services/library/remote_playlist_actions_service_test.dart`
Expected: files are formatted.

Run: `flutter test test/services/library/remote_playlist_actions_service_test.dart`
Expected: all tests pass.

Run: `flutter analyze`
Expected: no issues.

Run: `git add lib/services/library/remote_playlist_actions_service.dart lib/providers/account_provider.dart lib/ui/pages/library/playlist_detail_page.dart test/services/library/remote_playlist_actions_service_test.dart && git commit -m "refactor(library): extract remote playlist actions"`
Expected: commit succeeds.

---

### Task 7: Add Bounded Negative Caching to FileExistsCache

**Files:**
- Modify: `lib/providers/download/file_exists_cache.dart`
- Test: `test/providers/download/file_exists_cache_phase4_test.dart`

- [ ] **Step 1: Add negative-cache tests**

Append these tests to `test/providers/download/file_exists_cache_phase4_test.dart` inside the existing group:

```dart
    test('missing paths are cached to avoid repeated refresh scheduling', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'file_exists_cache_missing_'
      );
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });
      final missingPath = '${tempDir.path}/missing_cover.jpg';
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final cache = container.read(fileExistsCacheProvider.notifier);

      expect(cache.exists(missingPath), isFalse);
      await _waitForCondition(() => cache.debugMissingPathCount == 1);

      expect(cache.getFirstExisting([missingPath]), isNull);
      expect(cache.pendingRefreshCount, 0);
      expect(cache.exists(missingPath), isFalse);
      expect(cache.debugMissingPathCount, 1);
    });

    test('markAsExisting clears a previous missing-path cache entry', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'file_exists_cache_missing_to_existing_'
      );
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });
      final path = '${tempDir.path}/cover.jpg';
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final cache = container.read(fileExistsCacheProvider.notifier);

      expect(cache.exists(path), isFalse);
      await _waitForCondition(() => cache.debugMissingPathCount == 1);

      cache.markAsExisting(path);

      expect(cache.debugMissingPathCount, 0);
      expect(container.read(filePathExistsProvider(path)), isTrue);
    });

    test('missing path cache is bounded', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final cache = container.read(fileExistsCacheProvider.notifier);

      for (var i = 0; i < 6000; i++) {
        cache.debugMarkMissingForTesting('/missing/$i.jpg');
      }

      expect(cache.debugMissingPathCount, 5000);
    });
```

- [ ] **Step 2: Run the negative-cache tests to verify they fail**

Run: `flutter test test/providers/download/file_exists_cache_phase4_test.dart --plain-name "missing paths are cached to avoid repeated refresh scheduling"`
Expected: FAIL because `debugMissingPathCount` does not exist.

- [ ] **Step 3: Implement bounded missing-path cache**

In `lib/providers/download/file_exists_cache.dart`, add these fields after `_pendingRefreshPaths`:

```dart
  final Set<String> _missingPaths = <String>{};
```

Add this constant after `_maxCacheSize`:

```dart
  static const int _maxMissingCacheSize = 5000;
```

Add these testing/debug accessors after `cacheEpoch`:

```dart
  int get debugMissingPathCount => _missingPaths.length;

  void debugMarkMissingForTesting(String path) {
    _markAsMissing(path);
  }
```

Change `exists` to:

```dart
  bool exists(String path) {
    if (state.contains(path)) return true;
    if (_missingPaths.contains(path)) return false;

    _checkAndCache(path);
    return false;
  }
```

Change `preloadPaths` first line to:

```dart
    final uncached = paths
        .toSet()
        .difference(state)
        .difference(_missingPaths)
        .toList();
```

Change `markAsExisting` to:

```dart
  void markAsExisting(String path) {
    _missingPaths.remove(path);
    if (state.contains(path)) return;
    _updateState({...state, path});
  }
```

Change `remove` to:

```dart
  void remove(String path) {
    _missingPaths.remove(path);
    if (!state.contains(path)) return;
    final newState = Set<String>.from(state)..remove(path);
    _updateState(newState);
  }
```

Change `clearAll` to:

```dart
  void clearAll() {
    final hadEntries = state.isNotEmpty || _missingPaths.isNotEmpty;
    _missingPaths.clear();
    if (!hadEntries) return;
    _updateState(<String>{});
  }
```

Add this helper after `_trimToMaxSize`:

```dart
  Set<String> _trimMissingToMaxSize(Set<String> paths) {
    if (paths.length <= _maxMissingCacheSize) {
      return paths;
    }

    final trimmed = Set<String>.from(paths);
    final toRemove = trimmed.length - _maxMissingCacheSize;
    final keysToRemove = trimmed.take(toRemove).toList();
    trimmed.removeAll(keysToRemove);
    return trimmed;
  }

  void _markAsMissing(String path) {
    if (_missingPaths.contains(path)) return;
    _missingPaths
      ..add(path)
      ..removeAll(state);
    final trimmed = _trimMissingToMaxSize(_missingPaths);
    if (!identical(trimmed, _missingPaths)) {
      _missingPaths
        ..clear()
        ..addAll(trimmed);
    }
  }
```

In `_checkAndCache`, replace the `if (await File(path).exists())` block with:

```dart
          if (await File(path).exists()) {
            markAsExisting(path);
          } else {
            _markAsMissing(path);
          }
```

In `_scheduleRefreshPaths`, replace the `uncached` calculation with:

```dart
    final uncached = paths
        .where((path) => !state.contains(path) && !_missingPaths.contains(path))
        .toSet();
```

Inside the refresh loop, replace the `if (await File(path).exists())` block with:

```dart
              if (await File(path).exists()) {
                existing.add(path);
              } else {
                _markAsMissing(path);
              }
```

At the end of `_scheduleRefreshPaths`, replace `_updateState({...state, ...existing});` with:

```dart
          for (final path in existing) {
            _missingPaths.remove(path);
          }
          _updateState({...state, ...existing});
```

In `preloadPaths`, after the results loop, add missing results:

```dart
        if (!result.exists) {
          _markAsMissing(result.path);
        }
```

- [ ] **Step 4: Verify and commit**

Run: `dart format lib/providers/download/file_exists_cache.dart test/providers/download/file_exists_cache_phase4_test.dart`
Expected: files are formatted.

Run: `flutter test test/providers/download/file_exists_cache_phase4_test.dart`
Expected: all tests pass.

Run: `git add lib/providers/download/file_exists_cache.dart test/providers/download/file_exists_cache_phase4_test.dart && git commit -m "perf(download): cache missing file paths"`
Expected: commit succeeds.

---

### Task 8: Final Phase 2 Validation

**Files:**
- Inspect: `docs/superpowers/specs/2026-04-24-review-driven-refactor-design.md`
- Inspect: `CLAUDE.md`

- [ ] **Step 1: Run focused Phase 2 tests**

Run:

```bash
flutter test \
  test/services/download/download_media_headers_test.dart \
  test/services/import/playlist_import_service_test.dart \
  test/services/lyrics/lyrics_auto_match_service_phase4_test.dart \
  test/services/audio/playback_request_executor_test.dart \
  test/providers/download/download_event_handler_test.dart \
  test/services/library/remote_playlist_actions_service_test.dart \
  test/providers/download/file_exists_cache_phase4_test.dart
```

Expected: all tests pass.

- [ ] **Step 2: Run static analysis**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 3: Run the full test suite**

Run: `flutter test`
Expected: all tests pass.

- [ ] **Step 4: Decide whether docs need updates**

Read `CLAUDE.md` sections `Download System`, `Lyrics System`, and `UI Development Guidelines`.
Expected: no update is required unless implementation changed a documented project rule. If an implementation step changed a documented rule, update only the affected bullet and run `git add CLAUDE.md && git commit -m "docs: update phase 2 refactor notes"`.

- [ ] **Step 5: Record Phase 2 scope adjustments for the next phase**

In the final implementation report, state:

```markdown
Phase 2 completed the remaining logic-unification items except search history, which was already completed in Phase 1. Phase 3 should re-evaluate data transaction boundaries and queue/performance split work against the new tests before implementation.
```

Expected: report includes the scope adjustment and the validation command results.

---

## Self-Review

- Spec coverage: covers Phase 2 candidates from the design spec except `searchHistoryProvider`, which Phase 1 already completed. Adds the Phase 2-adjacent tests recommended by the testing review for lyrics direct fetch, provider completion/failure glue, and local-file handoff.
- Placeholder scan: no TBD markers or open-ended implementation placeholders remain; every code-changing step includes concrete snippets and commands.
- Type consistency: `buildDownloadMediaHeaders`, `DownloadEventHandler`, and `RemotePlaylistActionsService` names are consistent across tests, providers, and service code.
- Scope check: no database schema changes, unique indexes, playlist/track atomic transaction refactors, or audio architecture rewrites are included.
