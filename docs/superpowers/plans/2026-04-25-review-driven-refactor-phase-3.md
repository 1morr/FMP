# Review-Driven Refactor Phase 3 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement Phase 3 structural refactors from `docs/review`: atomic Playlist/Track and DownloadTask/Track writes, purpose-specific play-history queries, lazy history rows, queue-state isolation, and Source ownership cleanup.

**Architecture:** Keep the existing audio architecture intact: UI still calls `AudioController`, `QueueManager` still owns queue semantics, and playback request locking stays in `PlaybackRequestExecutor`/`AudioController`. Phase 3 changes transaction boundaries and provider/list structure without changing user-visible playback, playlist, history, or download behavior.

**Tech Stack:** Flutter, Dart, Riverpod, Isar, `flutter_test`, existing fake services, source/static tests for structural boundaries.

---

## Scope and File Map

Phase 3 covers structural debt. It intentionally does **not** add database unique indexes, migrate model schemas, rewrite `AudioController`, or introduce a radio/audio ownership coordinator.

- Modify `lib/services/library/playlist_service.dart`: make core Playlist/Track add/remove/duplicate paths update both sides inside one Isar transaction.
- Test `test/services/library/playlist_service_bidirectional_test.dart`: behavioral bidirectional relation coverage, including duplicate playlist reverse relation.
- Test `test/services/library/playlist_service_transaction_source_test.dart`: static guard that core remove paths no longer call separate repository transactions.
- Modify `lib/data/repositories/download_repository.dart`: add one transaction method for completing a task and writing the Track download path.
- Modify `lib/services/download/download_service.dart`: replace separate Track path + task status writes with the new completion transaction.
- Test `test/services/download/download_completion_transaction_test.dart`: repository-level atomic completion coverage.
- Modify `lib/data/repositories/play_history_repository.dart`: add purpose-specific query methods for recent distinct, stats, and paged history rows.
- Modify `lib/providers/play_history_provider.dart`: stop deriving recent/stats/history page from one 1000-row shared snapshot.
- Modify `lib/ui/pages/history/play_history_page.dart`: flatten date headers and history rows so all visible rows are lazily built.
- Test `test/data/repositories/play_history_repository_phase4_test.dart`, `test/providers/play_history_provider_phase4_test.dart`, and `test/ui/pages/history/play_history_page_phase2_test.dart`: repository/provider/UI regressions.
- Modify `lib/services/audio/player_state.dart` and `lib/services/audio/audio_provider.dart`: introduce low-frequency queue state and make `queueProvider` read it instead of high-frequency `PlayerState` position updates.
- Test `test/services/audio/audio_controller_phase1_test.dart` or new `test/services/audio/audio_queue_state_provider_test.dart`: queue provider does not update on position-only state changes.
- Modify Source creation call sites in `lib/services/audio/audio_provider.dart`, `lib/providers/playlist_provider.dart`, `lib/providers/popular_provider.dart`, `lib/services/import/import_service.dart`, and `lib/services/cache/ranking_cache_service.dart`: prefer injected `SourceManager`/providers over direct ad-hoc `YouTubeSource()` where practical.
- Test with source/static guard `test/data/sources/source_ownership_phase3_test.dart`.

---

### Task 1: Atomic Playlist Add and Duplicate Relations

**Files:**
- Modify: `lib/services/library/playlist_service.dart:284-368`, `lib/services/library/playlist_service.dart:553-579`
- Create: `test/services/library/playlist_service_bidirectional_test.dart`

- [ ] **Step 1: Write the failing bidirectional duplicate test**

Create `test/services/library/playlist_service_bidirectional_test.dart`:

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

  group('PlaylistService bidirectional relations', () {
    setUpAll(() async {
      await Isar.initializeIsarCore(
        libraries: {Abi.current(): await _resolveIsarLibraryPath()},
      );
    });

    test('duplicatePlaylist adds reverse playlistInfo to copied tracks', () async {
      final harness = await _createHarness();
      addTearDown(harness.dispose);

      final original = await harness.playlists.save(Playlist()
        ..name = 'Original'
        ..createdAt = DateTime.now());
      final track = await harness.tracks.save(Track()
        ..sourceId = 'yt-dup'
        ..sourceType = SourceType.youtube
        ..title = 'Duplicate Me'
        ..createdAt = DateTime.now());
      await harness.service.addTrackToPlaylist(original.id, track);

      final copy = await harness.service.duplicatePlaylist(original.id, 'Copy');

      final copiedTrack = await harness.tracks.getById(track.id);
      expect(copy.trackIds, [track.id]);
      expect(copiedTrack!.belongsToPlaylist(original.id), isTrue);
      expect(copiedTrack.belongsToPlaylist(copy.id), isTrue);
      expect(
        copiedTrack.playlistInfo
            .singleWhere((info) => info.playlistId == copy.id)
            .playlistName,
        'Copy',
      );
    });
  });
}

class _Harness {
  _Harness(this.isar)
      : playlists = PlaylistRepository(isar),
        tracks = TrackRepository(isar),
        settings = SettingsRepository(isar) {
    service = PlaylistService(
      playlistRepository: playlists,
      trackRepository: tracks,
      settingsRepository: settings,
      isar: isar,
    );
  }

  final Isar isar;
  final PlaylistRepository playlists;
  final TrackRepository tracks;
  final SettingsRepository settings;
  late final PlaylistService service;

  Future<void> dispose() async {
    final dir = Directory(isar.directory!);
    await isar.close(deleteFromDisk: true);
    if (await dir.exists()) await dir.delete(recursive: true);
  }
}

Future<_Harness> _createHarness() async {
  final tempDir = await Directory.systemTemp.createTemp(
    'playlist_service_bidirectional_test_',
  );
  final isar = await Isar.open(
    [PlaylistSchema, TrackSchema, SettingsSchema],
    directory: tempDir.path,
    name: 'playlist_service_bidirectional_test',
  );
  return _Harness(isar);
}

