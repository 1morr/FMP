# Refresh Partial Failure Policy Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prevent imported playlist refresh from deleting local tracks when the upstream playlist data or per-track persistence is partial.

**Architecture:** Keep Phase 0 narrow: add protective tests around `ImportService.refreshPlaylist()`, then change only refresh commit/prune behavior. A refresh may prune removed tracks only when the parsed remote result is complete and every refreshed track was persisted successfully; partial refreshes may append fully saved new tracks but must preserve existing local membership.

**Tech Stack:** Flutter, Dart, Isar, Riverpod-adjacent services, `flutter_test`.

---

## File structure

- Create: `test/services/import/import_service_refresh_partial_test.dart`
  - Focused service tests for refresh partial data and persistence failures.
  - Uses a real temporary Isar database plus fake `BaseSource` / `BilibiliSource` implementations.
- Modify: `lib/services/import/import_service.dart`
  - Add `ImportResult.pruningSkipped`.
  - Add helper logic for deciding whether refresh may prune local tracks.
  - Preserve original playlist membership when pruning is skipped.
  - Track Bilibili multi-page expansion fallback as a partial refresh condition.

## Refresh policy for this phase

- Complete refresh: parsed remote result is complete and no per-track persistence errors occur. The playlist may replace `trackIds` with the refreshed order and prune old local tracks absent from remote.
- Partial refresh from source data: parsed remote result says more tracks exist than were returned, or Bilibili multi-page expansion falls back after an error. The playlist must not prune old local tracks.
- Partial refresh from persistence: one or more tracks fail lookup/save during refresh. The playlist must not prune old local tracks.
- Partial additions: fully resolved and saved new tracks may be appended to the existing local playlist when pruning is skipped.

### Task 1: Add failing tests for incomplete source data and per-track save failure

**Files:**
- Create: `test/services/import/import_service_refresh_partial_test.dart`
- Modify: none
- Test: `test/services/import/import_service_refresh_partial_test.dart`

- [ ] **Step 1: Create the failing test file**

Create `test/services/import/import_service_refresh_partial_test.dart` with this content:

```dart
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/models/playlist.dart';
import 'package:fmp/data/models/track.dart';
import 'package:fmp/data/repositories/playlist_repository.dart';
import 'package:fmp/data/repositories/track_repository.dart';
import 'package:fmp/data/sources/base_source.dart';
import 'package:fmp/data/sources/source_provider.dart';
import 'package:fmp/services/import/import_service.dart';
import 'package:isar/isar.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ImportService refresh partial failure policy', () {
    late Directory tempDir;
    late Isar isar;
    late PlaylistRepository playlistRepository;

    setUpAll(() async {
      await Isar.initializeIsarCore(
        libraries: {Abi.current(): await _resolveIsarLibraryPath()},
      );
    });

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp(
        'import_service_refresh_partial_',
      );
      isar = await Isar.open(
        [PlaylistSchema, TrackSchema],
        directory: tempDir.path,
        name: 'import_service_refresh_partial_test',
      );
      playlistRepository = PlaylistRepository(isar);
    });

    tearDown(() async {
      await isar.close(deleteFromDisk: true);
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('skips pruning when a refreshed track fails to save', () async {
      final trackRepository = _FailingSaveTrackRepository(isar);
      final playlist = await _createImportedPlaylist(playlistRepository);
      final keep = await _saveExistingTrack(trackRepository, playlist, 'keep');
      final old = await _saveExistingTrack(trackRepository, playlist, 'old');
      playlist.trackIds = [keep.id, old.id];
      await playlistRepository.save(playlist);

      final source = _FakeRefreshSource(
        tracks: [
          _track('keep'),
          _track('new'),
          _track('broken'),
        ],
        totalCount: 3,
      );
      final service = ImportService(
        sourceManager: _FakeSourceManager(source),
        playlistRepository: playlistRepository,
        trackRepository: trackRepository,
        isar: isar,
      );

      final result = await service.refreshPlaylist(playlist.id);

      final newTrack = await trackRepository.getBySourceIdAndCid(
        'new',
        SourceType.youtube,
      );
      final savedPlaylist = await playlistRepository.getById(playlist.id);
      final oldTrack = await trackRepository.getById(old.id);

      expect(result.pruningSkipped, isTrue);
      expect(result.removedCount, 0);
      expect(result.errors, hasLength(1));
      expect(newTrack, isNotNull);
      expect(savedPlaylist!.trackIds, [keep.id, old.id, newTrack!.id]);
      expect(oldTrack!.belongsToPlaylist(playlist.id), isTrue);
    });

    test('skips pruning when source result is smaller than reported total',
        () async {
      final trackRepository = TrackRepository(isar);
      final playlist = await _createImportedPlaylist(playlistRepository);
      final keep = await _saveExistingTrack(trackRepository, playlist, 'keep');
      final old = await _saveExistingTrack(trackRepository, playlist, 'old');
      playlist.trackIds = [keep.id, old.id];
      await playlistRepository.save(playlist);

      final source = _FakeRefreshSource(
        tracks: [_track('keep')],
        totalCount: 2,
      );
      final service = ImportService(
        sourceManager: _FakeSourceManager(source),
        playlistRepository: playlistRepository,
        trackRepository: trackRepository,
        isar: isar,
      );

      final result = await service.refreshPlaylist(playlist.id);

      final savedPlaylist = await playlistRepository.getById(playlist.id);
      final oldTrack = await trackRepository.getById(old.id);

      expect(result.pruningSkipped, isTrue);
      expect(result.removedCount, 0);
      expect(result.errors, isEmpty);
      expect(savedPlaylist!.trackIds, [keep.id, old.id]);
      expect(oldTrack!.belongsToPlaylist(playlist.id), isTrue);
    });
  });
}
```

