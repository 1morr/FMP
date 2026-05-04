# Performance and Data Batching Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace repeated per-track database and filesystem chains with batch operations in playlist mutations, selected downloads, download-path sync, and playlist cover grids.

**Architecture:** Keep existing domain boundaries. Add one small source-identity value object plus repository batch resolver, then make existing services consume it without changing playlist membership semantics or UI behavior. Batch writes only where they preserve existing partial-failure behavior; play-history pagination is intentionally left for a later sub-plan.

**Tech Stack:** Flutter, Dart, Riverpod, Isar, existing `PlaylistMutationService`, `TrackRepository`, `DownloadService`, `PlaylistService`, and provider tests.

---

## File Structure

- Modify: `lib/data/repositories/track_repository.dart`
  - Add `TrackSourceIdentity` and `getBySourceIdentities()`.
  - Refine `getOrCreateAll()` to use the resolver instead of source-id-only overfetch.
- Modify: `lib/services/library/playlist_mutation_service.dart`
  - Replace per-item `_findTrackByIdentity()` reads with one batch identity map per bulk mutation.
  - Collect new/updated tracks and persist them with `putAll()` where IDs can be assigned safely.
  - Preserve refresh partial-failure/pruning behavior.
- Modify: `lib/services/download/download_path_sync_service.dart`
  - Scan local metadata first, resolve all scanned identities once, and save changed tracks with `TrackRepository.saveAll()`.
- Modify: `lib/services/download/download_service.dart`
  - Add `DownloadBatchAddSummary` and `addTracksDownload()` using one base-dir lookup, one save-path batch lookup, and one priority lookup.
  - Keep `addTrackDownload()` as a compatibility wrapper over the batch method.
- Modify: `lib/ui/pages/library/playlist_detail_page.dart`
  - Use `addTracksDownload()` for selected-track downloads.
- Modify: `lib/services/library/playlist_service.dart`
  - Add `getPlaylistCoverDataForPlaylists()` that batches playlist first-track DB reads.
- Modify: `lib/providers/playlist_provider.dart`
  - Add `playlistCoverMapProvider` and keep `playlistCoverProvider` for non-grid callers.
- Modify: `lib/providers/library_invalidation_coordinator.dart`
  - Invalidate the batch cover provider when an individual cover changes.
- Modify: `lib/ui/pages/library/library_page.dart`
  - Read the shared cover map once for library playlist cards and reorderable cards.
- Modify: `lib/ui/pages/home/home_page.dart`
  - Read the shared cover map for home playlist cards.
- Tests:
  - `test/data/repositories/track_repository_batch_identity_test.dart`
  - `test/services/library/playlist_mutation_service_test.dart`
  - `test/services/download/download_service_phase1_test.dart`
  - `test/services/download/download_path_sync_service_batch_test.dart`
  - `test/services/library/playlist_cover_batch_test.dart`
  - `test/services/library/playlist_mutation_batch_structure_test.dart`
  - `test/ui/playlist_cover_grid_structure_test.dart`

---

### Task 1: Batch Track Identity Resolver

**Files:**
- Modify: `lib/data/repositories/track_repository.dart:42-59,326-421`
- Create: `test/data/repositories/track_repository_batch_identity_test.dart`

- [ ] **Step 1: Write failing resolver tests**

Create `test/data/repositories/track_repository_batch_identity_test.dart` with this full content:

