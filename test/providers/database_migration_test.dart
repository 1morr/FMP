import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/models/play_queue.dart';
import 'package:fmp/data/models/settings.dart';
import 'package:fmp/providers/database_provider.dart';
import 'package:isar/isar.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('database migration', () {
    late Directory tempDir;
    late Isar isar;

    setUpAll(() async {
      await Isar.initializeIsarCore(
        libraries: {Abi.current(): await _resolveIsarLibraryPath()},
      );
    });

    tearDown(() async {
      await isar.close(deleteFromDisk: true);
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    Future<void> openTestDatabase() async {
      tempDir =
          await Directory.systemTemp.createTemp('database_migration_test_');
      isar = await Isar.open(
        [SettingsSchema, PlayQueueSchema],
        directory: tempDir.path,
        name: 'database_migration_test',
      );
    }

    test('initializes bootstrap defaults for settings and queue', () async {
      await openTestDatabase();

      await initializeDatabaseDefaults(isar);

      final settings = await isar.settings.get(0);
      final queues = await isar.playQueues.where().findAll();
      expect(settings, isNotNull);
      expect(settings!.rememberPlaybackPosition, isTrue);
      expect(settings.tempPlayRewindSeconds, 10);
      expect(settings.disabledLyricsSources, 'lrclib');
      expect(settings.maxCacheSizeMB, createBootstrapSettings().maxCacheSizeMB);
      expect(queues, hasLength(1));
      expect(queues.single.lastVolume, 1.0);
      expect(queues.single.trackIds, isEmpty);
      expect(queues.single.currentIndex, 0);
    });

    test('repairs AI title parsing fields from Isar upgrade defaults',
        () async {
      await openTestDatabase();

      final upgradedSettings = Settings()
        ..lyricsAiTitleParsingModeIndex = 0
        ..lyricsAiEndpoint = ''
        ..lyricsAiModel = ''
        ..lyricsAiTimeoutSeconds = 0;
      await isar.writeTxn(() async {
        await isar.settings.put(upgradedSettings);
      });

      await runDatabaseMigrationForTesting(isar);

      final migratedSettings = await isar.settings.get(0);
      expect(migratedSettings, isNotNull);
      expect(migratedSettings!.lyricsAiTitleParsingModeIndex, 1);
      expect(migratedSettings.lyricsAiTitleParsingMode,
          LyricsAiTitleParsingMode.fallbackAfterRules);
      expect(migratedSettings.lyricsAiTimeoutSeconds, 10);
      expect(migratedSettings.lyricsAiEndpoint, isEmpty);
      expect(migratedSettings.lyricsAiModel, isEmpty);
    });

    test('repairs invalid AI title parsing mode index', () async {
      await openTestDatabase();

      final settings = Settings()
        ..lyricsAiTitleParsingModeIndex = 99
        ..lyricsAiTimeoutSeconds = 10;
      await isar.writeTxn(() async {
        await isar.settings.put(settings);
      });

      await runDatabaseMigrationForTesting(isar);

      final migratedSettings = await isar.settings.get(0);
      expect(migratedSettings, isNotNull);
      expect(migratedSettings!.lyricsAiTitleParsingModeIndex, 1);
      expect(migratedSettings.lyricsAiTitleParsingMode,
          LyricsAiTitleParsingMode.fallbackAfterRules);
      expect(migratedSettings.lyricsAiTimeoutSeconds, 10);
    });

    test(
        'repairs legacy playback and lyrics defaults only for legacy signature',
        () async {
      await openTestDatabase();

      final legacySettings = Settings()
        ..enabledSources = ['bilibili', 'youtube']
        ..useNeteaseAuthForPlay = false
        ..neteaseStreamPriority = ''
        ..rememberPlaybackPosition = false
        ..tempPlayRewindSeconds = 0
        ..disabledLyricsSources = '';
      await isar.writeTxn(() async {
        await isar.settings.put(legacySettings);
      });

      await runDatabaseMigrationForTesting(isar);

      final migratedSettings = await isar.settings.get(0);
      expect(migratedSettings, isNotNull);
      expect(migratedSettings!.rememberPlaybackPosition, isTrue);
      expect(migratedSettings.tempPlayRewindSeconds, 10);
      expect(migratedSettings.disabledLyricsSources, 'lrclib');
    });

    test('preserves intentional modern playback and lyrics settings', () async {
      await openTestDatabase();

      final modernSettings = Settings()
        ..rememberPlaybackPosition = false
        ..tempPlayRewindSeconds = 7
        ..disabledLyricsSources = 'qqmusic';
      await isar.writeTxn(() async {
        await isar.settings.put(modernSettings);
      });

      await runDatabaseMigrationForTesting(isar);
      await runDatabaseMigrationForTesting(isar);

      final migratedSettings = await isar.settings.get(0);
      expect(migratedSettings, isNotNull);
      expect(migratedSettings!.rememberPlaybackPosition, isFalse);
      expect(migratedSettings.tempPlayRewindSeconds, 7);
      expect(migratedSettings.disabledLyricsSources, 'qqmusic');
    });

    test('preserves intentional legacy-shaped playback and lyrics values', () async {
      await openTestDatabase();

      final intentionallyConfiguredSettings = Settings()
        ..enabledSources = ['bilibili', 'youtube']
        ..useNeteaseAuthForPlay = false
        ..neteaseStreamPriority = 'audioOnly'
        ..rememberPlaybackPosition = false
        ..tempPlayRewindSeconds = 0
        ..disabledLyricsSources = '';
      await isar.writeTxn(() async {
        await isar.settings.put(intentionallyConfiguredSettings);
      });

      await runDatabaseMigrationForTesting(isar);
      await runDatabaseMigrationForTesting(isar);

      final migratedSettings = await isar.settings.get(0);
      expect(migratedSettings, isNotNull);
      expect(migratedSettings!.rememberPlaybackPosition, isFalse);
      expect(migratedSettings.tempPlayRewindSeconds, 0);
      expect(migratedSettings.disabledLyricsSources, '');
      expect(migratedSettings.useNeteaseAuthForPlay, isFalse);
      expect(migratedSettings.neteaseStreamPriority, 'audioOnly');
      expect(migratedSettings.enabledSources, ['bilibili', 'youtube']);
    });

    test('migrates NetEase defaults when old settings omit netease source',
        () async {
      await openTestDatabase();

      final legacySettings = Settings()
        ..enabledSources = ['bilibili', 'youtube']
        ..useNeteaseAuthForPlay = false
        ..neteaseStreamPriority = '';
      await isar.writeTxn(() async {
        await isar.settings.put(legacySettings);
      });

      await runDatabaseMigrationForTesting(isar);

      final migratedSettings = await isar.settings.get(0);
      expect(migratedSettings, isNotNull);
      expect(migratedSettings!.useNeteaseAuthForPlay, isTrue);
      expect(migratedSettings.enabledSources, contains('netease'));
      expect(migratedSettings.neteaseStreamPriority, 'audioOnly');
    });

    test('preserves intentional NetEase opt-out on repeated migration runs',
        () async {
      await openTestDatabase();

      final modernSettings = Settings()
        ..enabledSources = ['bilibili', 'youtube']
        ..useNeteaseAuthForPlay = false
        ..neteaseStreamPriority = 'audioOnly';
      await isar.writeTxn(() async {
        await isar.settings.put(modernSettings);
      });

      await runDatabaseMigrationForTesting(isar);
      await runDatabaseMigrationForTesting(isar);

      final migratedSettings = await isar.settings.get(0);
      expect(migratedSettings, isNotNull);
      expect(migratedSettings!.useNeteaseAuthForPlay, isFalse);
      expect(migratedSettings.enabledSources, isNot(contains('netease')));
      expect(migratedSettings.neteaseStreamPriority, 'audioOnly');
    });

    test('repairs legacy queue volume without changing current queue state',
        () async {
      await openTestDatabase();

      final legacyQueue = PlayQueue()..lastVolume = 0;
      await isar.writeTxn(() async {
        await isar.playQueues.put(legacyQueue);
      });

      await runDatabaseMigrationForTesting(isar);

      final repairedQueue = await isar.playQueues.where().findFirst();
      expect(repairedQueue, isNotNull);
      expect(repairedQueue!.lastVolume, 1.0);

      await isar.writeTxn(() async {
        repairedQueue.lastVolume = 0;
        repairedQueue.trackIds = [1, 2, 3];
        repairedQueue.currentIndex = 1;
        await isar.playQueues.put(repairedQueue);
      });

      await runDatabaseMigrationForTesting(isar);

      final preservedQueue = await isar.playQueues.where().findFirst();
      expect(preservedQueue, isNotNull);
      expect(preservedQueue!.lastVolume, 0);
      expect(preservedQueue.trackIds, [1, 2, 3]);
      expect(preservedQueue.currentIndex, 1);
    });

    test('creates an empty queue when none exists', () async {
      await openTestDatabase();

      await runDatabaseMigrationForTesting(isar);

      final queues = await isar.playQueues.where().findAll();
      expect(queues, hasLength(1));
      expect(queues.single.trackIds, isEmpty);
      expect(queues.single.currentIndex, 0);
      expect(queues.single.lastVolume, 1.0);
    });
  });
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