- [ ] **Step 2: Append the shared test helpers**

Append this helper code to the same file:

```dart
class _FakeSourceManager extends SourceManager {
  _FakeSourceManager(this.source) : super();

  final BaseSource source;

  @override
  BaseSource? detectSource(String url) => source;

  @override
  void dispose() {}
}

class _FakeRefreshSource extends BaseSource {
  _FakeRefreshSource({required this.tracks, required this.totalCount});

  final List<Track> tracks;
  final int totalCount;

  @override
  SourceType get sourceType => SourceType.youtube;

  @override
  Future<PlaylistParseResult> parsePlaylist(
    String playlistUrl, {
    int page = 1,
    int pageSize = 20,
    Map<String, String>? authHeaders,
  }) async {
    return PlaylistParseResult(
      title: 'Remote Playlist',
      tracks: tracks.map((track) => track.copy()).toList(),
      totalCount: totalCount,
      sourceUrl: playlistUrl,
    );
  }

  @override
  String? parseId(String url) => url;

  @override
  bool isValidId(String id) => true;

  @override
  bool isPlaylistUrl(String url) => true;

  @override
  Future<bool> checkAvailability(String sourceId) async => true;

  @override
  Future<AudioStreamResult> getAudioStream(
    String sourceId, {
    AudioStreamConfig config = AudioStreamConfig.defaultConfig,
    Map<String, String>? authHeaders,
  }) async {
    return const AudioStreamResult(
      url: 'https://example.com/audio.m4a',
      streamType: StreamType.audioOnly,
    );
  }

  @override
  Future<Track> getTrackInfo(
    String sourceId, {
    Map<String, String>? authHeaders,
  }) async {
    return _track(sourceId);
  }

  @override
  Future<Track> refreshAudioUrl(
    Track track, {
    Map<String, String>? authHeaders,
  }) async {
    return track;
  }

  @override
  Future<SearchResult> search(
    String query, {
    int page = 1,
    int pageSize = 20,
    SearchOrder order = SearchOrder.relevance,
  }) async {
    return SearchResult.empty();
  }
}

class _FailingSaveTrackRepository extends TrackRepository {
  _FailingSaveTrackRepository(Isar isar) : super(isar);

  @override
  Future<Track> save(Track track) {
    if (track.sourceId == 'broken') {
      throw StateError('save failed for broken');
    }
    return super.save(track);
  }
}

Future<Playlist> _createImportedPlaylist(
  PlaylistRepository playlistRepository,
) async {
  final playlist = Playlist()
    ..name = 'Imported Playlist'
    ..sourceUrl = 'https://example.com/playlist'
    ..importSourceType = SourceType.youtube;
  playlist.id = await playlistRepository.save(playlist);
  return playlist;
}

Future<Track> _saveExistingTrack(
  TrackRepository trackRepository,
  Playlist playlist,
  String sourceId,
) async {
  final track = _track(sourceId)..addToPlaylist(playlist.id, playlistName: playlist.name);
  return trackRepository.save(track);
}

Track _track(String sourceId) {
  return Track()
    ..sourceId = sourceId
    ..sourceType = SourceType.youtube
    ..title = 'Track $sourceId'
    ..artist = 'Tester';
}

Future<String> _resolveIsarLibraryPath() async {
  final packageConfigFile = File(
    '${Directory.current.path}/.dart_tool/package_config.json',
  );
  final packageConfig = jsonDecode(await packageConfigFile.readAsString())
      as Map<String, dynamic>;
  final packages = packageConfig['packages'] as List<dynamic>;
  final packageConfigDir = Directory('${Directory.current.path}/.dart_tool');

  for (final package in packages) {
    if (package is! Map<String, dynamic> ||
        package['name'] != 'isar_flutter_libs') {
      continue;
    }
    final packageDir = Directory(
      packageConfigDir.uri.resolve(package['rootUri'] as String).toFilePath(),
    );
    if (Platform.isWindows) return '${packageDir.path}/windows/isar.dll';
    if (Platform.isLinux) return '${packageDir.path}/linux/libisar.so';
    if (Platform.isMacOS) return '${packageDir.path}/macos/libisar.dylib';
  }

  throw StateError('Unsupported platform for Isar test setup');
}
```