```dart
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/models/track.dart';
import 'package:fmp/data/repositories/track_repository.dart';
import 'package:isar/isar.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await Isar.initializeIsarCore(
      libraries: {Abi.current(): await _resolveIsarLibraryPath()},
    );
  });

  test('getBySourceIdentities keeps source type and nullable cid distinct', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'track_repository_batch_identity_test_',
    );
    final isar = await Isar.open(
      [TrackSchema],
      directory: tempDir.path,
      name: 'track_repository_batch_identity_test',
    );
    addTearDown(() async {
      await isar.close(deleteFromDisk: true);
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });
    final repo = TrackRepository(isar);

    final youtubeNull = await repo.save(_track('same', SourceType.youtube, 'YT'));
    final youtubeCid = await repo.save(
      _track('same', SourceType.youtube, 'YT P2')..cid = 22,
    );
    final bilibiliNull = await repo.save(
      _track('same', SourceType.bilibili, 'BV'),
    );

    final result = await repo.getBySourceIdentities([
      TrackSourceIdentity.fromTrack(youtubeNull),
      TrackSourceIdentity.fromTrack(youtubeCid),
      TrackSourceIdentity.fromTrack(bilibiliNull),
    ]);

    expect(result[TrackSourceIdentity.fromTrack(youtubeNull)]?.id, youtubeNull.id);
    expect(result[TrackSourceIdentity.fromTrack(youtubeCid)]?.id, youtubeCid.id);
    expect(result[TrackSourceIdentity.fromTrack(bilibiliNull)]?.id, bilibiliNull.id);
  });
}

Track _track(String sourceId, SourceType sourceType, String title) {
  return Track()
    ..sourceId = sourceId
    ..sourceType = sourceType
    ..title = title
    ..createdAt = DateTime.now();
}

Future<String> _resolveIsarLibraryPath() async {
  final packageConfigFile =
      File('${Directory.current.path}/.dart_tool/package_config.json');
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

- [ ] **Step 2: Run the failing test**

Run: `flutter test test/data/repositories/track_repository_batch_identity_test.dart`
Expected: FAIL because `TrackSourceIdentity` and `getBySourceIdentities()` do not exist.

- [ ] **Step 3: Add the resolver**

In `lib/data/repositories/track_repository.dart`, add this value object above `TrackRepository`:

```dart
class TrackSourceIdentity {
  final SourceType sourceType;
  final String sourceId;
  final int? cid;

  const TrackSourceIdentity({
    required this.sourceType,
    required this.sourceId,
    this.cid,
  });

  factory TrackSourceIdentity.fromTrack(Track track) => TrackSourceIdentity(
        sourceType: track.sourceType,
        sourceId: track.sourceId,
        cid: track.cid,
      );

  String get sourcePageKey => cid != null
      ? '${sourceType.name}:$sourceId:$cid'
      : '${sourceType.name}:$sourceId';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TrackSourceIdentity &&
          other.sourceType == sourceType &&
          other.sourceId == sourceId &&
          other.cid == cid;

