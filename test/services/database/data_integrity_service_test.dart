import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/models/account.dart';
import 'package:fmp/data/models/download_task.dart';
import 'package:fmp/data/models/play_queue.dart';
import 'package:fmp/data/models/playlist.dart';
import 'package:fmp/data/models/track.dart';
import 'package:fmp/services/database/data_integrity_service.dart';
import 'package:isar/isar.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DataIntegrityService', () {
    setUpAll(() async {
      await Isar.initializeIsarCore(
        libraries: {Abi.current(): await _resolveIsarLibraryPath()},
      );
    });

    test('scan reports duplicate logical records without modifying data',
        () async {
      final harness = await _createHarness();
      addTearDown(harness.dispose);

      await harness.seedDuplicates();

      final report = await harness.service.scan();

      expect(report.duplicateTrackKeys, contains('youtube:same'));
      expect(report.duplicateDownloadSavePaths,
          contains('/downloads/Playlist/Song/audio.m4a'));
      expect(report.duplicateAccountPlatforms, contains(SourceType.youtube));
      expect(report.playQueueCount, 2);
      expect(report.hasIssues, isTrue);

      final tracks = await harness.isar.tracks.where().findAll();
      final tasks = await harness.isar.downloadTasks.where().findAll();
      final accounts = await harness.isar.accounts.where().findAll();
      final queues = await harness.isar.playQueues.where().findAll();
      expect(tracks, hasLength(3));
      expect(tasks, hasLength(2));
      expect(accounts, hasLength(2));
      expect(queues, hasLength(2));
    });

    test('repair merges or removes duplicates using deterministic keep rules',
        () async {
      final harness = await _createHarness();
      addTearDown(harness.dispose);

      await harness.seedDuplicates();

      final result = await harness.service.repair();

      expect(result.removedTrackIds, hasLength(1));
      expect(result.removedDownloadTaskIds, hasLength(1));
      expect(result.removedAccountIds, hasLength(1));
      expect(result.removedPlayQueueIds, hasLength(1));

      final report = await harness.service.scan();
      expect(report.hasIssues, isFalse);

      await harness.service.repair();
      final secondReport = await harness.service.scan();
      expect(secondReport.hasIssues, isFalse);

      final tracks = await harness.isar.tracks.where().findAll();
      expect(tracks, hasLength(2));
      expect(tracks.map((track) => track.title),
          containsAll(['Complete Track', 'Other Track']));
      final keptTrack = tracks.singleWhere((track) => track.sourceId == 'same');
      expect(keptTrack.title, 'Complete Track');
      expect(keptTrack.thumbnailUrl, 'https://img.example/cover.jpg');

      final playlists = await harness.isar.playlists.where().findAll();
      expect(playlists.single.trackIds, [keptTrack.id]);
      expect(playlists.single.trackIds,
          isNot(contains(harness.trackIdsByTitle['Sparse Track'])));

      final tasks = await harness.isar.downloadTasks.where().findAll();
      expect(tasks, hasLength(1));
      expect(tasks.single.status, DownloadStatus.completed);
      expect(tasks.single.trackId, keptTrack.id);

      final accounts = await harness.isar.accounts.where().findAll();
      expect(accounts, hasLength(1));
      expect(accounts.single.isLoggedIn, isTrue);
      expect(accounts.single.userName, 'Logged In');

      final queues = await harness.isar.playQueues.where().findAll();
      expect(queues, hasLength(1));
      expect(queues.single.trackIds, [
        keptTrack.id,
        harness.trackIdsByTitle['Other Track'],
      ]);
    });

    test('repair preserves duplicate track playlist download metadata',
        () async {
      final harness = await _createHarness();
      addTearDown(harness.dispose);

      await harness.seedTrackMetadataMergeDuplicate();

      await harness.service.repair();

      final tracks = await harness.isar.tracks.where().findAll();
      expect(tracks, hasLength(1));
      final keptTrack = tracks.single;
      expect(keptTrack.title, 'Kept Rich Track');
      expect(keptTrack.thumbnailUrl, 'https://img.example/rich.jpg');
      expect(keptTrack.durationMs, 240000);
      expect(keptTrack.artist, 'Recovered Artist');
      expect(
        keptTrack.getDownloadPath(42, playlistName: 'Downloaded Playlist'),
        '/downloads/Downloaded Playlist/Rich Track/audio.m4a',
      );
    });

    test('repair remaps shuffled queue original order', () async {
      final harness = await _createHarness();
      addTearDown(harness.dispose);

      await harness.seedShuffledQueueDuplicateTracks();

      await harness.service.repair();

      final tracks = await harness.isar.tracks.where().findAll();
      final keptTrack =
          tracks.singleWhere((track) => track.sourceId == 'queue');
      final otherTrack =
          tracks.singleWhere((track) => track.sourceId == 'other');
      final queue = (await harness.isar.playQueues.where().findAll()).single;

      expect(queue.trackIds, [otherTrack.id, keptTrack.id]);
      expect(queue.originalOrder, [keptTrack.id, otherTrack.id]);
      expect(queue.currentIndex, 1);
      expect(queue.currentTrackId, keptTrack.id);
    });

    test('repair clamps queue current index after deduping track ids',
        () async {
      final harness = await _createHarness();
      addTearDown(harness.dispose);

      await harness.seedInvalidCurrentIndexQueueDuplicateTracks();

      await harness.service.repair();

      final keptTrack = (await harness.isar.tracks.where().findAll()).single;
      final queue = (await harness.isar.playQueues.where().findAll()).single;

      expect(queue.trackIds, [keptTrack.id]);
      expect(queue.currentIndex, 0);
      expect(queue.currentTrackId, keptTrack.id);
    });

    test('repair preserves duplicate track state metadata', () async {
      final harness = await _createHarness();
      addTearDown(harness.dispose);

      await harness.seedTrackStateMetadataDuplicate();

      await harness.service.repair();

      final track = (await harness.isar.tracks.where().findAll()).single;
      expect(track.title, 'Kept Default State Track');
      expect(track.isVip, isTrue);
      expect(track.isAvailable, isFalse);
      expect(track.unavailableReason, 'Removed track unavailable');
      expect(track.createdAt, DateTime(2026, 4, 20));
      expect(track.updatedAt, DateTime(2026, 4, 26));
    });

    test('repair preserves duplicate account profile metadata', () async {
      final harness = await _createHarness();
      addTearDown(harness.dispose);

      await harness.seedAccountProfileMetadataDuplicate();

      await harness.service.repair();

      final account = (await harness.isar.accounts.where().findAll()).single;
      expect(account.isLoggedIn, isTrue);
      expect(account.userId, 'rich-user-id');
      expect(account.userName, 'Rich User');
      expect(account.avatarUrl, 'https://img.example/avatar.jpg');
      expect(account.isVip, isTrue);
      expect(account.loginAt, DateTime(2026, 4, 20));
      expect(account.lastRefreshed, DateTime(2026, 4, 26));
    });

    test('repair keeps populated queue over newer empty queue', () async {
      final harness = await _createHarness();
      addTearDown(harness.dispose);

      await harness.seedNewerEmptyQueueDuplicate();

      await harness.service.repair();

      final track = (await harness.isar.tracks.where().findAll()).single;
      final queue = (await harness.isar.playQueues.where().findAll()).single;
      expect(queue.trackIds, [track.id]);
      expect(queue.currentIndex, 0);
    });
  });
}

