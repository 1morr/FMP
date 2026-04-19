import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/models/play_queue.dart';
import 'package:fmp/data/models/settings.dart';
import 'package:fmp/data/models/track.dart';
import 'package:fmp/data/repositories/queue_repository.dart';
import 'package:fmp/data/repositories/settings_repository.dart';
import 'package:fmp/data/repositories/track_repository.dart';
import 'package:fmp/data/sources/source_provider.dart';
import 'package:fmp/services/audio/queue_manager.dart';
import 'package:fmp/services/audio/queue_persistence_manager.dart';
import 'package:isar/isar.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('QueueManager Task 1 regression', () {
    late Directory tempDir;
    late Isar isar;
    late QueueManager queueManager;

    setUpAll(() async {
      await Isar.initializeIsarCore(
        libraries: {Abi.current(): await _resolveIsarLibraryPath()},
      );
    });

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('queue_manager_task1_');
      isar = await Isar.open(
        [TrackSchema, PlayQueueSchema, SettingsSchema],
        directory: tempDir.path,
        name: 'queue_manager_test',
      );

      queueManager = QueueManager(
        queueRepository: QueueRepository(isar),
        trackRepository: TrackRepository(isar),
        settingsRepository: SettingsRepository(isar),
        sourceManager: SourceManager(),
        queuePersistenceManager: QueuePersistenceManager(
          queueRepository: QueueRepository(isar),
          trackRepository: TrackRepository(isar),
          settingsRepository: SettingsRepository(isar),
        ),
      );

      await queueManager.initialize();
    });

    tearDown(() async {
      queueManager.dispose();
      await isar.close(deleteFromDisk: true);
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('dispose cancels the periodic saver after persistence promotion', () async {
      await queueManager.playSingle(_queueTrack('timer-track'));
      queueManager.updatePosition(const Duration(seconds: 12));

      queueManager.dispose();
      await Future<void>.delayed(const Duration(seconds: 11));

      final persistedQueue = await QueueRepository(isar).getOrCreate();
      expect(persistedQueue.trackIds, [_trackId(queueManager.currentTrack)]);
      expect(persistedQueue.lastPositionMs, 0);
    });
  });

  group('PlayQueue model', () {
    group('properties', () {
      test('length returns correct value', () {
        final queue = PlayQueue()..trackIds = [1, 2, 3, 4, 5];

        expect(queue.length, equals(5));
      });

      test('isEmpty returns true for empty queue', () {
        final queue = PlayQueue();

        expect(queue.isEmpty, isTrue);
        expect(queue.isNotEmpty, isFalse);
      });

      test('isNotEmpty returns true for non-empty queue', () {
        final queue = PlayQueue()..trackIds = [1, 2, 3];

        expect(queue.isNotEmpty, isTrue);
        expect(queue.isEmpty, isFalse);
      });
    });

    group('navigation', () {
      test('hasNext returns true when not at end', () {
        final queue = PlayQueue()
          ..trackIds = [1, 2, 3]
          ..currentIndex = 0;

        expect(queue.hasNext, isTrue);
      });

      test('hasNext returns false when at last track', () {
        final queue = PlayQueue()
          ..trackIds = [1, 2, 3]
          ..currentIndex = 2;

        expect(queue.hasNext, isFalse);
      });

      test('hasPrevious returns false when at first track', () {
        final queue = PlayQueue()
          ..trackIds = [1, 2, 3]
          ..currentIndex = 0;

        expect(queue.hasPrevious, isFalse);
      });

      test('hasPrevious returns true when not at beginning', () {
        final queue = PlayQueue()
          ..trackIds = [1, 2, 3]
          ..currentIndex = 1;

        expect(queue.hasPrevious, isTrue);
      });
    });

    group('currentTrackId', () {
      test('returns null for empty queue', () {
        final queue = PlayQueue();

        expect(queue.currentTrackId, isNull);
      });

      test('returns correct track id', () {
        final queue = PlayQueue()
          ..trackIds = [10, 20, 30]
          ..currentIndex = 1;

        expect(queue.currentTrackId, equals(20));
      });

      test('returns null when index out of bounds', () {
        final queue = PlayQueue()
          ..trackIds = [1, 2, 3]
          ..currentIndex = 10;

        expect(queue.currentTrackId, isNull);
      });
    });

    group('LoopMode', () {
      test('default loop mode is none', () {
        final queue = PlayQueue();

        expect(queue.loopMode, equals(LoopMode.none));
      });

      test('can set loop mode to all', () {
        final queue = PlayQueue()..loopMode = LoopMode.all;

        expect(queue.loopMode, equals(LoopMode.all));
      });

      test('can set loop mode to one', () {
        final queue = PlayQueue()..loopMode = LoopMode.one;

        expect(queue.loopMode, equals(LoopMode.one));
      });
    });

    group('shuffle', () {
      test('default shuffle is disabled', () {
        final queue = PlayQueue();

        expect(queue.isShuffleEnabled, isFalse);
      });

      test('can enable shuffle', () {
        final queue = PlayQueue()..isShuffleEnabled = true;

        expect(queue.isShuffleEnabled, isTrue);
      });

      test('originalOrder is null by default', () {
        final queue = PlayQueue();

        expect(queue.originalOrder, isNull);
      });

      test('can store original order', () {
        final queue = PlayQueue()..originalOrder = [3, 1, 2];

        expect(queue.originalOrder, equals([3, 1, 2]));
      });
    });

    group('volume', () {
      test('default volume is 1.0', () {
        final queue = PlayQueue();

        expect(queue.lastVolume, equals(1.0));
      });

      test('can set volume', () {
        final queue = PlayQueue()..lastVolume = 0.5;

        expect(queue.lastVolume, equals(0.5));
      });
    });

    group('position', () {
      test('default position is 0', () {
        final queue = PlayQueue();

        expect(queue.lastPositionMs, equals(0));
      });

      test('can set position', () {
        final queue = PlayQueue()..lastPositionMs = 30000; // 30 seconds

        expect(queue.lastPositionMs, equals(30000));
      });
    });
  });

  group('Track model uniqueness', () {
    test('uniqueKey includes cid when present', () {
      final track = Track()
        ..sourceId = 'BV123456'
        ..sourceType = SourceType.bilibili
        ..title = 'Test Track'
        ..cid = 12345;

      expect(track.uniqueKey, contains('12345'));
      expect(track.uniqueKey, contains('BV123456'));
    });

    test('uniqueKey without cid uses sourceId only', () {
      final track = Track()
        ..sourceId = 'BV123456'
        ..sourceType = SourceType.bilibili
        ..title = 'Test Track';

      expect(track.uniqueKey, equals('bilibili:BV123456'));
    });

    test('tracks with same source and cid have same uniqueKey', () {
      final track1 = Track()
        ..id = 1
        ..sourceId = 'BV123456'
        ..sourceType = SourceType.bilibili
        ..cid = 111;

      final track2 = Track()
        ..id = 2
        ..sourceId = 'BV123456'
        ..sourceType = SourceType.bilibili
        ..cid = 111;

      expect(track1.uniqueKey, equals(track2.uniqueKey));
    });

    test('tracks with different cid have different uniqueKey', () {
      final track1 = Track()
        ..sourceId = 'BV123456'
        ..sourceType = SourceType.bilibili
        ..cid = 111;

      final track2 = Track()
        ..sourceId = 'BV123456'
        ..sourceType = SourceType.bilibili
        ..cid = 222;

      expect(track1.uniqueKey, isNot(equals(track2.uniqueKey)));
    });
  });

  group('Track audio URL validation', () {
    test('hasValidAudioUrl returns false when url is null', () {
      final track = Track()
        ..sourceId = 'test123'
        ..sourceType = SourceType.bilibili
        ..title = 'Test';

      expect(track.hasValidAudioUrl, isFalse);
    });

    test('hasValidAudioUrl returns true when url exists without expiry', () {
      final track = Track()
        ..sourceId = 'test123'
        ..sourceType = SourceType.bilibili
        ..title = 'Test'
        ..audioUrl = 'https://example.com/audio.m4a';

      expect(track.hasValidAudioUrl, isTrue);
    });

    test('hasValidAudioUrl returns true when not expired', () {
      final track = Track()
        ..sourceId = 'test123'
        ..sourceType = SourceType.bilibili
        ..title = 'Test'
        ..audioUrl = 'https://example.com/audio.m4a'
        ..audioUrlExpiry = DateTime.now().add(const Duration(hours: 1));

      expect(track.hasValidAudioUrl, isTrue);
    });

    test('hasValidAudioUrl returns false when expired', () {
      final track = Track()
        ..sourceId = 'test123'
        ..sourceType = SourceType.bilibili
        ..title = 'Test'
        ..audioUrl = 'https://example.com/audio.m4a'
        ..audioUrlExpiry = DateTime.now().subtract(const Duration(hours: 1));

      expect(track.hasValidAudioUrl, isFalse);
    });
  });

  group('Track multi-page operations', () {
    test('isPartOfMultiPage returns false for single page', () {
      final track = Track()
        ..sourceId = 'test123'
        ..sourceType = SourceType.bilibili
        ..title = 'Single Video';

      expect(track.isPartOfMultiPage, isFalse);
    });

    test('isPartOfMultiPage returns true for multi-page', () {
      final track = Track()
        ..sourceId = 'test123'
        ..sourceType = SourceType.bilibili
        ..title = 'P01 - Intro'
        ..pageNum = 1
        ..pageCount = 3;

      expect(track.isPartOfMultiPage, isTrue);
    });

    test('groupKey is same for pages of same video', () {
      final page1 = Track()
        ..sourceId = 'BV123456'
        ..sourceType = SourceType.bilibili
        ..title = 'P01'
        ..pageNum = 1
        ..cid = 111;

      final page2 = Track()
        ..sourceId = 'BV123456'
        ..sourceType = SourceType.bilibili
        ..title = 'P02'
        ..pageNum = 2
        ..cid = 222;

      expect(page1.groupKey, equals(page2.groupKey));
    });

    test('uniqueKey is different for pages of same video', () {
      final page1 = Track()
        ..sourceId = 'BV123456'
        ..sourceType = SourceType.bilibili
        ..title = 'P01'
        ..cid = 111;

      final page2 = Track()
        ..sourceId = 'BV123456'
        ..sourceType = SourceType.bilibili
        ..title = 'P02'
        ..cid = 222;

      expect(page1.uniqueKey, isNot(equals(page2.uniqueKey)));
    });
  });
}