Future<String> _resolveIsarLibraryPath() async {
  final packageConfigFile =
      File('${Directory.current.path}/.dart_tool/package_config.json');
  final packageConfig =
      jsonDecode(await packageConfigFile.readAsString()) as Map<String, dynamic>;
  final packages = packageConfig['packages'] as List<dynamic>;
  final packageConfigDir = Directory('${Directory.current.path}/.dart_tool');

  for (final package in packages) {
    if (package is! Map<String, dynamic> ||
        package['name'] != 'isar_flutter_libs') continue;
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

- [ ] **Step 2: Run the duplicate test and verify it fails**

Run: `flutter test test/services/library/playlist_service_bidirectional_test.dart --plain-name "duplicatePlaylist adds reverse playlistInfo to copied tracks"`
Expected: FAIL because `duplicatePlaylist()` copies `Playlist.trackIds` but does not add the copied playlist id to each `Track.playlistInfo`.

- [ ] **Step 3: Update add and duplicate paths to use one relation transaction**

In `lib/services/library/playlist_service.dart`, replace the persistence section of `addTrackToPlaylist()` with:

```dart
    existingTrack.addToPlaylist(playlistId, playlistName: playlist.name);
    final wasEmpty = playlist.trackIds.isEmpty;
    if (!playlist.trackIds.contains(existingTrack.id)) {
      playlist.trackIds = [...playlist.trackIds, existingTrack.id];
    }
    if (wasEmpty && !playlist.hasCustomCover) {
      playlist.coverUrl = existingTrack.thumbnailUrl;
    }
    playlist.updatedAt = DateTime.now();
    existingTrack.updatedAt = DateTime.now();

    await _isar.writeTxn(() async {
      await _isar.tracks.put(existingTrack);
      await _isar.playlists.put(playlist);
    });
```

In `addTracksToPlaylist()`, replace the separate `saveAll()` + `addTracks()` calls with:

```dart
    final wasEmpty = playlist.trackIds.isEmpty;
    final trackIds = tracksToAdd.map((track) => track.id).toList();
    playlist.trackIds = [...playlist.trackIds, ...trackIds];
    if (wasEmpty && !playlist.hasCustomCover && tracksToAdd.isNotEmpty) {
      playlist.coverUrl = tracksToAdd.first.thumbnailUrl;
    }
    playlist.updatedAt = DateTime.now();
    for (final track in tracksToAdd) {
      track.updatedAt = DateTime.now();
    }

    await _isar.writeTxn(() async {
      await _isar.tracks.putAll(tracksToAdd);
      await _isar.playlists.put(playlist);
    });
```

In `duplicatePlaylist()`, replace the final save with:

```dart
    await _isar.writeTxn(() async {
      final id = await _isar.playlists.put(copy);
      copy.id = id;

      final copiedTracks = (await _isar.tracks.getAll(copy.trackIds))
          .whereType<Track>()
          .toList();
      for (final track in copiedTracks) {
        track.addToPlaylist(copy.id, playlistName: copy.name);
        track.updatedAt = DateTime.now();
      }
      if (copiedTracks.isNotEmpty) {
        await _isar.tracks.putAll(copiedTracks);
      }
    });
    return copy;
```

- [ ] **Step 4: Verify add/duplicate behavior and commit**

Run: `dart format lib/services/library/playlist_service.dart test/services/library/playlist_service_bidirectional_test.dart`
Expected: files formatted.

Run: `flutter test test/services/library/playlist_service_bidirectional_test.dart`
Expected: PASS.

Run: `git add lib/services/library/playlist_service.dart test/services/library/playlist_service_bidirectional_test.dart && git commit -m "refactor(library): make playlist add relations atomic"`
Expected: commit succeeds.

---

### Task 2: Atomic Playlist Remove Relations

**Files:**
- Modify: `lib/services/library/playlist_service.dart:373-450`
- Create: `test/services/library/playlist_service_transaction_source_test.dart`
- Modify: `test/services/library/playlist_service_bidirectional_test.dart`

- [ ] **Step 1: Write structural source tests for remove transactions**

Create `test/services/library/playlist_service_transaction_source_test.dart`:

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PlaylistService transaction boundaries', () {
    final source = File('lib/services/library/playlist_service.dart')
        .readAsStringSync();

    test('removeTrackFromPlaylist uses service-level Isar transaction', () {
      final body = _methodBody(source, 'removeTrackFromPlaylist');

      expect(body, contains('_isar.writeTxn'));
      expect(body, isNot(contains('_playlistRepository.removeTrack(')));
      expect(body, isNot(contains('_trackRepository.delete(')));
      expect(body, isNot(contains('_trackRepository.save(')));
    });

    test('removeTracksFromPlaylist uses service-level Isar transaction', () {
      final body = _methodBody(source, 'removeTracksFromPlaylist');

      expect(body, contains('_isar.writeTxn'));
      expect(body, isNot(contains('_playlistRepository.removeTracks(')));
      expect(body, isNot(contains('_trackRepository.deleteAll(')));
      expect(body, isNot(contains('_trackRepository.saveAll(')));
    });
  });
}

String _methodBody(String source, String name) {
  final start = source.indexOf('Future<void> $name');
  expect(start, isNonNegative, reason: 'method $name should exist');
  final firstBrace = source.indexOf('{', start);
  var depth = 0;
  for (var i = firstBrace; i < source.length; i++) {
    final char = source[i];
    if (char == '{') depth++;
    if (char == '}') depth--;
    if (depth == 0) return source.substring(firstBrace, i + 1);
  }
  fail('method $name body did not close');
}
```

- [ ] **Step 2: Add behavioral tests for single and batch removal**

Append these tests to the existing group in `test/services/library/playlist_service_bidirectional_test.dart`:

```dart
    test('removeTrackFromPlaylist updates playlist and deletes orphan track',
        () async {
      final harness = await _createHarness();
      addTearDown(harness.dispose);

      final playlist = await harness.playlists.save(Playlist()
        ..name = 'Remove Single'
        ..createdAt = DateTime.now());
      final track = await harness.tracks.save(Track()
        ..sourceId = 'yt-remove-single'
        ..sourceType = SourceType.youtube
        ..title = 'Remove Single Track'
        ..createdAt = DateTime.now());
      await harness.service.addTrackToPlaylist(playlist.id, track);

      await harness.service.removeTrackFromPlaylist(playlist.id, track.id);

      final updatedPlaylist = await harness.playlists.getById(playlist.id);
      expect(updatedPlaylist!.trackIds, isEmpty);
      expect(await harness.tracks.getById(track.id), isNull);
    });

    test('removeTracksFromPlaylist updates shared tracks and deletes orphans',
        () async {
      final harness = await _createHarness();
      addTearDown(harness.dispose);

      final first = await harness.playlists.save(Playlist()
        ..name = 'First'
        ..createdAt = DateTime.now());
      final second = await harness.playlists.save(Playlist()
        ..name = 'Second'
        ..createdAt = DateTime.now());
      final orphan = await harness.tracks.save(Track()
        ..sourceId = 'yt-orphan'
        ..sourceType = SourceType.youtube
        ..title = 'Orphan'
        ..createdAt = DateTime.now());
      final shared = await harness.tracks.save(Track()
        ..sourceId = 'yt-shared'
        ..sourceType = SourceType.youtube
        ..title = 'Shared'
        ..createdAt = DateTime.now());
      await harness.service.addTracksToPlaylist(first.id, [orphan, shared]);
      await harness.service.addTrackToPlaylist(second.id, shared);

      await harness.service.removeTracksFromPlaylist(first.id, [orphan.id, shared.id]);

      final updatedFirst = await harness.playlists.getById(first.id);
      expect(updatedFirst!.trackIds, isEmpty);
      expect(await harness.tracks.getById(orphan.id), isNull);
      final updatedShared = await harness.tracks.getById(shared.id);
      expect(updatedShared!.belongsToPlaylist(first.id), isFalse);
      expect(updatedShared.belongsToPlaylist(second.id), isTrue);
    });