- [ ] **Step 3: Run the new tests and verify they fail**

Run:

```bash
flutter test test/services/import/import_service_refresh_partial_test.dart
```

Expected: FAIL. At minimum, the compiler should report that `ImportResult` has no getter named `pruningSkipped`. If the getter is added before running this task, the tests should fail because the current implementation prunes `old` when refresh results are partial.

- [ ] **Step 4: Keep the test file staged only after Task 2**

Do not commit while the test suite does not compile or while the new tests are failing. Keep `test/services/import/import_service_refresh_partial_test.dart` in the working tree so Task 2 can add the minimal production API needed to move from compile failure to behavioral failure.

### Task 2: Add refresh completeness reporting to `ImportResult`

**Files:**
- Modify: `lib/services/import/import_service.dart:63-78`
- Test: `test/services/import/import_service_refresh_partial_test.dart`

- [ ] **Step 1: Add the failing expectation already present in Task 1**

The tests from Task 1 already expect:

```dart
expect(result.pruningSkipped, isTrue);
```

- [ ] **Step 2: Add `pruningSkipped` to `ImportResult`**

In `lib/services/import/import_service.dart`, replace the `ImportResult` class with:

```dart
/// 导入结果
class ImportResult {
  final Playlist playlist;
  final int addedCount;
  final int skippedCount;
  final int removedCount;
  final List<String> errors;
  final bool pruningSkipped;

  const ImportResult({
    required this.playlist,
    required this.addedCount,
    required this.skippedCount,
    this.removedCount = 0,
    required this.errors,
    this.pruningSkipped = false,
  });
}
```

This is backward-compatible for existing call sites because the new field has a default.

- [ ] **Step 3: Run tests and verify they still fail behaviorally**

Run:

```bash
flutter test test/services/import/import_service_refresh_partial_test.dart
```

Expected: FAIL. The compiler error should be gone. The failure should now show `pruningSkipped` is false or `old` was removed from the playlist.