class _Harness {
  _Harness(this.isar) : service = DataIntegrityService(isar);

  final Isar isar;
  final DataIntegrityService service;
  final trackIdsByTitle = <String, int>{};

  Future<void> seedDuplicates() async {
    await isar.writeTxn(() async {
      final trackIds = await isar.tracks.putAll([
        Track()
          ..sourceId = 'same'
          ..sourceType = SourceType.youtube
          ..title = 'Sparse Track'
          ..createdAt = DateTime(2026, 4, 24),
        Track()
          ..sourceId = 'same'
          ..sourceType = SourceType.youtube
          ..title = 'Complete Track'
          ..thumbnailUrl = 'https://img.example/cover.jpg'
          ..durationMs = 180000
          ..createdAt = DateTime(2026, 4, 25),
        Track()
          ..sourceId = 'other'
          ..sourceType = SourceType.youtube
          ..title = 'Other Track'
          ..createdAt = DateTime(2026, 4, 25),
      ]);
      final sparseTrackId = trackIds[0];
      final completeTrackId = trackIds[1];
      final otherTrackId = trackIds[2];
      trackIdsByTitle['Sparse Track'] = sparseTrackId;
      trackIdsByTitle['Complete Track'] = completeTrackId;
      trackIdsByTitle['Other Track'] = otherTrackId;

      await isar.playlists.put(Playlist()
        ..name = 'Mixed Playlist'
        ..trackIds = [sparseTrackId, completeTrackId]
        ..createdAt = DateTime(2026, 4, 25));
      await isar.downloadTasks.putAll([
        DownloadTask()
          ..trackId = sparseTrackId
          ..savePath = '/downloads/Playlist/Song/audio.m4a'
          ..status = DownloadStatus.pending
          ..createdAt = DateTime(2026, 4, 24),
        DownloadTask()
          ..trackId = sparseTrackId
          ..savePath = '/downloads/Playlist/Song/audio.m4a'
          ..status = DownloadStatus.completed
          ..createdAt = DateTime(2026, 4, 25)
          ..completedAt = DateTime(2026, 4, 25, 1),
      ]);
      await isar.accounts.putAll([
        Account()
          ..platform = SourceType.youtube
          ..isLoggedIn = false
          ..userName = 'Logged Out'
          ..lastRefreshed = DateTime(2026, 4, 24),
        Account()
          ..platform = SourceType.youtube
          ..isLoggedIn = true
          ..userName = 'Logged In'
          ..lastRefreshed = DateTime(2026, 4, 25),
      ]);
      await isar.playQueues.putAll([
        PlayQueue()
          ..trackIds = [sparseTrackId]
          ..lastUpdated = DateTime(2026, 4, 24),
        PlayQueue()
          ..trackIds = [sparseTrackId, completeTrackId, otherTrackId]
          ..lastUpdated = DateTime(2026, 4, 25),
      ]);
    });
  }