```

- [ ] **Step 3: Run remove tests and verify failure**

Run: `flutter test test/services/library/playlist_service_transaction_source_test.dart`
Expected: FAIL because remove methods still call repository-level writes instead of one service-level transaction.

Run: `flutter test test/services/library/playlist_service_bidirectional_test.dart --plain-name "removeTrackFromPlaylist updates playlist and deletes orphan track"`
Expected: PASS or FAIL depending on current behavior; this test protects the behavior while the structural test drives the transaction refactor.

- [ ] **Step 4: Refactor single remove into one transaction**

In `lib/services/library/playlist_service.dart`, replace the body after `wasFirstTrack` in `removeTrackFromPlaylist()` with:

```dart
    if (playlist == null) return;

    await _isar.writeTxn(() async {
      playlist.trackIds = playlist.trackIds.where((id) => id != trackId).toList();
      playlist.updatedAt = DateTime.now();
      await _isar.playlists.put(playlist);

      final track = await _isar.tracks.get(trackId);
      if (track != null) {
        track.removeFromPlaylist(playlistId);
        if (track.playlistInfo.isEmpty) {
          await _isar.tracks.delete(trackId);
          logDebug('Deleted orphan track: ${track.title}');
        } else {
          track.updatedAt = DateTime.now();
          await _isar.tracks.put(track);
        }
      }
    });
```

Keep the existing default-cover refresh after the transaction:

```dart
    if (wasFirstTrack) {
      final updatedPlaylist = await _playlistRepository.getById(playlistId);
      if (updatedPlaylist != null) {
        await _updateDefaultCover(updatedPlaylist);
      }
    }
```

- [ ] **Step 5: Refactor batch remove into one transaction**

In `removeTracksFromPlaylist()`, replace the separate repository calls with:

```dart
    final trackIdSet = trackIds.toSet();
    await _isar.writeTxn(() async {
      playlist.trackIds =
          playlist.trackIds.where((id) => !trackIdSet.contains(id)).toList();
      playlist.updatedAt = DateTime.now();
      await _isar.playlists.put(playlist);

      final tracks = (await _isar.tracks.getAll(trackIds)).whereType<Track>();
      final toDelete = <int>[];
      final toUpdate = <Track>[];

      for (final track in tracks) {
        track.removeFromPlaylist(playlistId);
        if (track.playlistInfo.isEmpty) {
          toDelete.add(track.id);
          logDebug('Will delete orphan track: ${track.title}');
        } else {
          track.updatedAt = DateTime.now();
          toUpdate.add(track);
        }
      }

      if (toDelete.isNotEmpty) {
        await _isar.tracks.deleteAll(toDelete);
      }
      if (toUpdate.isNotEmpty) {
        await _isar.tracks.putAll(toUpdate);
      }
    });
```

Keep the default-cover refresh after the transaction.

- [ ] **Step 6: Verify remove behavior and commit**

Run: `dart format lib/services/library/playlist_service.dart test/services/library/playlist_service_bidirectional_test.dart test/services/library/playlist_service_transaction_source_test.dart`
Expected: files formatted.

Run: `flutter test test/services/library/playlist_service_bidirectional_test.dart test/services/library/playlist_service_transaction_source_test.dart`
Expected: PASS.

Run: `git add lib/services/library/playlist_service.dart test/services/library/playlist_service_bidirectional_test.dart test/services/library/playlist_service_transaction_source_test.dart && git commit -m "refactor(library): make playlist removals atomic"`
Expected: commit succeeds.

---

### Task 3: Atomic Download Completion Writes

**Files:**
- Modify: `lib/data/repositories/download_repository.dart:158-173`
- Modify: `lib/services/download/download_service.dart:866-887`
- Create: `test/services/download/download_completion_transaction_test.dart`

- [ ] **Step 1: Write repository-level completion transaction tests**

Create `test/services/download/download_completion_transaction_test.dart`:

```dart
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/models/download_task.dart';
import 'package:fmp/data/models/track.dart';
import 'package:fmp/data/repositories/download_repository.dart';
import 'package:isar/isar.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DownloadRepository completion transaction', () {
    setUpAll(() async {
      await Isar.initializeIsarCore(
        libraries: {Abi.current(): await _resolveIsarLibraryPath()},
      );
    });

    test('completeTaskWithDownloadPath updates track and task together', () async {
      final harness = await _createHarness();
      addTearDown(harness.dispose);

      final trackId = await harness.isar.writeTxn(() async {
        return harness.isar.tracks.put(Track()
          ..sourceId = 'yt-complete'
          ..sourceType = SourceType.youtube
          ..title = 'Complete Track'
          ..createdAt = DateTime.now());
      });
      final task = await harness.repository.saveTask(DownloadTask()
        ..trackId = trackId
        ..playlistId = 7
        ..playlistName = 'Phase3'
        ..savePath = 'C:/Music/FMP/Phase3/audio.m4a'
        ..status = DownloadStatus.downloading
        ..createdAt = DateTime.now());

      await harness.repository.completeTaskWithDownloadPath(
        taskId: task.id,
        trackId: trackId,
        playlistId: 7,
        playlistName: 'Phase3',
        savePath: 'C:/Music/FMP/Phase3/audio.m4a',
      );

      final updatedTrack = await harness.isar.tracks.get(trackId);
      final updatedTask = await harness.repository.getTaskById(task.id);
      expect(updatedTrack!.downloadPathForPlaylist(7),
          'C:/Music/FMP/Phase3/audio.m4a');
      expect(updatedTask!.status, DownloadStatus.completed);
      expect(updatedTask.completedAt, isNotNull);
    });

    test('completeTaskWithDownloadPath does not complete when track is missing',
        () async {
      final harness = await _createHarness();
      addTearDown(harness.dispose);

      final task = await harness.repository.saveTask(DownloadTask()
        ..trackId = 999
        ..status = DownloadStatus.downloading
        ..createdAt = DateTime.now());

      await expectLater(
        harness.repository.completeTaskWithDownloadPath(
          taskId: task.id,
          trackId: 999,
          playlistId: null,
          playlistName: null,
          savePath: 'C:/Music/FMP/Missing/audio.m4a',
        ),
        throwsStateError,
      );

      final updatedTask = await harness.repository.getTaskById(task.id);
      expect(updatedTask!.status, DownloadStatus.downloading);
    });
  });
}