- [ ] **Step 4: Commit the tests and result field together**

```bash
git add lib/services/import/import_service.dart test/services/import/import_service_refresh_partial_test.dart
git commit -m "test(import): cover partial refresh pruning policy"
```

### Task 3: Skip pruning when parsed source data is incomplete

**Files:**
- Modify: `lib/services/import/import_service.dart:461-612`
- Test: `test/services/import/import_service_refresh_partial_test.dart`

- [ ] **Step 1: Add source completeness detection after expansion**

In `ImportService.refreshPlaylist()`, immediately after `expandedTracks` is assigned and `_throwIfCancelled();` is called, add:

```dart
      final sourceDataComplete = result.totalCount <= 0 ||
          expandedTracks.length >= result.totalCount;
```

The surrounding section should become:

```dart
      } else {
        expandedTracks = result.tracks;
      }
      _throwIfCancelled();

      final sourceDataComplete = result.totalCount <= 0 ||
          expandedTracks.length >= result.totalCount;

      _updateProgress(
        status: ImportStatus.importing,
        total: expandedTracks.length,
        current: 0,
      );
```

- [ ] **Step 2: Track persistence completeness before removal calculation**

After the refresh loop ends, before `_throwIfCancelled();`, add:

```dart
      final persistenceComplete = errors.isEmpty;
      final canPruneRemovedTracks = sourceDataComplete && persistenceComplete;
```

The section should become:

```dart
      for (int i = 0; i < expandedTracks.length; i++) {
        _throwIfCancelled();
        final track = expandedTracks[i];

        _updateProgress(
          current: i + 1,
          currentItem: track.title,
        );

        try {
          // existing track persistence logic remains unchanged for now
        } catch (e) {
          if (_isCancelled) rethrow;
          errors.add('${track.title}: ${e.toString()}');
        }
      }

      final persistenceComplete = errors.isEmpty;
      final canPruneRemovedTracks = sourceDataComplete && persistenceComplete;

      _throwIfCancelled();
```

- [ ] **Step 3: Replace removal calculation with prune gate**

Replace this block:

```dart
      // 计算被移除的歌曲（在原来列表中但不在新列表中的）
      final newTrackIdSet = Set<int>.from(newTrackIds);
      final removedTrackIds = originalTrackIds.difference(newTrackIdSet);
      final removedCount = removedTrackIds.length;
```

with:

```dart
      // 计算被移除的歌曲（只有完整刷新才允许 prune）
      final newTrackIdSet = Set<int>.from(newTrackIds);
      final removedTrackIds = canPruneRemovedTracks
          ? originalTrackIds.difference(newTrackIdSet)
          : <int>{};
      final removedCount = removedTrackIds.length;
      final pruningSkipped = !canPruneRemovedTracks;
```

- [ ] **Step 4: Preserve original membership when pruning is skipped**

Replace this block:

```dart
      // 更新歌单
      playlist.trackIds = newTrackIds;
      playlist.lastRefreshed = DateTime.now();
```

with:

```dart
      // 更新歌单。Partial refresh can append fully saved tracks, but must not
      // remove existing local membership based on incomplete remote data.
      playlist.trackIds = canPruneRemovedTracks
          ? newTrackIds
          : _mergePreservingExistingTrackOrder(
              playlist.trackIds,
              newTrackIds,
            );
      playlist.lastRefreshed = DateTime.now();
```

- [ ] **Step 5: Return `pruningSkipped`**

Replace the refresh return block with:

```dart
      return ImportResult(
        playlist: playlist,
        addedCount: addedCount,
        skippedCount: skippedCount,
        removedCount: removedCount,
        errors: errors,
        pruningSkipped: pruningSkipped,
      );
```

- [ ] **Step 6: Add the merge helper**

In `ImportService`, before `_throwIfCancelled()`, add:

```dart
  List<int> _mergePreservingExistingTrackOrder(
    List<int> existingTrackIds,
    List<int> refreshedTrackIds,
  ) {
    final merged = List<int>.from(existingTrackIds);
    final seen = merged.toSet();
    for (final trackId in refreshedTrackIds) {
      if (seen.add(trackId)) {
        merged.add(trackId);
      }
    }
    return merged;
  }
```

- [ ] **Step 7: Run the focused tests**

Run:

```bash
flutter test test/services/import/import_service_refresh_partial_test.dart
```

Expected: PASS for the two tests in Task 1.

- [ ] **Step 8: Commit incomplete-source prune protection**

```bash
git add lib/services/import/import_service.dart test/services/import/import_service_refresh_partial_test.dart
git commit -m "fix(import): skip pruning on partial refresh"
```

### Task 4: Mark Bilibili multi-page expansion fallback as partial

**Files:**
- Modify: `lib/services/import/import_service.dart:641-692`
- Test: `test/services/import/import_service_refresh_partial_test.dart`

- [ ] **Step 1: Add a Bilibili fallback test**

Add this test inside the existing group in `test/services/import/import_service_refresh_partial_test.dart`:

```dart
    test('skips pruning when Bilibili multipage expansion falls back', () async {
      final trackRepository = TrackRepository(isar);
      final playlist = await _createImportedPlaylist(
        playlistRepository,
        sourceType: SourceType.bilibili,
      );
      final keep = await _saveExistingTrack(
        trackRepository,
        playlist,
        'BV_KEEP',
        sourceType: SourceType.bilibili,
      );
      final old = await _saveExistingTrack(
        trackRepository,
        playlist,
        'BV_OLD',
        sourceType: SourceType.bilibili,
      );
      playlist.trackIds = [keep.id, old.id];
      await playlistRepository.save(playlist);

      final source = _FakeBilibiliRefreshSource(
        tracks: [
          _track(
            'BV_KEEP',
            sourceType: SourceType.bilibili,
            pageCount: 2,
          ),
        ],
        totalCount: 1,
        failVideoPages: true,
      );
      final service = ImportService(
        sourceManager: _FakeSourceManager(source),
        playlistRepository: playlistRepository,
        trackRepository: trackRepository,
        isar: isar,
      );

      final result = await service.refreshPlaylist(playlist.id);

      final savedPlaylist = await playlistRepository.getById(playlist.id);
      final oldTrack = await trackRepository.getById(old.id);

      expect(result.pruningSkipped, isTrue);
      expect(result.removedCount, 0);
      expect(savedPlaylist!.trackIds, [keep.id, old.id]);
      expect(oldTrack!.belongsToPlaylist(playlist.id), isTrue);
    });
```

- [ ] **Step 2: Update helpers to accept source type and page count**

Replace `_createImportedPlaylist`, `_saveExistingTrack`, and `_track` helpers with:

```dart
Future<Playlist> _createImportedPlaylist(
  PlaylistRepository playlistRepository, {
  SourceType sourceType = SourceType.youtube,
}) async {
  final playlist = Playlist()
    ..name = 'Imported Playlist'
    ..sourceUrl = 'https://example.com/playlist'
    ..importSourceType = sourceType;
  playlist.id = await playlistRepository.save(playlist);
  return playlist;
}

Future<Track> _saveExistingTrack(
  TrackRepository trackRepository,
  Playlist playlist,
  String sourceId, {
  SourceType sourceType = SourceType.youtube,
  int? pageCount,
  int? cid,
}) async {
  final track = _track(
    sourceId,
    sourceType: sourceType,
    pageCount: pageCount,
    cid: cid,
  )..addToPlaylist(playlist.id, playlistName: playlist.name);
  return trackRepository.save(track);
}

Track _track(
  String sourceId, {
  SourceType sourceType = SourceType.youtube,
  int? pageCount,
  int? cid,
}) {
  return Track()
    ..sourceId = sourceId
    ..sourceType = sourceType
    ..title = 'Track $sourceId'
    ..artist = 'Tester'
    ..pageCount = pageCount
    ..cid = cid;
}
```