  @override
  int get hashCode => Object.hash(sourceType, sourceId, cid);
}
```

Add this repository method near `getBySourceIds()`:

```dart
Future<Map<TrackSourceIdentity, Track>> getBySourceIdentities(
  Iterable<TrackSourceIdentity> identities,
) async {
  final requested = identities.toSet();
  if (requested.isEmpty) return {};
  final keys = requested.map((identity) => identity.sourcePageKey).toSet();
  final tracks = await _isar.tracks
      .where()
      .anyOf(keys, (q, key) => q.sourcePageKeyEqualToAnyCid(key))
      .findAll();
  final result = <TrackSourceIdentity, Track>{};
  for (final track in tracks) {
    final identity = TrackSourceIdentity.fromTrack(track);
    if (requested.contains(identity)) {
      result.putIfAbsent(identity, () => track);
    }
  }
  return result;
}
```

Then update `getOrCreateAll()` so `existingTracks` comes from `getBySourceIdentities(uniqueTracks.map(TrackSourceIdentity.fromTrack))` and `existingMap` is keyed by `TrackSourceIdentity` instead of `uniqueKey`.

- [ ] **Step 4: Verify resolver tests pass**

Run: `flutter test test/data/repositories/track_repository_batch_identity_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/data/repositories/track_repository.dart test/data/repositories/track_repository_batch_identity_test.dart
git commit -m "perf(data): add batch track identity resolver"
```

### Task 2: Batch Playlist Mutation Reads and Writes

**Files:**
- Modify: `lib/services/library/playlist_mutation_service.dart:270-535,591-610`
- Modify: `test/services/library/playlist_mutation_service_test.dart`

- [ ] **Step 1: Add a regression test before refactor**

Add this test to `playlist_mutation_service_test.dart`:

```dart
test('addTracks uses identity semantics for mixed source and cid tracks in one batch', () async {
  final harness = await _createHarness();
  addTearDown(harness.dispose);
  final playlist = await _createPlaylist(harness, 'Batch Identity');
  final existing = await harness.tracks.save(_track('same', 'Existing')..cid = 1);
  final incoming = [_track('same', 'Null CID'), _track('same', 'Existing Updated')..cid = 1];
  final result = await harness.mutations.addTracks(playlist.id, incoming);
  final saved = await harness.playlists.getById(playlist.id);
  expect(result.addedCount, 2);
  expect(saved!.trackIds, contains(existing.id));
  expect((await harness.tracks.getBySourceIds(['same'])), hasLength(2));
});
```

Keep the existing partial-refresh persistence-error test unchanged; it is the guard that refresh batching must not turn one bad track into a full prune.

- [ ] **Step 2: Run focused tests before production change**

Run: `flutter test test/services/library/playlist_mutation_service_test.dart`
Expected: existing behavior tests PASS. The next structure test in Step 3 still FAILS until the per-track lookup is removed.

- [ ] **Step 3: Add a failing structure test for the batching boundary**

Create `test/services/library/playlist_mutation_batch_structure_test.dart`:

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('playlist mutation bulk paths resolve identities once per batch', () {
    final source = File(
      'lib/services/library/playlist_mutation_service.dart',
    ).readAsStringSync();
    final addTracksBody = _methodBody(source, 'addTracks');
    final refreshBody = _methodBody(source, 'replaceTracksFromRemoteRefresh');

    expect(source, contains('_findTracksByIdentity('));
    expect(addTracksBody, contains('final existingByIdentity ='));
    expect(refreshBody, contains('final existingByIdentity ='));
    expect(addTracksBody, isNot(contains('await _findTrackByIdentity')));
    expect(refreshBody, isNot(contains('await _findTrackByIdentity')));
    expect(source, isNot(contains('Future<Track?> _findTrackByIdentity')));
  });
}

String _methodBody(String source, String methodName) {
  final methodIndex = source.indexOf(' $methodName(');
  if (methodIndex == -1) {
    throw StateError('Method $methodName not found');
  }
  final openBrace = source.indexOf('{', methodIndex);
  var depth = 0;
  for (var i = openBrace; i < source.length; i++) {
    if (source[i] == '{') depth++;
    if (source[i] == '}') depth--;
    if (depth == 0) return source.substring(openBrace + 1, i);
  }
  throw StateError('Method $methodName body is not closed');
}
```

- [ ] **Step 4: Run the failing structure test**

Run: `flutter test test/services/library/playlist_mutation_batch_structure_test.dart`
Expected: FAIL because the current implementation still has `_findTrackByIdentity()` and per-loop `await _findTrackByIdentity(...)` calls.

- [ ] **Step 5: Replace per-track identity reads**

Import the resolver in `playlist_mutation_service.dart`:

```dart
import '../../data/repositories/track_repository.dart';
```

Replace `_findTrackByIdentity()` with:

```dart
Future<Map<TrackSourceIdentity, Track>> _findTracksByIdentity(
  Iterable<Track> tracks,
) {
  return TrackRepository(_isar).getBySourceIdentities(
    tracks.map(TrackSourceIdentity.fromTrack),
  );
}
```

In both `addTracks()` and `replaceTracksFromRemoteRefresh()`, compute once before looping:

```dart
final existingByIdentity = await _findTracksByIdentity(candidateTracks);
```

Inside the loop use:

```dart
final existingTrack = existingByIdentity[TrackSourceIdentity.fromTrack(inputTrack)];
```

- [ ] **Step 6: Batch normal writes without changing result counts**

For `addTracks()`, collect every new or changed `trackToSave` into `tracksToSave`, call one `await _isar.tracks.putAll(tracksToSave)`, assign returned IDs back to the same objects, and only then append newly linked IDs to `playlist.trackIds`. Keep the existing `addedTrackIds`, `repairedTrackIds`, `skippedTrackIds`, `updatedTrackIds`, `coverChanged`, and metadata merge rules.

For `replaceTracksFromRemoteRefresh()`, batch valid new/changed tracks, but preserve the existing per-track error behavior by keeping the current per-track fallback when a track cannot be prepared or saved. The existing test `replaceTracksFromRemoteRefresh preserves stale tracks when one track fails to persist` must still pass and must still set `pruningSkipped` to true.

