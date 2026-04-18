import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/models/play_queue.dart';
import 'package:fmp/data/models/settings.dart';
import 'package:fmp/data/repositories/queue_repository.dart';
import 'package:fmp/data/repositories/settings_repository.dart';
import 'package:fmp/services/audio/internal/queue_persistence_helpers.dart';
import 'package:isar/isar.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('QueuePersistenceHelpers Task 5 regression', () {
    late Directory tempDir;
    late Isar isar;
    late QueueRepository queueRepository;
    late SettingsRepository settingsRepository;
    late PlayQueue currentQueue;
    late int currentIndex;
    late Duration currentPosition;
    late QueuePersistenceHelpers helpers;

    setUpAll(() async {
      await Isar.initializeIsarCore(
        libraries: {Abi.current(): await _resolveIsarLibraryPath()},
      );
    });

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp(
        'queue_persistence_helpers_',
      );
      isar = await Isar.open(
        [PlayQueueSchema, SettingsSchema],
        directory: tempDir.path,
        name: 'queue_persistence_helpers_test',
      );

      queueRepository = QueueRepository(isar);
      settingsRepository = SettingsRepository(isar);
      currentQueue = await queueRepository.getOrCreate();
      currentIndex = 0;
      currentPosition = Duration.zero;
      helpers = QueuePersistenceHelpers(
        queueRepository: queueRepository,
        settingsRepository: settingsRepository,
        getCurrentQueue: () => currentQueue,
        getCurrentIndex: () => currentIndex,
        getCurrentPosition: () => currentPosition,
      );
    });

    tearDown(() async {
      await isar.close(deleteFromDisk: true);
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('savePositionNow persists both currentIndex and lastPositionMs', () async {
      currentIndex = 3;
      currentPosition = const Duration(minutes: 2, seconds: 5, milliseconds: 400);

      await helpers.savePositionNow();

      final persistedQueue = await queueRepository.getOrCreate();
      expect(persistedQueue.currentIndex, 3);
      expect(persistedQueue.lastPositionMs, currentPosition.inMilliseconds);
    });

    test('saveVolume clamps and persists the value', () async {
      await helpers.saveVolume(1.5);

      var persistedQueue = await queueRepository.getOrCreate();
      expect(persistedQueue.lastVolume, 1.0);

      await helpers.saveVolume(-0.25);

      persistedQueue = await queueRepository.getOrCreate();
      expect(persistedQueue.lastVolume, 0.0);
    });

    test('getPositionRestoreSettings returns repository-backed values', () async {
      final settings = await settingsRepository.get();
      settings.rememberPlaybackPosition = false;
      settings.restartRewindSeconds = 7;
      settings.tempPlayRewindSeconds = 13;
      await settingsRepository.save(settings);

      final restoreSettings = await helpers.getPositionRestoreSettings();

      expect(restoreSettings.enabled, isFalse);
      expect(restoreSettings.restartRewindSeconds, 7);
      expect(restoreSettings.tempPlayRewindSeconds, 13);
    });
  });
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