- [ ] **Step 3: Add the fake Bilibili source helper**

Add these imports to the top of the test file:

```dart
import 'package:fmp/data/models/video_detail.dart';
import 'package:fmp/data/sources/bilibili_source.dart';
```

Then add this helper class near the other fake source classes:

```dart
class _FakeBilibiliRefreshSource extends BilibiliSource {
  _FakeBilibiliRefreshSource({
    required this.tracks,
    required this.totalCount,
    this.failVideoPages = false,
  });

  final List<Track> tracks;
  final int totalCount;
  final bool failVideoPages;

  @override
  SourceType get sourceType => SourceType.bilibili;

  @override
  Future<PlaylistParseResult> parsePlaylist(
    String playlistUrl, {
    int page = 1,
    int pageSize = 20,
    Map<String, String>? authHeaders,
  }) async {
    return PlaylistParseResult(
      title: 'Bilibili Playlist',
      tracks: tracks.map((track) => track.copy()).toList(),
      totalCount: totalCount,
      sourceUrl: playlistUrl,
    );
  }

  @override
  Future<List<VideoPage>> getVideoPages(
    String bvid, {
    Map<String, String>? authHeaders,
  }) async {
    if (failVideoPages) {
      throw StateError('video pages unavailable');
    }
    return const [
      VideoPage(cid: 101, page: 1, part: 'Part 1', duration: 180),
      VideoPage(cid: 102, page: 2, part: 'Part 2', duration: 181),
    ];
  }
}
```

- [ ] **Step 4: Run the Bilibili test and verify it fails**

Run:

```bash
flutter test test/services/import/import_service_refresh_partial_test.dart --plain-name "skips pruning when Bilibili multipage expansion falls back"
```

Expected: FAIL because `_expandMultiPageVideos()` currently swallows page expansion errors without reporting that the refresh is partial.

- [ ] **Step 5: Add an expansion result type inside `ImportService`**

In `lib/services/import/import_service.dart`, after the `ImportResult` class, add:

```dart
class _TrackExpansionResult {
  final List<Track> tracks;
  final bool isComplete;

  const _TrackExpansionResult({
    required this.tracks,
    required this.isComplete,
  });
}
```

- [ ] **Step 6: Change `_expandMultiPageVideos()` to return completeness**

Replace `_expandMultiPageVideos()` with:

```dart
  /// 展开多分P视频为独立Track
  Future<_TrackExpansionResult> _expandMultiPageVideos(
    BilibiliSource source,
    List<Track> tracks,
    void Function(int current, int total, String item) onProgress,
  ) async {
    final expandedTracks = <Track>[];
    var isComplete = true;

    // 统计多P视频数量用于进度显示
    final multiPageCount = tracks.where((t) => (t.pageCount ?? 0) > 1).length;
    int multiPageProcessed = 0;

    for (final track in tracks) {
      // 单P视频直接添加（cid 会在播放时通过 ensureAudioUrl 获取）
      if ((track.pageCount ?? 0) <= 1) {
        track.pageNum = 1;
        expandedTracks.add(track);
        continue;
      }

      // 多P视频需要获取详细分P信息
      multiPageProcessed++;
      onProgress(multiPageProcessed, multiPageCount, track.title);

      try {
        // 获取分P信息
        final pages = await source.getVideoPages(track.sourceId);

        if (pages.length <= 1) {
          // API 返回单P，直接添加
          if (pages.isNotEmpty) {
            track.cid = pages.first.cid;
            track.pageNum = 1;
          }
          expandedTracks.add(track);
        } else {
          // 多P视频，展开为独立Track
          for (final page in pages) {
            expandedTracks.add(page.toTrack(track));
          }
        }

        // 添加小延迟避免请求过快
        await Future.delayed(const Duration(milliseconds: 100));
      } catch (e) {
        isComplete = false;
        // 获取分P失败，直接添加原始track
        expandedTracks.add(track);
      }
    }

    return _TrackExpansionResult(
      tracks: expandedTracks,
      isComplete: isComplete,
    );
  }
```