Track _queueTrack(String sourceId) {
  return Track()
    ..sourceId = sourceId
    ..sourceType = SourceType.youtube
    ..title = sourceId
    ..artist = 'Tester';
}

int _trackId(Track? track) {
  if (track == null) {
    throw StateError('Expected queue manager to have a current track');
  }
  return track.id;
}

Future<String> _resolveIsarLibraryPath() async {
  final packageConfig = await _loadPackageConfig();
  final packageDir = _resolvePackageDirectory(packageConfig, 'isar_flutter_libs');

  if (Platform.isWindows) {
    return '${packageDir.path}/windows/isar.dll';
  }
  if (Platform.isLinux) {
    return '${packageDir.path}/linux/libisar.so';
  }
  if (Platform.isMacOS) {
    return '${packageDir.path}/macos/libisar.dylib';
  }

  throw UnsupportedError('Unsupported platform for Isar tests: ${Platform.operatingSystem}');
}

Future<Map<String, dynamic>> _loadPackageConfig() async {
  final packageConfigFile =
      File('${Directory.current.path}/.dart_tool/package_config.json');
  if (!await packageConfigFile.exists()) {
    throw StateError(
      'Could not find .dart_tool/package_config.json for test package resolution',
    );
  }

  return jsonDecode(await packageConfigFile.readAsString())
      as Map<String, dynamic>;
}

Directory _resolvePackageDirectory(
  Map<String, dynamic> packageConfig,
  String packageName,
) {
  final packages = packageConfig['packages'];
  if (packages is! List) {
    throw StateError('Invalid package_config.json format');
  }

  final packageConfigDir = Directory('${Directory.current.path}/.dart_tool');
  for (final package in packages) {
    if (package is! Map<String, dynamic>) continue;
    if (package['name'] != packageName) continue;

    final rootUri = package['rootUri'];
    if (rootUri is! String) break;

    return Directory(packageConfigDir.uri.resolve(rootUri).toFilePath());
  }

  throw StateError('Package not found in package_config.json: $packageName');
}