  Future<void> seedTrackMetadataMergeDuplicate() async {
    await isar.writeTxn(() async {
      await isar.tracks.putAll([
        Track()
          ..sourceId = 'merge'
          ..sourceType = SourceType.youtube
          ..title = 'Removed Download Track'
          ..artist = 'Recovered Artist'
          ..playlistInfo = [
            PlaylistDownloadInfo()
              ..playlistId = 42
              ..playlistName = 'Downloaded Playlist'
              ..downloadPath =
                  '/downloads/Downloaded Playlist/Rich Track/audio.m4a',
          ]
          ..createdAt = DateTime(2026, 4, 24),
        Track()
          ..sourceId = 'merge'
          ..sourceType = SourceType.youtube
          ..title = 'Kept Rich Track'
          ..thumbnailUrl = 'https://img.example/rich.jpg'
          ..durationMs = 240000
          ..createdAt = DateTime(2026, 4, 25),
      ]);
    });
  }

  Future<void> seedShuffledQueueDuplicateTracks() async {
    await isar.writeTxn(() async {
      final trackIds = await isar.tracks.putAll([
        Track()
          ..sourceId = 'queue'
          ..sourceType = SourceType.youtube
          ..title = 'Sparse Queue Track'
          ..createdAt = DateTime(2026, 4, 24),
        Track()
          ..sourceId = 'queue'
          ..sourceType = SourceType.youtube
          ..title = 'Complete Queue Track'
          ..thumbnailUrl = 'https://img.example/queue.jpg'
          ..createdAt = DateTime(2026, 4, 25),
        Track()
          ..sourceId = 'other'
          ..sourceType = SourceType.youtube
          ..title = 'Queue Other Track'
          ..createdAt = DateTime(2026, 4, 25),
      ]);
      final sparseTrackId = trackIds[0];
      final completeTrackId = trackIds[1];
      final otherTrackId = trackIds[2];
      await isar.playQueues.put(
        PlayQueue()
          ..trackIds = [otherTrackId, sparseTrackId, completeTrackId]
          ..currentIndex = 2
          ..isShuffleEnabled = true
          ..originalOrder = [sparseTrackId, otherTrackId, completeTrackId]
          ..lastUpdated = DateTime(2026, 4, 25),
      );
    });
  }