- [ ] **Step 7: Verify focused mutation tests**

Run:
```bash
flutter test test/services/library/playlist_mutation_service_test.dart
flutter test test/services/library/playlist_mutation_batch_structure_test.dart
```
Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add lib/services/library/playlist_mutation_service.dart test/services/library/playlist_mutation_service_test.dart test/services/library/playlist_mutation_batch_structure_test.dart
git commit -m "perf(library): batch playlist mutation identity lookups"
```

### Task 3: Batch Download Sync and Selected Downloads

**Files:**
- Modify: `lib/services/download/download_path_sync_service.dart:62-160,166-256`
- Modify: `lib/services/download/download_service.dart:31-41,354-510`
- Modify: `lib/ui/pages/library/playlist_detail_page.dart:288-356`
- Create: `test/services/download/download_path_sync_service_batch_test.dart`
- Modify: `test/services/download/download_service_phase1_test.dart`

- [ ] **Step 1: Write failing selected-download test**

Add this test plus helper to `download_service_phase1_test.dart`:

```dart
test('addTracksDownload batches selected tracks and reports created skipped counts', () async {
  final settings = await settingsRepository.get();
  settings.customDownloadDir = tempDir.path;
  await settingsRepository.save(settings);
  final playlist = Playlist()
    ..id = 7
    ..name = 'Batch Downloads';
  final downloaded = await trackRepository.save(_downloadTrack('downloaded'));
  downloaded.setDownloadPath(
    playlist.id,
    p.join(tempDir.path, 'done.m4a'),
    playlistName: playlist.name,
  );
  await trackRepository.save(downloaded);
  final queued = await trackRepository.save(_downloadTrack('queued'));
  final fresh = await trackRepository.save(_downloadTrack('fresh'));
  final queuedPath = DownloadPathUtils.computeDownloadPath(
    baseDir: tempDir.path,
    playlistName: playlist.name,
    track: queued,
  );
  await downloadRepository.saveTask(
    DownloadTask()
      ..trackId = queued.id
      ..playlistId = playlist.id
      ..playlistName = playlist.name
      ..savePath = queuedPath
      ..status = DownloadStatus.pending
      ..priority = 9
      ..createdAt = DateTime.now(),
  );
  final service = DownloadService(
    downloadRepository: downloadRepository,
    trackRepository: trackRepository,
    settingsRepository: settingsRepository,
    sourceManager: SourceManager(),
  );

  final summary = await service.addTracksDownload(
    [downloaded, queued, fresh],
    fromPlaylist: playlist,
    skipSchedule: true,
  );

  expect(summary.createdCount, 1);
  expect(summary.alreadyDownloadedCount, 1);
  expect(summary.taskExistsCount, 1);
  expect(
    (await downloadRepository.getAllTasks()).map((task) => task.trackId),
    contains(fresh.id),
  );
  service.dispose();
});