class _Harness {
  _Harness(this.isar) : repository = DownloadRepository(isar);

  final Isar isar;
  final DownloadRepository repository;

  Future<void> dispose() async {
    final dir = Directory(isar.directory!);
    await isar.close(deleteFromDisk: true);
    if (await dir.exists()) await dir.delete(recursive: true);
  }
}

Future<_Harness> _createHarness() async {
  final tempDir = await Directory.systemTemp.createTemp(
    'download_completion_transaction_test_',
  );
  final isar = await Isar.open(
    [TrackSchema, DownloadTaskSchema],
    directory: tempDir.path,
    name: 'download_completion_transaction_test',
  );
  return _Harness(isar);
}

Future<String> _resolveIsarLibraryPath() async {
  final packageConfigFile =
      File('${Directory.current.path}/.dart_tool/package_config.json');
  final packageConfig =
      jsonDecode(await packageConfigFile.readAsString()) as Map<String, dynamic>;
  final packages = packageConfig['packages'] as List<dynamic>;
  final packageConfigDir = Directory('${Directory.current.path}/.dart_tool');

  for (final package in packages) {
    if (package is! Map<String, dynamic> ||
        package['name'] != 'isar_flutter_libs') continue;
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

- [ ] **Step 2: Run the new test and verify it fails**

Run: `flutter test test/services/download/download_completion_transaction_test.dart`
Expected: FAIL because `DownloadRepository.completeTaskWithDownloadPath()` does not exist.

- [ ] **Step 3: Add the transaction method**

In `lib/data/repositories/download_repository.dart`, add the Track import:

```dart
import '../models/track.dart';
```

Then add this method after `updateTaskStatus()`:

```dart
  /// Complete a download and attach its saved path to the Track in one DB txn.
  Future<void> completeTaskWithDownloadPath({
    required int taskId,
    required int trackId,
    required int? playlistId,
    required String? playlistName,
    required String savePath,
  }) async {
    await _isar.writeTxn(() async {
      final track = await _isar.tracks.get(trackId);
      if (track == null) {
        throw StateError('Track not found for completed download: $trackId');
      }
      final task = await _isar.downloadTasks.get(taskId);
      if (task == null) {
        throw StateError('Download task not found for completion: $taskId');
      }

      final effectivePlaylistId = playlistId ?? 0;
      track.setDownloadPath(
        effectivePlaylistId,
        savePath,
        playlistName: playlistName,
      );
      task.status = DownloadStatus.completed;
      task.completedAt = DateTime.now();
      task.savePath = savePath;
      track.updatedAt = DateTime.now();

      await _isar.tracks.put(track);
      await _isar.downloadTasks.put(task);
    });
  }
```

- [ ] **Step 4: Use the transaction in `DownloadService`**

In `lib/services/download/download_service.dart`, replace:

```dart
        await _trackRepository.addDownloadPath(
            track.id, task.playlistId, task.playlistName, savePath);
```

and the later completed status update:

```dart
      await _downloadRepository.updateTaskStatus(
          task.id, DownloadStatus.completed);
```

with one call in the verified-file branch:

```dart
        await _downloadRepository.completeTaskWithDownloadPath(
          taskId: task.id,
          trackId: track.id,
          playlistId: task.playlistId,
          playlistName: task.playlistName,
          savePath: savePath,
        );
```

Remove the separate completed-status update block. Keep the abort check after the transaction so a deletion during metadata/finalization still clears the track path and files.

- [ ] **Step 5: Verify download tests and commit**

Run: `dart format lib/data/repositories/download_repository.dart lib/services/download/download_service.dart test/services/download/download_completion_transaction_test.dart`
Expected: files formatted.

Run: `flutter test test/services/download/download_completion_transaction_test.dart test/services/download/download_service_phase1_test.dart`
Expected: PASS.

Run: `git add lib/data/repositories/download_repository.dart lib/services/download/download_service.dart test/services/download/download_completion_transaction_test.dart && git commit -m "refactor(download): complete task and track path atomically"`
Expected: commit succeeds.

---

### Task 4: Purpose-Specific Play History Queries

**Files:**
- Modify: `lib/data/repositories/play_history_repository.dart:68-97`, `lib/data/repositories/play_history_repository.dart:222-334`
- Modify: `lib/providers/play_history_provider.dart:8-93`
- Modify: `test/data/repositories/play_history_repository_phase4_test.dart`
- Modify: `test/providers/play_history_provider_phase4_test.dart`

- [ ] **Step 1: Add repository tests for paged query and recent distinct**

Append these tests to `test/data/repositories/play_history_repository_phase4_test.dart` inside the existing group:

```dart
    test('queryHistory applies time order pagination without snapshot cap',
        () async {
      final harness = await _createHarness();
      addTearDown(harness.dispose);

      final records = List.generate(75, (index) {
        return _history(
          sourceId: 'song-$index',
          sourceType: SourceType.youtube,
          title: 'Song $index',
          playedAt: DateTime(2026, 4, 20, 12).subtract(Duration(minutes: index)),
        );
      });
      await harness.seedMany(records);

      final page = await harness.repository.queryHistory(
        offset: 20,
        limit: 10,
      );

      expect(page.map((e) => e.sourceId).toList(),
          List.generate(10, (index) => 'song-${index + 20}'));
    });

    test('getRecentHistoryDistinct scans only enough recent rows for unique tracks',
        () async {
      final harness = await _createHarness();
      addTearDown(harness.dispose);

      await harness.seedMany([
        _history(
          sourceId: 'repeat',
          sourceType: SourceType.youtube,
          title: 'Repeat Latest',
          playedAt: DateTime(2026, 4, 20, 12),
        ),
        _history(
          sourceId: 'repeat',
          sourceType: SourceType.youtube,
          title: 'Repeat Older',
          playedAt: DateTime(2026, 4, 20, 11),
        ),
        _history(
          sourceId: 'unique',
          sourceType: SourceType.youtube,
          title: 'Unique',
          playedAt: DateTime(2026, 4, 20, 10),
        ),
      ]);

      final recent = await harness.repository.getRecentHistoryDistinct(limit: 2);

      expect(recent.map((e) => e.sourceId).toList(), ['repeat', 'unique']);
    });
```

Also add this method to `_Harness`:

```dart
  Future<void> seedMany(List<PlayHistory> records) async {
    await isar.writeTxn(() async {
      await isar.playHistorys.putAll(records);
    });
  }
```

- [ ] **Step 2: Add provider tests proving recent/stats no longer depend on shared snapshot**

Append this test to `test/providers/play_history_provider_phase4_test.dart`:

```dart
    test('recent and stats use purpose-specific repository queries', () async {
      final repository = _FakePlayHistoryRepository([
        _history(
          id: 1,
          sourceId: 'song-a',
          title: 'Song A',
          playedAt: DateTime(2026, 4, 20, 12),
        ),
      ]);
      final container = ProviderContainer(
        overrides: [
          playHistoryRepositoryProvider.overrideWith((ref) => repository),
        ],
      );
      addTearDown(container.dispose);

      await container.read(recentPlayHistoryProvider.future);
      await container.read(playHistoryStatsProvider.future);

      expect(repository.snapshotCalls, 0);
      expect(repository.recentDistinctCalls, 1);
      expect(repository.statsCalls, 1);
    });
```

Update `_FakePlayHistoryRepository` with counters and overrides:

```dart
  int recentDistinctCalls = 0;
  int statsCalls = 0;

  @override
  Future<List<PlayHistory>> getRecentHistoryDistinct({int limit = 10}) async {
    recentDistinctCalls++;
    return records.take(limit).toList();
  }

  @override
  Future<PlayHistoryStats> getHistoryStats() async {
    statsCalls++;
    return PlayHistoryStats(
      totalCount: records.length,
      todayCount: records.length,
      weekCount: records.length,
      totalDurationMs: 0,
      todayDurationMs: 0,
      weekDurationMs: 0,
    );
  }
```

- [ ] **Step 3: Run tests and verify provider failure**

Run: `flutter test test/providers/play_history_provider_phase4_test.dart --plain-name "recent and stats use purpose-specific repository queries"`
Expected: FAIL because current `recentPlayHistoryProvider` and `playHistoryStatsProvider` derive from `playHistorySnapshotProvider`, so `snapshotCalls` is not 0 and fake purpose-specific methods are not called.

- [ ] **Step 4: Refactor providers to purpose-specific async providers**

In `lib/providers/play_history_provider.dart`, replace `recentPlayHistoryProvider` with:

```dart
final recentPlayHistoryProvider =
    FutureProvider.autoDispose<List<PlayHistory>>((ref) async {
  final repo = ref.watch(playHistoryRepositoryProvider);
  return repo.getRecentHistoryDistinct(limit: 10);
});
```

Replace `playHistoryStatsProvider` with:

```dart
final playHistoryStatsProvider =
    FutureProvider.autoDispose<PlayHistoryStats>((ref) async {
  final repo = ref.watch(playHistoryRepositoryProvider);
  return repo.getHistoryStats();
});
```

This preserves existing UI call sites because `_RecentHistorySection` in `lib/ui/pages/home/home_page.dart` and `_buildStatsCard()` in `lib/ui/pages/history/play_history_page.dart` already call `.when(...)` on the watched provider value.

Keep `playHistorySnapshotProvider`, `filteredPlayHistoryProvider`, and `groupedPlayHistoryProvider` for the history page until Task 5 flattens rows.

- [ ] **Step 5: Make repository queryHistory use query-level pagination for the common path**

In `lib/data/repositories/play_history_repository.dart`, change the beginning of `queryHistory()` to fast-path unfiltered time sorting:

```dart
    final hasFilters = (sourceTypes != null && sourceTypes.isNotEmpty) ||
        startDate != null ||
        endDate != null ||
        (searchKeyword != null && searchKeyword.isNotEmpty);

    if (!hasFilters && sortOrder == HistorySortOrder.timeDesc) {
      return _isar.playHistorys
          .where()
          .sortByPlayedAtDesc()
          .offset(offset)
          .limit(limit)
          .findAll();
    }
    if (!hasFilters && sortOrder == HistorySortOrder.timeAsc) {
      return _isar.playHistorys
          .where()
          .sortByPlayedAt()
          .offset(offset)
          .limit(limit)
          .findAll();
    }

    var records = await _isar.playHistorys.where().findAll();
```

Leave filtered/search/playCount behavior unchanged in this task to avoid a large query rewrite.

- [ ] **Step 6: Verify history query/provider tests and commit**

Run: `dart format lib/data/repositories/play_history_repository.dart lib/providers/play_history_provider.dart test/data/repositories/play_history_repository_phase4_test.dart test/providers/play_history_provider_phase4_test.dart`
Expected: files formatted.

Run: `flutter test test/data/repositories/play_history_repository_phase4_test.dart test/providers/play_history_provider_phase4_test.dart`
Expected: PASS.

Run: `git add lib/data/repositories/play_history_repository.dart lib/providers/play_history_provider.dart test/data/repositories/play_history_repository_phase4_test.dart test/providers/play_history_provider_phase4_test.dart && git commit -m "perf(history): split recent and stats queries"`
Expected: commit succeeds.

---

### Task 5: Flatten Play History Timeline Rows

**Files:**
- Modify: `lib/providers/play_history_provider.dart:198-211`, `lib/providers/play_history_provider.dart:360-366`
- Modify: `lib/ui/pages/history/play_history_page.dart:424-573`
- Modify: `test/ui/pages/history/play_history_page_phase2_test.dart`

- [ ] **Step 1: Write static UI regression test for non-eager history rows**

Append this test to `test/ui/pages/history/play_history_page_phase2_test.dart`:

```dart
  group('history page lazy timeline structure', () {
    test('timeline list does not expand grouped histories with spread map', () {
      final source = File('lib/ui/pages/history/play_history_page.dart')
          .readAsStringSync();
      final timelineBody = _methodBody(source, '_buildTimelineList');
      final dateGroupBody = _methodBody(source, '_buildDateGroup');

      expect(timelineBody, contains('ListView.builder'));
      expect(timelineBody, contains('HistoryTimelineRow'));
      expect(dateGroupBody, isNot(contains('...histories.map')));
    });
  });

String _methodBody(String source, String name) {
  final start = source.indexOf(name);
  expect(start, isNonNegative, reason: 'method $name should exist');
  final firstBrace = source.indexOf('{', start);
  var depth = 0;
  for (var i = firstBrace; i < source.length; i++) {
    final char = source[i];
    if (char == '{') depth++;
    if (char == '}') depth--;
    if (depth == 0) return source.substring(firstBrace, i + 1);
  }
  fail('method $name body did not close');
}
```

Add `import 'dart:io';` at the top of the file.

- [ ] **Step 2: Run the static test and verify it fails**

Run: `flutter test test/ui/pages/history/play_history_page_phase2_test.dart --plain-name "timeline list does not expand grouped histories with spread map"`
Expected: FAIL because `_buildDateGroup()` currently contains `...histories.map(...)`.

- [ ] **Step 3: Add flattened row model to provider file**

In `lib/providers/play_history_provider.dart`, add after `_groupHistoryByDate()`:

```dart
sealed class HistoryTimelineRow {
  const HistoryTimelineRow();
}

class HistoryDateHeaderRow extends HistoryTimelineRow {
  final DateTime date;
  final List<PlayHistory> histories;

  const HistoryDateHeaderRow({
    required this.date,
    required this.histories,
  });
}

class HistoryTrackRow extends HistoryTimelineRow {
  final DateTime date;
  final PlayHistory history;

  const HistoryTrackRow({
    required this.date,
    required this.history,
  });
}

List<HistoryTimelineRow> buildHistoryTimelineRows(
  Map<DateTime, List<PlayHistory>> grouped,
  Set<DateTime> collapsedGroups,
) {
  final sortedDates = grouped.keys.toList()..sort((a, b) => b.compareTo(a));
  final rows = <HistoryTimelineRow>[];
  for (final date in sortedDates) {
    final histories = grouped[date]!;
    rows.add(HistoryDateHeaderRow(date: date, histories: histories));
    if (!collapsedGroups.contains(date)) {
      for (final history in histories) {
        rows.add(HistoryTrackRow(date: date, history: history));
      }
    }
  }
  return rows;
}
```

- [ ] **Step 4: Refactor `_buildTimelineList()` to render flattened rows**

In `lib/ui/pages/history/play_history_page.dart`, change the non-empty branch to:

```dart
        final pageState = ref.watch(playHistoryPageProvider);
        final notifier = ref.read(playHistoryPageProvider.notifier);
        final rows = buildHistoryTimelineRows(grouped, _collapsedGroups);

        return ListView.builder(
          controller: _scrollController,
          itemCount: rows.length,
          cacheExtent: 500,
          itemBuilder: (context, index) {
            final row = rows[index];
            return RepaintBoundary(
              child: switch (row) {
                HistoryDateHeaderRow(:final date, :final histories) =>
                  _buildDateHeader(context, date, histories, pageState, notifier),
                HistoryTrackRow(:final history) => _buildTimelineItem(
                    context,
                    history,
                    isMultiSelectMode: pageState.isMultiSelectMode,
                    isSelected: pageState.selectedIds.contains(history.id),
                    onToggleSelection: () => notifier.toggleSelection(history.id),
                    onEnterMultiSelect: () =>
                        notifier.enterMultiSelectMode(history.id),
                  ),
              },
            );
          },
        );
```

Rename `_buildDateGroup()` to `_buildDateHeader()` and remove the `if (!isCollapsed) ...histories.map(...)` section. Keep the header UI and `_toggleGroupCollapse(date)` behavior unchanged.

- [ ] **Step 5: Verify flattened timeline and commit**

Run: `dart format lib/providers/play_history_provider.dart lib/ui/pages/history/play_history_page.dart test/ui/pages/history/play_history_page_phase2_test.dart`
Expected: files formatted.

Run: `flutter test test/ui/pages/history/play_history_page_phase2_test.dart test/providers/play_history_provider_phase4_test.dart`
Expected: PASS.

Run: `git add lib/providers/play_history_provider.dart lib/ui/pages/history/play_history_page.dart test/ui/pages/history/play_history_page_phase2_test.dart && git commit -m "perf(history): flatten timeline rows"`
Expected: commit succeeds.

---

### Task 6: Split Low-Frequency Queue State Provider

**Files:**
- Modify: `lib/services/audio/player_state.dart:19-41`
- Modify: `lib/services/audio/audio_provider.dart:2492-2675`
- Test: `test/services/audio/audio_queue_state_provider_test.dart`

- [ ] **Step 1: Write provider-level queue isolation test**

Create `test/services/audio/audio_queue_state_provider_test.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/models/track.dart';
import 'package:fmp/services/audio/audio_provider.dart';

void main() {
  group('queueStateProvider', () {
    test('queueProvider follows queueStateProvider instead of PlayerState queue', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final firstQueue = [_track('one')];
      final secondQueue = [_track('two')];

      container.read(queueStateProvider.notifier).state =
          QueueState(queue: firstQueue, queueVersion: 1);
      expect(container.read(queueProvider), firstQueue);

      container.read(audioControllerProvider.notifier).state =
          container.read(audioControllerProvider).copyWith(
                queue: secondQueue,
                position: const Duration(seconds: 30),
              );

      expect(container.read(queueProvider), firstQueue);
    });
  });
}

Track _track(String sourceId) => Track()
  ..sourceId = sourceId
  ..sourceType = SourceType.youtube
  ..title = sourceId;
```

- [ ] **Step 2: Run the queue provider test and verify it fails**

Run: `flutter test test/services/audio/audio_queue_state_provider_test.dart`
Expected: FAIL because `QueueState`/`queueStateProvider` do not exist and `queueProvider` still reads `audioControllerProvider.select((s) => s.queue)`.

- [ ] **Step 3: Add queue state type and provider**

In `lib/services/audio/audio_provider.dart`, before `audioControllerProvider`, add:

```dart
class QueueState {
  final List<Track> queue;
  final List<Track> upcomingTracks;
  final int? currentIndex;
  final Track? queueTrack;
  final bool canPlayPrevious;
  final bool canPlayNext;
  final bool isShuffleEnabled;
  final LoopMode loopMode;
  final int queueVersion;
  final bool isMixMode;
  final String? mixTitle;
  final bool isLoadingMoreMix;

  const QueueState({
    this.queue = const [],
    this.upcomingTracks = const [],
    this.currentIndex,
    this.queueTrack,
    this.canPlayPrevious = false,
    this.canPlayNext = false,
    this.isShuffleEnabled = false,
    this.loopMode = LoopMode.none,
    this.queueVersion = 0,
    this.isMixMode = false,
    this.mixTitle,
    this.isLoadingMoreMix = false,
  });

  QueueState copyWith({
    List<Track>? queue,
    List<Track>? upcomingTracks,
    int? currentIndex,
    Track? queueTrack,
    bool? canPlayPrevious,
    bool? canPlayNext,
    bool? isShuffleEnabled,
    LoopMode? loopMode,
    int? queueVersion,
    bool? isMixMode,
    String? mixTitle,
    bool clearMixTitle = false,
    bool? isLoadingMoreMix,
  }) {
    return QueueState(
      queue: queue ?? this.queue,
      upcomingTracks: upcomingTracks ?? this.upcomingTracks,
      currentIndex: currentIndex ?? this.currentIndex,
      queueTrack: queueTrack ?? this.queueTrack,
      canPlayPrevious: canPlayPrevious ?? this.canPlayPrevious,
      canPlayNext: canPlayNext ?? this.canPlayNext,
      isShuffleEnabled: isShuffleEnabled ?? this.isShuffleEnabled,
      loopMode: loopMode ?? this.loopMode,
      queueVersion: queueVersion ?? this.queueVersion,
      isMixMode: isMixMode ?? this.isMixMode,
      mixTitle: clearMixTitle ? null : (mixTitle ?? this.mixTitle),
      isLoadingMoreMix: isLoadingMoreMix ?? this.isLoadingMoreMix,
    );
  }
}

final queueStateProvider = StateProvider<QueueState>((ref) => const QueueState());
```

- [ ] **Step 4: Write queue state from `_updateQueueState()`**

In `AudioController`, add a callback field near `onLyricsAutoMatchStateChanged`:

```dart
  void Function(QueueState queueState)? onQueueStateChanged;
```

Then in `_updateQueueState()`, after computing all queue fields and before `state = state.copyWith(...)`, emit:

```dart
    final nextQueueState = QueueState(
      queue: queue,
      upcomingTracks: upcomingTracks,
      currentIndex: currentIndex,
      queueTrack: queueTrack,
      isShuffleEnabled: _queueManager.isShuffleEnabled,
      loopMode: _queueManager.loopMode,
      canPlayPrevious: canPlayPrevious,
      canPlayNext: canPlayNext,
      queueVersion: state.queueVersion + 1,
      isMixMode: state.isMixMode,
      mixTitle: state.mixTitle,
      isLoadingMoreMix: state.isLoadingMoreMix,
    );
    onQueueStateChanged?.call(nextQueueState);
```

In the provider creation block, wire it:

```dart
  controller.onQueueStateChanged = (queueState) {
    ref.read(queueStateProvider.notifier).state = queueState;
  };
```

Keep writing queue fields into `PlayerState` in this task for compatibility with existing UI. The goal is to move `queueProvider` first, not remove fields yet.

- [ ] **Step 5: Point queue convenience providers to `queueStateProvider`**

Replace `queueProvider` with:

```dart
final queueProvider = Provider<List<Track>>((ref) {
  return ref.watch(queueStateProvider.select((s) => s.queue));
});
```

Add these providers for UI migration if absent:

```dart
final queueVersionProvider = Provider<int>((ref) {
  return ref.watch(queueStateProvider.select((s) => s.queueVersion));
});

final queueTrackProvider = Provider<Track?>((ref) {
  return ref.watch(queueStateProvider.select((s) => s.queueTrack));
});
```

- [ ] **Step 6: Verify queue provider split and commit**

Run: `dart format lib/services/audio/audio_provider.dart lib/services/audio/player_state.dart test/services/audio/audio_queue_state_provider_test.dart`
Expected: files formatted.

Run: `flutter test test/services/audio/audio_queue_state_provider_test.dart test/services/audio/audio_controller_phase1_test.dart test/ui/pages/queue/queue_page_reorder_test.dart`
Expected: PASS.

Run: `git add lib/services/audio/audio_provider.dart lib/services/audio/player_state.dart test/services/audio/audio_queue_state_provider_test.dart && git commit -m "perf(audio): expose queue state separately"`
Expected: commit succeeds.

---

### Task 7: Source Ownership Static Guard

**Files:**
- Modify: `lib/services/audio/audio_provider.dart:815-841`, `lib/services/audio/audio_provider.dart:1503-1603`
- Modify: `lib/providers/playlist_provider.dart:347-377`
- Modify: `lib/providers/popular_provider.dart:180-194`
- Modify: `lib/services/import/import_service.dart:344-356`
- Modify: `lib/services/cache/ranking_cache_service.dart:61`
- Create: `test/data/sources/source_ownership_phase3_test.dart`

- [ ] **Step 1: Write a static guard for direct YouTubeSource construction**

Create `test/data/sources/source_ownership_phase3_test.dart`:

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Source ownership', () {
    test('runtime code does not construct ad-hoc YouTubeSource instances', () {
      const checkedFiles = [
        'lib/services/audio/audio_provider.dart',
        'lib/providers/playlist_provider.dart',
        'lib/providers/popular_provider.dart',
        'lib/services/import/import_service.dart',
        'lib/services/cache/ranking_cache_service.dart',
      ];

      final offenders = <String>[];
      for (final path in checkedFiles) {
        final source = File(path).readAsStringSync();
        if (source.contains('YouTubeSource(')) {
          offenders.add(path);
        }
      }

      expect(offenders, isEmpty);
    });
  });
}
```

- [ ] **Step 2: Run the static guard and verify it fails**

Run: `flutter test test/data/sources/source_ownership_phase3_test.dart`
Expected: FAIL and list files that still call `YouTubeSource()` directly.

- [ ] **Step 3: Replace direct construction in provider/service constructors**

Use the existing `sourceManagerProvider`/typed source providers where a Riverpod ref is available:

- In `lib/providers/playlist_provider.dart`, use `ref.watch(youtubeSourceProvider)` instead of constructing `YouTubeSource()`.
- In `lib/providers/popular_provider.dart`, change `rankingVideosProvider` to pass `ref.watch(bilibiliSourceProvider)` and `youtubeTrendingProvider` to pass `ref.watch(youtubeSourceProvider)`. Remove `YouTubeTrendingNotifier.dispose()` disposing `_source`, because the shared source is owned by `SourceManager`.
- In `lib/services/import/import_service.dart`, replace `YouTubeSource()` with `_sourceManager.getSource(SourceType.youtube) as YouTubeSource?` and keep the existing failure path if it is null.
- In `lib/services/cache/ranking_cache_service.dart`, make `bilibiliSource` and `youtubeSource` required constructor parameters so the service no longer constructs sources internally. Because `main.dart` currently initializes the global singleton outside `ProviderScope`, also move the singleton creation into `rankingCacheServiceProvider` or expose a bootstrap function that receives `SourceManager`-owned `bilibiliSourceProvider`/`youtubeSourceProvider`. Do not dispose these sources in `RankingCacheService.dispose()` because `SourceManager` owns them.
- In `lib/services/audio/audio_provider.dart`, extend the constructor with `YouTubeSource? youtubeSource`; add a `_youtubeSource` field; change `startMixFromPlaylist()` and `_loadMoreMixTracks()` to use `_mixTracksFetcher` first, then `_youtubeSource?.fetchMixTracks(...)`. Wire `youtubeSource: ref.watch(youtubeSourceProvider)` in `audioControllerProvider`. Remove local `YouTubeSource()` creation and disposal from these methods.

Keep behavior identical: if a YouTube-specific source is unavailable, throw/log the same error path the current code uses.

- [ ] **Step 4: Verify source ownership and behavior tests**

Run: `dart format lib/services/audio/audio_provider.dart lib/providers/playlist_provider.dart lib/providers/popular_provider.dart lib/services/import/import_service.dart lib/services/cache/ranking_cache_service.dart test/data/sources/source_ownership_phase3_test.dart`
Expected: files formatted.

Run: `flutter test test/data/sources/source_ownership_phase3_test.dart test/services/audio/audio_controller_mix_boundary_test.dart test/services/import/import_service_phase4_test.dart`
Expected: PASS.

Run: `git add lib/services/audio/audio_provider.dart lib/providers/playlist_provider.dart lib/providers/popular_provider.dart lib/services/import/import_service.dart lib/services/cache/ranking_cache_service.dart test/data/sources/source_ownership_phase3_test.dart && git commit -m "refactor(source): centralize youtube source ownership"`
Expected: commit succeeds.

---

### Task 8: Final Phase 3 Validation

**Files:**
- Verify: all files touched by Tasks 1-7
- Modify docs only if implementation changes durable project guidance in `CLAUDE.md`

- [ ] **Step 1: Run focused Phase 3 tests**

Run:

```bash
flutter test \
  test/services/library/playlist_service_bidirectional_test.dart \
  test/services/library/playlist_service_transaction_source_test.dart \
  test/services/download/download_completion_transaction_test.dart \
  test/services/download/download_service_phase1_test.dart \
  test/data/repositories/play_history_repository_phase4_test.dart \
  test/providers/play_history_provider_phase4_test.dart \
  test/ui/pages/history/play_history_page_phase2_test.dart \
  test/services/audio/audio_queue_state_provider_test.dart \
  test/services/audio/audio_controller_phase1_test.dart \
  test/ui/pages/queue/queue_page_reorder_test.dart \
  test/data/sources/source_ownership_phase3_test.dart
