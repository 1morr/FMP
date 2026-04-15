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

    test('migrates NetEase defaults when old settings omit netease source', () async {
      tempDir = await Directory.systemTemp.createTemp('database_migration_test_');
      isar = await Isar.open(
        [SettingsSchema, PlayQueueSchema],
        directory: tempDir.path,
        name: 'database_migration_test',
      );

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

    test('preserves intentional NetEase opt-out on repeated migration runs', () async {
      tempDir = await Directory.systemTemp.createTemp('database_migration_test_');
      isar = await Isar.open(
        [SettingsSchema, PlayQueueSchema],
        directory: tempDir.path,
        name: 'database_migration_test',
      );

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

    test('creates an empty queue when none exists', () async {
      tempDir = await Directory.systemTemp.createTemp('database_migration_test_');
      isar = await Isar.open(
        [SettingsSchema, PlayQueueSchema],
        directory: tempDir.path,
        name: 'database_migration_test',
      );

      await runDatabaseMigrationForTesting(isar);

      final queues = await isar.playQueues.where().findAll();
      expect(queues, hasLength(1));
      expect(queues.single.trackIds, isEmpty);
      expect(queues.single.currentIndex, 0);
    });
  });
}

Future<String> _resolveIsarLibraryPath() async {
  final packageConfigFile = File('${Directory.current.path}/.dart_tool/package_config.json');
  final packageConfig = jsonDecode(await packageConfigFile.readAsString()) as Map<String, dynamic>;
  final packages = packageConfig['packages'] as List<dynamic>;
  final packageConfigDir = Directory('${Directory.current.path}/.dart_tool');

  for (final package in packages) {
    if (package is! Map<String, dynamic> || package['name'] != 'isar_flutter_libs') {
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