  Future<void> seedInvalidCurrentIndexQueueDuplicateTracks() async {
    await isar.writeTxn(() async {
      final trackIds = await isar.tracks.putAll([
        Track()
          ..sourceId = 'invalid-index'
          ..sourceType = SourceType.youtube
          ..title = 'Sparse Invalid Index Track'
          ..createdAt = DateTime(2026, 4, 24),
        Track()
          ..sourceId = 'invalid-index'
          ..sourceType = SourceType.youtube
          ..title = 'Complete Invalid Index Track'
          ..thumbnailUrl = 'https://img.example/invalid-index.jpg'
          ..createdAt = DateTime(2026, 4, 25),
      ]);
      await isar.playQueues.put(
        PlayQueue()
          ..trackIds = [trackIds[0], trackIds[1]]
          ..currentIndex = 1
          ..lastUpdated = DateTime(2026, 4, 25),
      );
    });
  }

  Future<void> seedTrackStateMetadataDuplicate() async {
    await isar.writeTxn(() async {
      await isar.tracks.putAll([
        Track()
          ..sourceId = 'state'
          ..sourceType = SourceType.youtube
          ..title = 'Removed State Track'
          ..isVip = true
          ..isAvailable = false
          ..unavailableReason = 'Removed track unavailable'
          ..createdAt = DateTime(2026, 4, 20)
          ..updatedAt = DateTime(2026, 4, 26),
        Track()
          ..sourceId = 'state'
          ..sourceType = SourceType.youtube
          ..title = 'Kept Default State Track'
          ..thumbnailUrl = 'https://img.example/state.jpg'
          ..createdAt = DateTime(2026, 4, 25)
          ..updatedAt = DateTime(2026, 4, 25),
      ]);
    });
  }

  Future<void> seedAccountProfileMetadataDuplicate() async {
    await isar.writeTxn(() async {
      await isar.accounts.putAll([
        Account()
          ..platform = SourceType.netease
          ..isLoggedIn = true
          ..loginAt = DateTime(2026, 4, 25)
          ..lastRefreshed = DateTime(2026, 4, 25),
        Account()
          ..platform = SourceType.netease
          ..isLoggedIn = false
          ..userId = 'rich-user-id'
          ..userName = 'Rich User'
          ..avatarUrl = 'https://img.example/avatar.jpg'
          ..isVip = true
          ..loginAt = DateTime(2026, 4, 20)
          ..lastRefreshed = DateTime(2026, 4, 26),
      ]);
    });
  }

  Future<void> seedNewerEmptyQueueDuplicate() async {
    await isar.writeTxn(() async {
      final trackId = await isar.tracks.put(
        Track()
          ..sourceId = 'queue-populated'
          ..sourceType = SourceType.youtube
          ..title = 'Queue Populated Track'
          ..createdAt = DateTime(2026, 4, 25),
      );
      await isar.playQueues.putAll([
        PlayQueue()
          ..trackIds = [trackId]
          ..currentIndex = 0
          ..lastUpdated = DateTime(2026, 4, 24),
        PlayQueue()
          ..trackIds = []
          ..currentIndex = 0
          ..lastUpdated = DateTime(2026, 4, 25),
      ]);
    });
  }

  Future<void> dispose() async {
    final dir = Directory(isar.directory!);
    await isar.close(deleteFromDisk: true);
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  }
}

Future<_Harness> _createHarness() async {
  final tempDir = await Directory.systemTemp.createTemp(
    'data_integrity_service_test_',
  );
  final isar = await Isar.open(
    [
      TrackSchema,
      PlaylistSchema,
      DownloadTaskSchema,
      AccountSchema,
      PlayQueueSchema,
    ],
    directory: tempDir.path,
    name: 'data_integrity_service_test',
  );
  return _Harness(isar);
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
