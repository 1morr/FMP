import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/models/settings.dart';
import 'package:fmp/data/repositories/settings_repository.dart';
import 'package:fmp/services/download/download_path_manager.dart';
import 'package:isar/isar.dart';
import '../../support/isar_test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DownloadPathManager settings updates', () {
    late Directory tempDir;
    late Isar isar;
    late SettingsRepository settingsRepository;
    late DownloadPathManager manager;

    setUpAll(() async {
      await initializeIsarForTests();
    });

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('download_path_manager_');
      isar = await Isar.open(
        [SettingsSchema],
        directory: tempDir.path,
        name: 'download_path_manager_test',
      );
      settingsRepository = SettingsRepository(isar);
      manager = DownloadPathManager(settingsRepository);
    });

    tearDown(() async {
      await isar.close(deleteFromDisk: true);
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('saveDownloadPath preserves unrelated settings', () async {
      final settings = await settingsRepository.get();
      settings.audioQualityLevelIndex = 2;
      settings.useNeteaseAuthForPlay = false;
      await settingsRepository.save(settings);

      await manager.saveDownloadPath('/tmp/fmp-downloads');

      final updated = await settingsRepository.get();
      expect(updated.customDownloadDir, '/tmp/fmp-downloads');
      expect(updated.audioQualityLevelIndex, 2);
      expect(updated.useNeteaseAuthForPlay, isFalse);
    });

    test('clearDownloadPath preserves unrelated settings', () async {
      final settings = await settingsRepository.get();
      settings.customDownloadDir = '/tmp/fmp-downloads';
      settings.audioQualityLevelIndex = 1;
      settings.useNeteaseAuthForPlay = false;
      await settingsRepository.save(settings);

      await manager.clearDownloadPath();

      final updated = await settingsRepository.get();
      expect(updated.customDownloadDir, isNull);
      expect(updated.audioQualityLevelIndex, 1);
      expect(updated.useNeteaseAuthForPlay, isFalse);
    });
  });
}
