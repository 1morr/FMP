import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/models/play_queue.dart';
import 'package:fmp/data/models/settings.dart';
import 'package:fmp/data/models/track.dart';
import 'package:fmp/data/repositories/queue_repository.dart';
import 'package:fmp/data/repositories/settings_repository.dart';
import 'package:fmp/data/repositories/track_repository.dart';
import 'package:fmp/services/audio/queue_persistence_manager.dart';
import 'package:isar_community/isar.dart';
import '../../support/isar_test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('QueuePersistenceManager Task 1 regression', () {
    test(
      'queue persistence manager owns playback position restore selectors',
      () async {
        final source = await File(
          '${Directory.current.path}/lib/services/audio/queue_persistence_manager.dart',
        ).readAsString();

        expect(source.contains('class AudioRuntimeSettings'), isTrue);
        expect(
          source.contains(
            'Future<AudioRuntimeSettings> getPositionRestoreSettings()',
          ),
          isTrue,
        );
      },
    );

    test(
      'queue manager does not directly own persisted mix metadata fields',
      () async {
        final source = await File(
          '${Directory.current.path}/lib/services/audio/queue_manager.dart',
        ).readAsString();

        expect(source.contains('bool get isMixMode'), isFalse);
        expect(source.contains('String? get mixPlaylistId'), isFalse);
        expect(source.contains('String? get mixSeedVideoId'), isFalse);
        expect(source.contains('String? get mixTitle'), isFalse);
        expect(source.contains('_currentQueue!.isMixMode = false'), isFalse);
        expect(source.contains('_currentQueue!.mixPlaylistId = null'), isFalse);
        expect(
          source.contains('_currentQueue!.mixSeedVideoId = null'),
          isFalse,
        );
        expect(source.contains('_currentQueue!.mixTitle = null'), isFalse);
      },
    );
    late Directory tempDir;
    late Isar isar;
    late QueueRepository queueRepository;
    late TrackRepository trackRepository;
    late SettingsRepository settingsRepository;
    late PlayQueue currentQueue;
    late QueuePersistenceManager manager;

    setUpAll(() async {
      await initializeIsarForTests();
    });

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp(
        'queue_persistence_manager_',
      );
      isar = await Isar.open(
        [TrackSchema, PlayQueueSchema, SettingsSchema],
        directory: tempDir.path,
        name: 'queue_persistence_manager_test',
      );

      queueRepository = QueueRepository(isar);
      trackRepository = TrackRepository(isar);
      settingsRepository = SettingsRepository(isar);
      currentQueue = await queueRepository.getOrCreate();
      manager = QueuePersistenceManager(
        queueRepository: queueRepository,
        trackRepository: trackRepository,
        settingsRepository: settingsRepository,
      );
    });

    tearDown(() async {
      await isar.close(deleteFromDisk: true);
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test(
      'restoreState returns queue snapshot, saved position, volume, and mix metadata',
      () async {
        final savedTracks = await trackRepository.getOrCreateAll([
          _track('restore-a', title: 'Restore A'),
          _track('restore-b', title: 'Restore B'),
        ]);
        final settings = await settingsRepository.get();
        settings.rememberPlaybackPosition = true;
        await settingsRepository.save(settings);

        currentQueue.trackIds = savedTracks.map((track) => track.id).toList();
        currentQueue.currentIndex = 1;
        currentQueue.lastPositionMs = const Duration(
          minutes: 1,
          seconds: 15,
        ).inMilliseconds;
        currentQueue.lastVolume = 0.35;
        currentQueue.isMixMode = true;
        currentQueue.mixPlaylistId = 'RDrestore123';
        currentQueue.mixSeedVideoId = 'seed-restore';
        currentQueue.mixTitle = 'Restored Mix';
        await queueRepository.save(currentQueue);

        final restored = await manager.restoreState();

        expect(restored.queue.trackIds, currentQueue.trackIds);
        expect(restored.tracks.map((track) => track.sourceId), [
          'restore-a',
          'restore-b',
        ]);
        expect(restored.currentIndex, 1);
        expect(restored.savedPosition, const Duration(minutes: 1, seconds: 15));
        expect(restored.savedVolume, 0.35);
        expect(restored.queue.isMixMode, isTrue);
        expect(restored.mixPlaylistId, 'RDrestore123');
        expect(restored.mixSeedVideoId, 'seed-restore');
        expect(restored.mixTitle, 'Restored Mix');
      },
    );

    test('persistQueue saves queue snapshot and playback position', () async {
      final savedTracks = await trackRepository.getOrCreateAll([
        _track('persist-a', title: 'Persist A'),
        _track('persist-b', title: 'Persist B'),
      ]);

      await manager.persistQueue(
        queue: currentQueue,
        tracks: savedTracks,
        currentIndex: 1,
        currentPosition: const Duration(seconds: 42),
      );

      final persistedQueue = await queueRepository.getOrCreate();
      expect(
        persistedQueue.trackIds,
        savedTracks.map((track) => track.id).toList(),
      );
      expect(persistedQueue.currentIndex, 1);
      expect(
        persistedQueue.lastPositionMs,
        const Duration(seconds: 42).inMilliseconds,
      );
    });

    test(
      'savePositionNow persists both currentIndex and lastPositionMs',
      () async {
        await manager.savePositionNow(
          queue: currentQueue,
          currentIndex: 3,
          currentPosition: const Duration(
            minutes: 2,
            seconds: 5,
            milliseconds: 400,
          ),
        );

        final persistedQueue = await queueRepository.getOrCreate();
        expect(persistedQueue.currentIndex, 3);
        expect(
          persistedQueue.lastPositionMs,
          const Duration(
            minutes: 2,
            seconds: 5,
            milliseconds: 400,
          ).inMilliseconds,
        );
      },
    );

    test('saveVolume clamps and persists the value', () async {
      await manager.saveVolume(queue: currentQueue, volume: 1.5);

      var persistedQueue = await queueRepository.getOrCreate();
      expect(persistedQueue.lastVolume, 1.0);

      await manager.saveVolume(queue: currentQueue, volume: -0.25);

      persistedQueue = await queueRepository.getOrCreate();
      expect(persistedQueue.lastVolume, 0.0);
    });

    test('setMixMode updates and clears persisted mix metadata', () async {
      await manager.setMixMode(
        queue: currentQueue,
        enabled: true,
        playlistId: 'RDmix456',
        seedVideoId: 'seed-456',
        title: 'Queue Mix',
      );

      var persistedQueue = await queueRepository.getOrCreate();
      expect(persistedQueue.isMixMode, isTrue);
      expect(persistedQueue.mixPlaylistId, 'RDmix456');
      expect(persistedQueue.mixSeedVideoId, 'seed-456');
      expect(persistedQueue.mixTitle, 'Queue Mix');

      await manager.setMixMode(queue: currentQueue, enabled: false);

      persistedQueue = await queueRepository.getOrCreate();
      expect(persistedQueue.isMixMode, isFalse);
      expect(persistedQueue.mixPlaylistId, isNull);
      expect(persistedQueue.mixSeedVideoId, isNull);
      expect(persistedQueue.mixTitle, isNull);
    });

    test(
      'getPositionRestoreSettings returns repository-backed values',
      () async {
        final settings = await settingsRepository.get();
        settings.rememberPlaybackPosition = false;
        settings.restartRewindSeconds = 7;
        settings.tempPlayRewindSeconds = 13;
        await settingsRepository.save(settings);

        final restoreSettings = await manager.getPositionRestoreSettings();

        expect(restoreSettings.enabled, isFalse);
        expect(restoreSettings.restartRewindSeconds, 7);
        expect(restoreSettings.tempPlayRewindSeconds, 13);
      },
    );
  });
}

Track _track(String sourceId, {required String title}) {
  return Track()
    ..sourceId = sourceId
    ..sourceType = SourceIds.youtube
    ..title = title
    ..artist = 'Tester';
}