```

Expected: all tests pass.

- [ ] **Step 2: Run analyzer**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 3: Inspect git diff for scope creep**

Run: `git diff --stat HEAD~7..HEAD` if each task committed, or `git diff --stat` if executing without intermediate commits.
Expected: only Phase 3 files from this plan changed. No generated Isar schema files should change in Phase 3.

- [ ] **Step 4: Manual smoke checklist**

Run or manually verify if the app environment is available:

```bash
flutter run
```

Manual checks:
- Create a playlist, add one song, duplicate playlist, confirm the song appears in both playlists.
- Remove a song from one playlist and confirm shared songs remain in the other playlist.
- Download a small test track and confirm it reaches completed state and appears as downloaded.
- Open history page with multiple dates and collapse/expand a date group.
- Start playback with a queue, open queue page, reorder one item, and confirm current track/next track behavior is unchanged.
- Start a YouTube Mix/ranking/import path that previously used direct source construction, if credentials/network are available.

- [ ] **Step 5: Commit validation-only doc updates if needed**

If the implementation changes durable project guidance, update `CLAUDE.md` with the exact new queue state provider or source ownership rule and commit:

```bash
git add CLAUDE.md
git commit -m "docs: document phase 3 refactor boundaries"
```

If no durable guidance changed, do not edit docs.

---

## Self-Review Notes

- **Spec coverage:** Covers every Phase 3 candidate from `docs/superpowers/specs/2026-04-24-review-driven-refactor-design.md`: Playlist/Track transactions, Download completion transaction, play history query/list structure, queue-state split, Source ownership, and avoids large `AudioController` decomposition beyond the queue-state seam.
- **Placeholder scan:** No placeholder tokens remain; each task has exact paths, commands, and concrete code snippets.
- **Type consistency:** Uses existing project types: `PlaylistService`, `Track`, `Playlist`, `DownloadTask`, `DownloadStatus`, `PlayHistory`, `PlayHistoryStats`, `QueueState`, `SourceManager`, and `YouTubeSource`. New names are introduced before later references.
- **Scope control:** Does not add Isar unique indexes, does not rewrite audio playback semantics, does not change radio/audio ownership, and does not move downloaded-category scanning or download manager row flattening (Phase 4 items).
