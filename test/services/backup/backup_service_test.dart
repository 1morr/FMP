import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/models/hotkey_config.dart';
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
import 'package:hotkey_manager/hotkey_manager.dart';
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
      expect(settingsBackup.lyricsAiTimeoutSeconds, 20);
      expect(settingsBackup.lyricsWindowTextColor, isNull);
      expect(settingsBackup.lyricsWindowSecondaryTextColor, isNull);
      expect(settingsBackup.lyricsWindowInactiveTextOpacity, isNull);
      expect(settingsBackup.lyricsWindowOutlineEnabled, isNull);
      expect(settingsBackup.lyricsWindowOutlineColor, isNull);
      expect(settingsBackup.lyricsWindowOutlineWidth, isNull);
      expect(settingsBackup.lyricsWindowShadowEnabled, isNull);
      expect(settingsBackup.lyricsWindowShadowColor, isNull);
      expect(settingsBackup.lyricsWindowShadowBlurRadius, isNull);
      expect(settingsBackup.lyricsWindowShadowOffsetX, isNull);
      expect(settingsBackup.lyricsWindowShadowOffsetY, isNull);
      expect(settingsBackup.disabledLyricsSources, 'lrclib');
      expect(settingsBackup.neteaseStreamPriority, 'audioOnly');
      expect(settingsBackup.useBilibiliAuthForPlay, isFalse);
      expect(settingsBackup.useYoutubeAuthForPlay, isFalse);
      expect(settingsBackup.useNeteaseAuthForPlay, isTrue);
      expect(settingsBackup.rankingRefreshIntervalMinutes, 60);
      expect(
        settingsBackup.homeRankingSourcePriority,
        defaultHomeRankingSourcePriority,
      );
      expect(settingsBackup.disabledHomeRankingSources, isEmpty);
      expect(settingsBackup.radioRefreshIntervalMinutes, 5);
      expect(settingsBackup.minimizeToTrayOnClose,
          Settings().minimizeToTrayOnClose);
      expect(
          settingsBackup.enableGlobalHotkeys, Settings().enableGlobalHotkeys);
    });

    test('SettingsBackup defaults lyrics AI timeout to twenty seconds', () {
      expect(SettingsBackup().lyricsAiTimeoutSeconds, 20);
    });

    test('importData normalizes invalid lyrics AI timeout', () async {
      final backupData = BackupData(
        version: kBackupVersion,
        exportedAt: DateTime(2026, 4, 20),
        appVersion: 'test',
        playlists: const [],
        tracks: const [],
        playHistory: const [],
        searchHistory: const [],
        radioStations: const [],
        settings: SettingsBackup(lyricsAiTimeoutSeconds: 0),
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
      expect(restoredSettings!.lyricsAiTimeoutSeconds, 20);
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
          rememberPlaybackPosition: false,
          tempPlayRewindSeconds: 7,
          neteaseStreamPriority: 'audioOnly',
          autoMatchLyrics: true,
          lyricsAiTitleParsingModeIndex: 3,
          allowPlainLyricsAutoMatch: true,
          lyricsAiEndpoint: 'https://example.test/v1',
          lyricsAiModel: 'test-model',
          lyricsAiTimeoutSeconds: 12,
          lyricsWindowTextColor: 0xFF88CCFF,
          lyricsWindowSecondaryTextColor: 0xCCFFE680,
          lyricsWindowInactiveTextOpacity: 0.42,
          lyricsWindowOutlineEnabled: false,
          lyricsWindowOutlineColor: 0xFF102030,
          lyricsWindowOutlineWidth: 2.25,
          lyricsWindowShadowEnabled: true,
          lyricsWindowShadowColor: 0xAA000000,
          lyricsWindowShadowBlurRadius: 8,
          lyricsWindowShadowOffsetX: 1,
          lyricsWindowShadowOffsetY: 2,
          disabledLyricsSources: 'qqmusic',
          useBilibiliAuthForPlay: true,
          useYoutubeAuthForPlay: true,
          useNeteaseAuthForPlay: false,
          rankingRefreshIntervalMinutes: 15,
          homeRankingSourcePriority: 'youtube,unknown,bilibili,youtube',
          disabledHomeRankingSources: 'netease,unknown',
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
      expect(restoredSettings.lyricsWindowTextColor, 0xFF88CCFF);
      expect(restoredSettings.lyricsWindowSecondaryTextColor, 0xCCFFE680);
      expect(restoredSettings.lyricsWindowInactiveTextOpacity, 0.42);
      expect(restoredSettings.lyricsWindowOutlineEnabled, isFalse);
      expect(restoredSettings.lyricsWindowOutlineColor, 0xFF102030);
      expect(restoredSettings.lyricsWindowOutlineWidth, 2.25);
      expect(restoredSettings.lyricsWindowShadowEnabled, isTrue);
      expect(restoredSettings.lyricsWindowShadowColor, 0xAA000000);
      expect(restoredSettings.lyricsWindowShadowBlurRadius, 8);
      expect(restoredSettings.lyricsWindowShadowOffsetX, 1);
      expect(restoredSettings.lyricsWindowShadowOffsetY, 2);
      expect(restoredSettings.disabledLyricsSources, 'qqmusic');
      expect(restoredSettings.useBilibiliAuthForPlay, isTrue);
      expect(restoredSettings.useYoutubeAuthForPlay, isTrue);
      expect(restoredSettings.useNeteaseAuthForPlay, isFalse);
      expect(restoredSettings.rankingRefreshIntervalMinutes, 15);
      expect(
        restoredSettings.homeRankingSourcePriority,
        'youtube,bilibili,netease',
      );
      expect(restoredSettings.homeRankingSourcePriorityList, [
        'youtube',
        'bilibili',
        'netease',
      ]);
      expect(restoredSettings.disabledHomeRankingSources, 'netease');
      expect(restoredSettings.disabledHomeRankingSourcesSet, {'netease'});
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

    test(
      'importData sanitizes Windows hotkey config from backup',
      () async {
        if (!Platform.isWindows) return;

        final importedHotkeyConfig = jsonEncode({
          'bindings': [
            {
              'action': HotkeyAction.playPause.name,
              'keyId': LogicalKeyboardKey.keyA.keyId,
              'modifiers': <String>[],
            },
            {
              'action': HotkeyAction.next.name,
              'keyId': LogicalKeyboardKey.arrowRight.keyId,
              'modifiers': ['control'],
            },
          ],
        });

        final backupData = BackupData(
          version: kBackupVersion,
          exportedAt: DateTime(2026, 5, 25),
          appVersion: 'test',
          playlists: const [],
          tracks: const [],
          playHistory: const [],
          searchHistory: const [],
          radioStations: const [],
          settings: SettingsBackup(
            enableGlobalHotkeys: true,
            hotkeyConfig: importedHotkeyConfig,
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
        final restoredConfig =
            HotkeyConfig.fromJsonString(restoredSettings!.hotkeyConfig);

        expect(result.settingsImported, isTrue);
        expect(result.errors, isEmpty);
        expect(restoredConfig.getBinding(HotkeyAction.playPause)!.isConfigured,
            isFalse);
        expect(restoredConfig.getBinding(HotkeyAction.next)!.modifiers,
            {HotKeyModifier.control});
      },
      skip: !Platform.isWindows ? 'Windows-only hotkey import behavior' : false,
    );

    test('importData restores playlist memberships through mutation service',
        () async {
      final backupData = BackupData(
        version: kBackupVersion,
        exportedAt: DateTime(2026, 5, 3),
        appVersion: 'test',
        playlists: [
          PlaylistBackup(
            name: 'Restored Playlist',
            coverUrl: 'https://img.example/restored-cover.jpg',
            hasCustomCover: true,
            trackKeys: const ['youtube:restored'],
            createdAt: DateTime(2026, 5, 3),
          ),
        ],
        tracks: [
          TrackBackup(
            sourceId: 'restored',
            sourceType: SourceType.youtube.name,
            title: 'Restored Track',
            thumbnailUrl: 'https://img.example/track-cover.jpg',
            createdAt: DateTime(2026, 5, 3),
          ),
        ],
        playHistory: const [],
        searchHistory: const [],
        radioStations: const [],
      );

      final result = await backupService.importData(
        backupData,
        importPlaylists: true,
        importPlayHistory: false,
        importSearchHistory: false,
        importRadioStations: false,
        importLyricsMatches: false,
        importSettings: false,
      );

      final playlist = (await isar.playlists.where().findAll()).single;
      final track = (await isar.tracks.where().findAll()).single;
      expect(result.playlistsImported, 1);
      expect(result.errors, isEmpty);
      expect(playlist.trackIds, [track.id]);
      expect(playlist.coverUrl, 'https://img.example/restored-cover.jpg');
      expect(playlist.hasCustomCover, isTrue);
      expect(track.belongsToPlaylist(playlist.id), isTrue);
      expect(track.playlistInfo.single.playlistName, 'Restored Playlist');
    });

    test('importData restores Netease source types without falling back',
        () async {
      final exportedAt = DateTime(2026, 5, 18);
      final backupData = BackupData(
        version: kBackupVersion,
        exportedAt: exportedAt,
        appVersion: 'test',
        playlists: [
          PlaylistBackup(
            name: 'Netease Import',
            importSourceType: SourceType.netease.name,
            trackKeys: const ['netease:netease-song'],
            createdAt: exportedAt,
          ),
        ],
        tracks: [
          TrackBackup(
            sourceId: 'netease-song',
            sourceType: SourceType.netease.name,
            title: 'Netease Track',
            createdAt: exportedAt,
          ),
        ],
        playHistory: [
          PlayHistoryBackup(
            sourceId: 'netease-history',
            sourceType: SourceType.netease.name,
            title: 'Netease History',
            playedAt: exportedAt,
          ),
        ],
        searchHistory: const [],
        radioStations: [
          RadioStationBackup(
            url: 'https://music.163.com/radio/test',
            title: 'Netease Radio',
            sourceType: SourceType.netease.name,
            sourceId: 'netease-radio',
            createdAt: exportedAt,
          ),
        ],
      );

      final result = await backupService.importData(
        backupData,
        importPlaylists: true,
        importPlayHistory: true,
        importSearchHistory: false,
        importRadioStations: true,
        importLyricsMatches: false,
        importSettings: false,
      );

      final track = (await isar.tracks.where().findAll()).single;
      final playlist = (await isar.playlists.where().findAll()).single;
      final history = (await isar.playHistorys.where().findAll()).single;
      final radio = (await isar.radioStations.where().findAll()).single;

      expect(result.errors, isEmpty);
      expect(track.sourceType, SourceType.netease);
      expect(playlist.importSourceType, SourceType.netease);
      expect(history.sourceType, SourceType.netease);
      expect(radio.sourceType, SourceType.netease);
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
        ..lyricsAiTimeoutSeconds = 15
        ..lyricsWindowTextColor = 0xFF88CCFF
        ..lyricsWindowSecondaryTextColor = 0xCCFFE680
        ..lyricsWindowInactiveTextOpacity = 0.42
        ..lyricsWindowOutlineEnabled = false
        ..lyricsWindowOutlineColor = 0xFF102030
        ..lyricsWindowOutlineWidth = 2.25
        ..lyricsWindowShadowEnabled = true
        ..lyricsWindowShadowColor = 0xAA000000
        ..lyricsWindowShadowBlurRadius = 8
        ..lyricsWindowShadowOffsetX = 1
        ..lyricsWindowShadowOffsetY = 2
        ..homeRankingSourcePriority = 'youtube,unknown,bilibili,youtube'
        ..disabledHomeRankingSources = 'netease,unknown';
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
      expect(settingsJson['lyricsWindowTextColor'], 0xFF88CCFF);
      expect(settingsJson['lyricsWindowSecondaryTextColor'], 0xCCFFE680);
      expect(settingsJson['lyricsWindowInactiveTextOpacity'], 0.42);
      expect(settingsJson['lyricsWindowOutlineEnabled'], isFalse);
      expect(settingsJson['lyricsWindowOutlineColor'], 0xFF102030);
      expect(settingsJson['lyricsWindowOutlineWidth'], 2.25);
      expect(settingsJson['lyricsWindowShadowEnabled'], isTrue);
      expect(settingsJson['lyricsWindowShadowColor'], 0xAA000000);
      expect(settingsJson['lyricsWindowShadowBlurRadius'], 8);
      expect(settingsJson['lyricsWindowShadowOffsetX'], 1);
      expect(settingsJson['lyricsWindowShadowOffsetY'], 2);
      expect(
        settingsJson['homeRankingSourcePriority'],
        'youtube,bilibili,netease',
      );
      expect(settingsJson['disabledHomeRankingSources'], 'netease');
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