Track _downloadTrack(String sourceId) {
  return Track()
    ..sourceId = sourceId
    ..sourceType = SourceType.youtube
    ..title = sourceId
    ..artist = 'Test Artist'
    ..createdAt = DateTime.now();
}
```

- [ ] **Step 2: Run failing download test**

Run: `flutter test test/services/download/download_service_phase1_test.dart --plain-name "addTracksDownload batches selected tracks"`
Expected: FAIL because `addTracksDownload()` and `DownloadBatchAddSummary` do not exist.

- [ ] **Step 3: Implement batch download enqueue**

In `download_service.dart`, add:

```dart
class DownloadBatchAddSummary {
  final int createdCount;
  final int alreadyDownloadedCount;
  final int taskExistsCount;
  const DownloadBatchAddSummary({this.createdCount = 0, this.alreadyDownloadedCount = 0, this.taskExistsCount = 0});
}
```

Add `addTracksDownload()` by extracting the existing `addPlaylistDownload()` batching pattern: filter downloaded tracks, compute base dir once, compute paths once, call `getTasksBySavePaths()` once, call `getNextPriority()` once, save new tasks with `saveTasks()`, and trigger scheduling only when `!skipSchedule && newTasks.isNotEmpty`. Change `addTrackDownload()` to delegate to `addTracksDownload([track], ...)` and convert the summary back to `DownloadResult`.

- [ ] **Step 4: Update selected downloads UI**

Replace the loop in `_downloadSelectedTracks()` with:

```dart
final summary = await downloadService.addTracksDownload(
  tracks,
  fromPlaylist: playlist,
  skipSchedule: true,
);
if (summary.createdCount > 0) {
  downloadService.triggerSchedule();
}
final addedCount = summary.createdCount;
final alreadyDownloadedCount = summary.alreadyDownloadedCount;
final taskExistsCount = summary.taskExistsCount;
```

- [ ] **Step 5: Batch download-path sync persistence**

In `download_path_sync_service.dart`, make `_scanAndMatchFolder()` return scanned `Track` objects without calling `_findMatchingTrack()` per item. After all folders are scanned, call `TrackRepository.getBySourceIdentities()` once, match scanned tracks from that map, collect changed DB tracks in `tracksToSave`, and replace per-track `_trackRepo.save(track)` calls with one `await _trackRepo.saveAll(tracksToSave)`.

- [ ] **Step 6: Add and run the download-path sync structure test**

Create `test/services/download/download_path_sync_service_batch_test.dart`:

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('download path sync resolves scanned track identities in one batch', () {
    final source = File(
      'lib/services/download/download_path_sync_service.dart',
    ).readAsStringSync();
    final syncBody = _methodBody(source, 'syncLocalFiles');
    final scanBody = _methodBody(source, '_scanAndMatchFolder');

    expect(syncBody, contains('getBySourceIdentities('));
    expect(syncBody, contains('saveAll('));
    expect(scanBody, isNot(contains('_findMatchingTrack(')));
    expect(source, isNot(contains('Future<Track?> _findMatchingTrack')));
  });
}

String _methodBody(String source, String methodName) {
  final methodIndex = source.indexOf(' $methodName(');
  if (methodIndex == -1) {
    throw StateError('Method $methodName not found');
  }
  final openBrace = source.indexOf('{', methodIndex);
  var depth = 0;
  for (var i = openBrace; i < source.length; i++) {
    if (source[i] == '{') depth++;
    if (source[i] == '}') depth--;
    if (depth == 0) return source.substring(openBrace + 1, i);
  }
  throw StateError('Method $methodName body is not closed');
}
```

Run: `flutter test test/services/download/download_path_sync_service_batch_test.dart`
Expected: FAIL until `syncLocalFiles()` uses `getBySourceIdentities()` and `saveAll()`.

- [ ] **Step 7: Verify download tests**

