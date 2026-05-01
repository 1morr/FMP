import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/models/lyrics_match.dart';
import 'package:fmp/data/models/play_history.dart';
import 'package:fmp/data/models/playlist.dart';
import 'package:fmp/data/models/radio_station.dart';
import 'package:fmp/data/models/search_history.dart';
import 'package:fmp/data/models/settings.dart';
import 'package:fmp/data/models/track.dart';
import 'package:fmp/providers/database_provider.dart';
import 'package:fmp/services/backup/backup_data.dart';
import 'package:fmp/services/backup/backup_service.dart';
import 'package:isar/isar.dart';
import 'package:package_info_plus/package_info_plus.dart';

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
        [
          SettingsSchema,
          PlaylistSchema,
          TrackSchema,
          PlayHistorySchema,
          SearchHistorySchema,
          RadioStationSchema,
          LyricsMatchSchema,
        ],
        directory: tempDir.path,
        name: 'backup_service_test',
      );
      backupService = BackupService(isar);
      PackageInfo.setMockInitialValues(
        appName: 'FMP',
        packageName: 'com.example.fmp',
        version: 'test-version',
        buildNumber: '1',
        buildSignature: '',
      );
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
      expect(settingsBackup.lyricsAiTitleParsingModeIndex, 0);
      expect(settingsBackup.allowPlainLyricsAutoMatch, isFalse);
      expect(settingsBackup.lyricsAiEndpoint, isEmpty);
      expect(settingsBackup.lyricsAiModel, isEmpty);
      expect(settingsBackup.lyricsAiTimeoutSeconds, 10);
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
          lyricsAiTitleParsingModeIndex: 3,
          allowPlainLyricsAutoMatch: true,
          lyricsAiEndpoint: 'https://example.test/v1',
          lyricsAiModel: 'test-model',
          lyricsAiTimeoutSeconds: 12,
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
      expect(restoredSettings.lyricsAiTitleParsingModeIndex, 3);
      expect(restoredSettings.lyricsAiTitleParsingMode,
          LyricsAiTitleParsingMode.advancedAiSelect);
      expect(restoredSettings.allowPlainLyricsAutoMatch, isTrue);
      expect(restoredSettings.lyricsAiEndpoint, 'https://example.test/v1');
      expect(restoredSettings.lyricsAiModel, 'test-model');
      expect(restoredSettings.lyricsAiTimeoutSeconds, 12);
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

    test('exportData includes lyrics AI settings without secure API key',
        () async {
      final outputPath = '${tempDir.path}/export.json';
      FilePicker.platform = _FakeFilePicker(saveFilePath: outputPath);
      final settings = Settings()
        ..lyricsAiTitleParsingMode = LyricsAiTitleParsingMode.advancedAiSelect
        ..allowPlainLyricsAutoMatch = true
        ..lyricsAiEndpoint = 'https://example.test/v1'
        ..lyricsAiModel = 'test-model'
        ..lyricsAiTimeoutSeconds = 15;
      await isar.writeTxn(() async {
        await isar.settings.put(settings);
      });

      final exportedPath = await backupService.exportData();

      expect(exportedPath, outputPath);
      final json = jsonDecode(await File(outputPath).readAsString())
          as Map<String, dynamic>;
      final settingsJson = json['settings'] as Map<String, dynamic>;
      expect(settingsJson['lyricsAiTitleParsingModeIndex'], 3);
      expect(settingsJson['allowPlainLyricsAutoMatch'], isTrue);
      expect(settingsJson['lyricsAiEndpoint'], 'https://example.test/v1');
      expect(settingsJson['lyricsAiModel'], 'test-model');
      expect(settingsJson['lyricsAiTimeoutSeconds'], 15);
      expect(settingsJson.containsKey('lyricsAiApiKey'), isFalse);
      expect(jsonEncode(json).contains('secret'), isFalse);
    });
  });
}

class _FakeFilePicker extends FilePicker {
  _FakeFilePicker({required this.saveFilePath});

  final String saveFilePath;

  @override
  Future<String?> saveFile({
    String? dialogTitle,
    String? fileName,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Uint8List? bytes,
    bool lockParentWindow = false,
  }) async {
    return saveFilePath;
  }
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