- [ ] **Step 7: Update import path call site to unpack expansion result**

In `importFromUrl()`, replace the Bilibili expansion block with:

```dart
      // 获取分P信息并展开（仅Bilibili）
      final List<Track> expandedTracks;
      if (source is BilibiliSource) {
        final expansion = await _expandMultiPageVideos(
          source,
          result.tracks,
          (current, total, item) {
            _updateProgress(
              status: ImportStatus.importing,
              current: current,
              total: total,
              currentItem: t.importSource.gettingPageInfo(
                  current: current.toString(), total: total.toString()),
            );
          },
        );
        expandedTracks = expansion.tracks;
      } else {
        expandedTracks = result.tracks;
      }
```

Import does not need the completeness flag in Phase 0 because this plan protects refresh pruning only.

- [ ] **Step 8: Update refresh path call site to use expansion completeness**

In `refreshPlaylist()`, replace the Bilibili expansion block with:

```dart
      // 获取分P信息并展开（仅Bilibili）
      final List<Track> expandedTracks;
      final bool expansionComplete;
      if (source is BilibiliSource) {
        final expansion = await _expandMultiPageVideos(
          source,
          result.tracks,
          (current, total, item) {
            _throwIfCancelled();
            _updateProgress(
              status: ImportStatus.importing,
              current: current,
              total: total,
              currentItem: t.importSource.gettingPageInfo(
                  current: current.toString(), total: total.toString()),
            );
          },
        );
        expandedTracks = expansion.tracks;
        expansionComplete = expansion.isComplete;
      } else {
        expandedTracks = result.tracks;
        expansionComplete = true;
      }
      _throwIfCancelled();

      final sourceDataComplete = expansionComplete &&
          (result.totalCount <= 0 || expandedTracks.length >= result.totalCount);
```

- [ ] **Step 9: Run the focused tests**

Run:

```bash
flutter test test/services/import/import_service_refresh_partial_test.dart
```

Expected: PASS.

- [ ] **Step 10: Commit Bilibili expansion completeness**

```bash
git add lib/services/import/import_service.dart test/services/import/import_service_refresh_partial_test.dart
git commit -m "fix(import): treat Bilibili expansion fallback as partial"
```

### Task 5: Verify existing refresh/import behavior and analyze

**Files:**
- Modify: none unless tests reveal a regression
- Test: existing focused tests plus analyzer

- [ ] **Step 1: Run import service focused tests**

Run:

```bash
flutter test test/services/import/import_service_refresh_partial_test.dart test/services/import/import_service_phase4_test.dart
```

Expected: PASS.

- [ ] **Step 2: Run refresh provider stale cleanup tests**

Run:

```bash
flutter test test/providers/refresh_provider_stale_cleanup_test.dart
```

Expected: PASS. This ensures the new refresh pruning logic did not regress cancellation rollback behavior.

- [ ] **Step 3: Run static analysis**

Run:

```bash
flutter analyze
```

Expected: `No issues found!`

- [ ] **Step 4: Commit verification-only fixes if needed**

If any command fails because of the Phase 0 implementation, fix only the directly related issue, then run the failing command again. Commit with:

```bash
git add lib/services/import/import_service.dart test/services/import/import_service_refresh_partial_test.dart
git commit -m "fix(import): stabilize partial refresh policy"
```

If all commands pass without changes, do not create an empty commit.

## Self-review notes

- Spec coverage: This plan covers Phase 0 only, as requested by the approved roadmap. It defines the refresh policy, adds protective tests, makes minimal production changes, and includes verification commands.
- Placeholder scan: No `TBD`, `TODO`, or unspecified edge-case steps remain.
- Type consistency: `ImportResult.pruningSkipped`, `_TrackExpansionResult`, `_mergePreservingExistingTrackOrder`, and helper class names are consistent across tasks.
- Scope check: The plan intentionally does not introduce `PlaylistMembershipService`, remote edit controller, provider invalidation coordinator, or batching. Those belong to later phases.