Run:
```bash
flutter test test/services/download/download_service_phase1_test.dart --plain-name "addTracksDownload batches selected tracks"
flutter test test/providers/startup_download_sync_provider_test.dart
flutter test test/services/download/download_path_sync_service_batch_test.dart
```
Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add lib/services/download/download_service.dart lib/services/download/download_path_sync_service.dart lib/ui/pages/library/playlist_detail_page.dart test/services/download/download_service_phase1_test.dart test/services/download/download_path_sync_service_batch_test.dart
git commit -m "perf(download): batch selected download enqueue"
```

### Task 4: Batch Playlist Cover Loading for Grids

**Files:**
- Modify: `lib/services/library/playlist_service.dart:40-52,304-341`
- Modify: `lib/providers/playlist_provider.dart:538-544`
- Modify: `lib/providers/library_invalidation_coordinator.dart:147-156`
- Modify: `lib/ui/pages/library/library_page.dart:249-404`
- Modify: `lib/ui/pages/home/home_page.dart:1092-1131`
- Create: `test/services/library/playlist_cover_batch_test.dart`

- [ ] **Step 1: Write failing batch cover service test**

Create `test/services/library/playlist_cover_batch_test.dart` with this full content:

```dart
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/models/playlist.dart';
import 'package:fmp/data/models/settings.dart';
import 'package:fmp/data/models/track.dart';
import 'package:fmp/data/repositories/playlist_repository.dart';
import 'package:fmp/data/repositories/settings_repository.dart';
import 'package:fmp/data/repositories/track_repository.dart';
import 'package:fmp/services/library/playlist_service.dart';
import 'package:isar/isar.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await Isar.initializeIsarCore(
      libraries: {Abi.current(): await _resolveIsarLibraryPath()},
    );
  });

  test('getPlaylistCoverDataForPlaylists resolves first-track covers in one batch', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'playlist_cover_batch_test_',
    );
    final isar = await Isar.open(
      [PlaylistSchema, TrackSchema, SettingsSchema],
      directory: tempDir.path,
      name: 'playlist_cover_batch_test',
    );
    addTearDown(() async {
      await isar.close(deleteFromDisk: true);
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });
    final playlistRepo = PlaylistRepository(isar);
    final trackRepo = TrackRepository(isar);
    final service = PlaylistService(
      playlistRepository: playlistRepo,
      trackRepository: trackRepo,
      settingsRepository: SettingsRepository(isar),
      isar: isar,
    );
    final firstTrack = await trackRepo.save(_track('first'));
    final secondTrack = await trackRepo.save(_track('second'));
    final firstPlaylist = Playlist()
      ..name = 'First'
      ..trackIds = [firstTrack.id]
      ..createdAt = DateTime.now();
    final secondPlaylist = Playlist()
      ..name = 'Second'
      ..trackIds = [secondTrack.id]
      ..createdAt = DateTime.now();
    firstPlaylist.id = await playlistRepo.save(firstPlaylist);
    secondPlaylist.id = await playlistRepo.save(secondPlaylist);

    final covers = await service.getPlaylistCoverDataForPlaylists([
      firstPlaylist,
      secondPlaylist,
    ]);

    expect(covers[firstPlaylist.id]!.networkUrl, 'https://example.com/first.jpg');
    expect(covers[secondPlaylist.id]!.networkUrl, 'https://example.com/second.jpg');
  });
}

Track _track(String sourceId) {
  return Track()
    ..sourceId = sourceId
    ..sourceType = SourceType.youtube
    ..title = sourceId
    ..thumbnailUrl = 'https://example.com/$sourceId.jpg'
    ..createdAt = DateTime.now();
}

Future<String> _resolveIsarLibraryPath() async {
  final packageConfigFile =
      File('${Directory.current.path}/.dart_tool/package_config.json');
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

- [ ] **Step 2: Run failing cover test**

Run: `flutter test test/services/library/playlist_cover_batch_test.dart`
Expected: FAIL because `getPlaylistCoverDataForPlaylists()` does not exist.

- [ ] **Step 3: Implement batch cover service/provider**

Add to `PlaylistService`:

```dart
Future<Map<int, PlaylistCoverData>> getPlaylistCoverDataForPlaylists(
  List<Playlist> playlists,
) async {
  final firstTrackIds = playlists
      .where((playlist) => playlist.trackIds.isNotEmpty)
      .map((playlist) => playlist.trackIds.first)
      .toSet()
      .toList();
  final firstTracks = await _trackRepository.getByIds(firstTrackIds);
  final firstTrackById = {for (final track in firstTracks) track.id: track};
  return {
    for (final playlist in playlists)
      playlist.id: await _coverDataFromPlaylistAndFirstTrack(
        playlist,
        playlist.trackIds.isEmpty ? null : firstTrackById[playlist.trackIds.first],
      ),
  };
}
```

Extract the current cover decision logic into `_coverDataFromPlaylistAndFirstTrack(Playlist playlist, Track? firstTrack)` and make existing `getPlaylistCoverData(int playlistId)` call it.

Add provider:

```dart
final playlistCoverMapProvider = FutureProvider<Map<int, PlaylistCoverData>>((ref) async {
  final service = ref.watch(playlistServiceProvider);
  final playlists = ref.watch(playlistListProvider).playlists;
  return service.getPlaylistCoverDataForPlaylists(playlists);
});
```

Update `library_invalidation_coordinator.dart` so `invalidatePlaylistCover` invalidates both `playlistCoverProvider(playlistId)` and `playlistCoverMapProvider`.

- [ ] **Step 4: Update grid cards**

In `library_page.dart` and `home_page.dart`, read `final coverMapAsync = ref.watch(playlistCoverMapProvider);` once in the parent list/grid builder and pass `AsyncValue<PlaylistCoverData>` or nullable `PlaylistCoverData` into card widgets. Remove per-card `ref.watch(playlistCoverProvider(playlist.id))` from `_PlaylistCard`, `_ReorderablePlaylistCard`, and `_HomePlaylistCard`.

- [ ] **Step 5: Add and run the grid structure test**

Create `test/ui/playlist_cover_grid_structure_test.dart`:

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('playlist grids use the shared cover map instead of per-card cover providers', () {
    final librarySource = File('lib/ui/pages/library/library_page.dart').readAsStringSync();
    final homeSource = File('lib/ui/pages/home/home_page.dart').readAsStringSync();
    final providerSource = File('lib/providers/playlist_provider.dart').readAsStringSync();

    expect(providerSource, contains('final playlistCoverMapProvider'));
    expect(librarySource, contains('playlistCoverMapProvider'));
    expect(homeSource, contains('playlistCoverMapProvider'));
    expect(_classBody(librarySource, '_PlaylistCard'), isNot(contains('playlistCoverProvider(')));
    expect(_classBody(librarySource, '_ReorderablePlaylistCard'), isNot(contains('playlistCoverProvider(')));
    expect(_classBody(homeSource, '_HomePlaylistCard'), isNot(contains('playlistCoverProvider(')));
  });
}

