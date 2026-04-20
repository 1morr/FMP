import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/models/settings.dart';
import 'package:fmp/providers/database_provider.dart';
import 'package:fmp/services/backup/backup_data.dart';
import 'package:fmp/services/backup/backup_service.dart';
import 'package:isar/isar.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('backup settings behavior', () {
    late Directory tempDir;
    late Isar isar;
    late BackupService backupService;

    setUpAll(() async {
      await Isar.initializeIsarCore(
        libraries: {Abi.current(): await _resolveIsarLibraryPath()},
      );
    });

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('backup_service_test_');
      isar = await Isar.open(
        [SettingsSchema],
        directory: tempDir.path,
        name: 'backup_service_test',
      );
      backupService = BackupService(isar);
    });

    tearDown(() async {
      await isar.close(deleteFromDisk: true);
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('SettingsBackup.fromJson uses current fallback defaults', () {
      final settingsBackup = SettingsBackup.fromJson({});
      final bootstrapSettings = createBootstrapSettings();

      expect(settingsBackup.maxCacheSizeMB, bootstrapSettings.maxCacheSizeMB);
      expect(settingsBackup.rememberPlaybackPosition, isTrue);
      expect(settingsBackup.tempPlayRewindSeconds, 10);
      expect(settingsBackup.autoMatchLyrics, isFalse);
      expect(settingsBackup.disabledLyricsSources, 'lrclib');
      expect(settingsBackup.neteaseStreamPriority, 'audioOnly');
      expect(settingsBackup.useBilibiliAuthForPlay, isFalse);
      expect(settingsBackup.useYoutubeAuthForPlay, isFalse);
      expect(settingsBackup.useNeteaseAuthForPlay, isTrue);
      expect(settingsBackup.rankingRefreshIntervalMinutes, 60);
      expect(settingsBackup.radioRefreshIntervalMinutes, 5);
      expect(settingsBackup.minimizeToTrayOnClose,
          Settings().minimizeToTrayOnClose);
      expect(
          settingsBackup.enableGlobalHotkeys, Settings().enableGlobalHotkeys);
    });

    test(
        'importData restores new settings fields and preserves device-specific ones',
        () async {
      final currentSettings = Settings()
        ..customDownloadDir = '/device/downloads'
        ..preferredAudioDeviceId = 'device-1'
        ..preferredAudioDeviceName = 'USB DAC'
        ..minimizeToTrayOnClose = false
        ..enableGlobalHotkeys = false
        ..launchAtStartup = false
        ..launchMinimized = false
        ..hotkeyConfig = jsonEncode({'playPause': 'Ctrl+Alt+P'});
      await isar.writeTxn(() async {
        await isar.settings.put(currentSettings);
      });

      final backupData = BackupData(
        version: kBackupVersion,
        exportedAt: DateTime(2026, 4, 20),
        appVersion: 'test',
        playlists: const [],
        tracks: const [],
        playHistory: const [],
        searchHistory: const [],
        radioStations: const [],
        settings: SettingsBackup(
          themeModeIndex: 2,
          maxCacheSizeMB: 48,
          enabledSources: const ['bilibili', 'youtube', 'netease'],
          rememberPlaybackPosition: false,
          tempPlayRewindSeconds: 7,
          neteaseStreamPriority: 'audioOnly',
          autoMatchLyrics: true,
          disabledLyricsSources: 'qqmusic',
          useBilibiliAuthForPlay: true,
          useYoutubeAuthForPlay: true,
          useNeteaseAuthForPlay: false,
          rankingRefreshIntervalMinutes: 15,
          radioRefreshIntervalMinutes: 9,
          minimizeToTrayOnClose: true,
          enableGlobalHotkeys: true,
          launchAtStartup: true,
          launchMinimized: true,
          hotkeyConfig: jsonEncode({'next': 'Ctrl+Alt+Right'}),
        ),
      );

      final result = await backupService.importData(
        backupData,
        importPlaylists: false,
        importPlayHistory: false,
        importSearchHistory: false,
        importRadioStations: false,
        importLyricsMatches: false,
        importSettings: true,
      );

      final restoredSettings = await isar.settings.get(0);
      expect(result.settingsImported, isTrue);
      expect(result.errors, isEmpty);
      expect(restoredSettings, isNotNull);
      expect(restoredSettings!.themeModeIndex, 2);
      expect(restoredSettings.maxCacheSizeMB, 48);
      expect(
          restoredSettings.enabledSources, ['bilibili', 'youtube', 'netease']);
      expect(restoredSettings.rememberPlaybackPosition, isFalse);
      expect(restoredSettings.tempPlayRewindSeconds, 7);
      expect(restoredSettings.neteaseStreamPriority, 'audioOnly');
      expect(restoredSettings.autoMatchLyrics, isTrue);
      expect(restoredSettings.disabledLyricsSources, 'qqmusic');
      expect(restoredSettings.useBilibiliAuthForPlay, isTrue);
      expect(restoredSettings.useYoutubeAuthForPlay, isTrue);
      expect(restoredSettings.useNeteaseAuthForPlay, isFalse);
      expect(restoredSettings.rankingRefreshIntervalMinutes, 15);
      expect(restoredSettings.radioRefreshIntervalMinutes, 9);
      expect(restoredSettings.customDownloadDir, '/device/downloads');
      expect(restoredSettings.preferredAudioDeviceId, 'device-1');
      expect(restoredSettings.preferredAudioDeviceName, 'USB DAC');

      if (Platform.isWindows) {
        expect(restoredSettings.minimizeToTrayOnClose, isTrue);
        expect(restoredSettings.enableGlobalHotkeys, isTrue);
        expect(restoredSettings.launchAtStartup, isTrue);
        expect(restoredSettings.launchMinimized, isTrue);
        expect(restoredSettings.hotkeyConfig,
            jsonEncode({'next': 'Ctrl+Alt+Right'}));
      } else {
        expect(restoredSettings.minimizeToTrayOnClose, isFalse);
        expect(restoredSettings.enableGlobalHotkeys, isFalse);
        expect(restoredSettings.launchAtStartup, isFalse);
        expect(restoredSettings.launchMinimized, isFalse);
        expect(restoredSettings.hotkeyConfig,
            jsonEncode({'playPause': 'Ctrl+Alt+P'}));
      }
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