String _classBody(String source, String className) {
  final classIndex = source.indexOf('class $className');
  if (classIndex == -1) throw StateError('Class $className not found');
  final openBrace = source.indexOf('{', classIndex);
  var depth = 0;
  for (var i = openBrace; i < source.length; i++) {
    if (source[i] == '{') depth++;
    if (source[i] == '}') depth--;
    if (depth == 0) return source.substring(openBrace + 1, i);
  }
  throw StateError('Class $className body is not closed');
}
```

Run: `flutter test test/ui/playlist_cover_grid_structure_test.dart`
Expected: FAIL until the grid cards stop watching `playlistCoverProvider(playlist.id)` themselves.

- [ ] **Step 6: Verify cover tests and analyze**

Run:
```bash
flutter test test/services/library/playlist_cover_batch_test.dart
flutter test test/ui/playlist_cover_grid_structure_test.dart
flutter analyze
```
Expected: PASS / no analyzer errors.

- [ ] **Step 7: Commit**

```bash
git add lib/services/library/playlist_service.dart lib/providers/playlist_provider.dart lib/providers/library_invalidation_coordinator.dart lib/ui/pages/library/library_page.dart lib/ui/pages/home/home_page.dart test/services/library/playlist_cover_batch_test.dart test/ui/playlist_cover_grid_structure_test.dart
git commit -m "perf(ui): batch playlist cover loading"
```

### Task 5: Phase Verification and Follow-up Boundary

**Files:**
- No source modifications unless verification reveals a missing durable architecture rule.

- [ ] **Step 1: Verify roadmap scope**

Re-read `docs/superpowers/specs/2026-05-02-program-logic-repair-roadmap-design.md:195-214` and confirm every Phase 5 acceptance criterion is covered. Do not implement play-history query pagination in this phase.

- [ ] **Step 2: Run focused phase tests**

Run:
```bash
flutter test test/data/repositories/track_repository_batch_identity_test.dart test/services/library/playlist_mutation_service_test.dart test/services/library/playlist_mutation_batch_structure_test.dart test/services/download/download_service_phase1_test.dart test/providers/startup_download_sync_provider_test.dart test/services/download/download_path_sync_service_batch_test.dart test/services/library/playlist_cover_batch_test.dart test/ui/playlist_cover_grid_structure_test.dart
```
Expected: PASS.

- [ ] **Step 3: Run full verification**

Run:
```bash
flutter analyze
flutter test
```
Expected: analyzer exits 0 and the full test suite exits 0.

- [ ] **Step 4: Commit docs only if architecture guidance changed**

If no durable project guidance changed, do not edit docs. If a new rule is needed, update `CLAUDE.md` and commit:

```bash
git add CLAUDE.md
git commit -m "docs: document batch data access patterns"
```

- [ ] **Step 5: Final implementation report**

Report exact commands run and results. State explicitly that play-history pagination remains a later sub-plan, matching the roadmap.
