import 'dart:convert';
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
import 'package:fmp/data/repositories/playlist_mutation_repository.dart';
import 'package:fmp/data/database/database_migration.dart';
import 'package:fmp/data/database/database_provider.dart';
import 'package:fmp/services/backup/backup_data.dart';
import 'package:fmp/services/backup/backup_service.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:isar_community/isar.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../../support/isar_test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('backup settings behavior', () {
    late Directory tempDir;
    late Isar isar;
    late BackupService backupService;

    setUpAll(() async {
      await initializeIsarForTests();
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
      // 沒有 sourceSettings 也沒有 v3 具名鍵時，折疊出的是每源預設。
      final netease = settingsBackup.sourceSettings.firstWhere(
        (e) => e.sourceId == SourceIds.netease,
      );
      expect(netease.streamPriority, 'audioOnly');
      expect(netease.useAuthForPlay, isTrue);
      expect(
        settingsBackup.sourceSettings
            .firstWhere((e) => e.sourceId == SourceIds.bilibili)
            .useAuthForPlay,
        isFalse,
      );
      expect(
        settingsBackup.sourceSettings
            .firstWhere((e) => e.sourceId == SourceIds.youtube)
            .useAuthForPlay,
        isFalse,
      );
      expect(settingsBackup.rankingRefreshIntervalMinutes, 60);
      expect(
        settingsBackup.homeRankingSourcePriority,
        defaultHomeRankingSourcePriority,
      );
      expect(settingsBackup.disabledHomeRankingSources, isEmpty);
      expect(settingsBackup.radioRefreshIntervalMinutes, 5);
      expect(
        settingsBackup.minimizeToTrayOnClose,
        Settings().minimizeToTrayOnClose,
      );
      expect(
        settingsBackup.enableGlobalHotkeys,
        Settings().enableGlobalHotkeys,
      );
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
          ..railExpanded = false
          ..detailPanelExpanded = true
          ..detailPanelWidth = 380
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
            sourceSettings: const [
              SourceSettingsBackup(
                sourceId: SourceIds.bilibili,
                streamPriority: 'audioOnly,muxed',
                useAuthForPlay: true,
              ),
              SourceSettingsBackup(
                sourceId: SourceIds.youtube,
                streamPriority: 'audioOnly,muxed,hls',
                useAuthForPlay: true,
              ),
              SourceSettingsBackup(
                sourceId: SourceIds.netease,
                streamPriority: 'audioOnly',
                useAuthForPlay: false,
              ),
            ],
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
            rankingRefreshIntervalMinutes: 15,
            homeRankingSourcePriority: 'youtube,unknown,bilibili,youtube',
            disabledHomeRankingSources: 'netease,unknown',
            radioRefreshIntervalMinutes: 9,
            minimizeToTrayOnClose: true,
            enableGlobalHotkeys: true,
            launchAtStartup: true,
            launchMinimized: true,
            railExpanded: true,
            detailPanelExpanded: false,
            detailPanelWidth: 420,
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
        expect(restoredSettings.streamPriorityFor(SourceIds.netease), [
          StreamType.audioOnly,
        ]);
        expect(restoredSettings.autoMatchLyrics, isTrue);
        expect(restoredSettings.lyricsAiTitleParsingModeIndex, 3);
        expect(
          restoredSettings.lyricsAiTitleParsingMode,
          LyricsAiTitleParsingMode.advancedAiSelect,
        );
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
        expect(restoredSettings.useAuthForPlay(SourceIds.bilibili), isTrue);
        expect(restoredSettings.useAuthForPlay(SourceIds.youtube), isTrue);
        expect(restoredSettings.useAuthForPlay(SourceIds.netease), isFalse);
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

        // 版面欄位無條件還原：`_DesktopLayout` 由螢幕寬度斷點選出，不是桌面平台
        // 專屬能力，所以不跟著 `Platform.isWindows` 走。
        expect(restoredSettings.railExpanded, isTrue);
        expect(restoredSettings.detailPanelExpanded, isFalse);
        expect(restoredSettings.detailPanelWidth, 420);

        if (Platform.isWindows) {
          expect(restoredSettings.minimizeToTrayOnClose, isTrue);
          expect(restoredSettings.enableGlobalHotkeys, isTrue);
          expect(restoredSettings.launchAtStartup, isTrue);
          expect(restoredSettings.launchMinimized, isTrue);
          expect(
            restoredSettings.hotkeyConfig,
            jsonEncode({'next': 'Ctrl+Alt+Right'}),
          );
        } else {
          expect(restoredSettings.minimizeToTrayOnClose, isFalse);
          expect(restoredSettings.enableGlobalHotkeys, isFalse);
          expect(restoredSettings.launchAtStartup, isFalse);
          expect(restoredSettings.launchMinimized, isFalse);
          expect(
            restoredSettings.hotkeyConfig,
            jsonEncode({'playPause': 'Ctrl+Alt+P'}),
          );
        }
      },
    );

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
        final restoredConfig = HotkeyConfig.fromJsonString(
          restoredSettings!.hotkeyConfig,
        );

        expect(result.settingsImported, isTrue);
        expect(result.errors, isEmpty);
        expect(
          restoredConfig.getBinding(HotkeyAction.playPause)!.isConfigured,
          isFalse,
        );
        expect(restoredConfig.getBinding(HotkeyAction.next)!.modifiers, {
          HotKeyModifier.control,
        });
      },
      skip: !Platform.isWindows ? 'Windows-only hotkey import behavior' : false,
    );

    test(
      'importData restores playlist memberships through mutation service',
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
              sourceType: SourceIds.youtube,
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
      },
    );

    test('a write failure leaves the database exactly as it was', () async {
      final seedTrack = Track()
        ..sourceId = 'kept'
        ..sourceType = SourceIds.youtube
        ..title = 'Kept Track'
        ..createdAt = DateTime(2026, 5, 1);
      final seedRadio = RadioStation()
        ..url = 'https://radio.example/kept'
        ..title = 'Kept Radio'
        ..sourceType = SourceIds.bilibili
        ..sourceId = 'kept-room'
        ..createdAt = DateTime(2026, 5, 1);
      await isar.writeTxn(() async {
        await isar.tracks.put(seedTrack);
        await isar.radioStations.put(seedRadio);
      });

      final before = await _snapshot(isar);

      // 寫入階段中途炸掉：歌單成員寫到一半，後面還有電台與設定沒寫。
      final failing = BackupService(
        isar,
        mutationService: _ThrowingMutationRepository(isar),
      );

      await expectLater(
        failing.importData(
          BackupData(
            version: kBackupVersion,
            exportedAt: DateTime(2026, 5, 4),
            appVersion: 'test',
            playlists: [
              PlaylistBackup(
                name: 'Half Written',
                trackKeys: const ['youtube:incoming'],
                createdAt: DateTime(2026, 5, 4),
              ),
            ],
            tracks: [
              TrackBackup(
                sourceId: 'incoming',
                sourceType: SourceIds.youtube,
                title: 'Incoming Track',
                createdAt: DateTime(2026, 5, 4),
              ),
            ],
            playHistory: const [],
            searchHistory: const [],
            radioStations: [
              RadioStationBackup(
                url: 'https://radio.example/new',
                title: 'New Radio',
                sourceType: SourceIds.bilibili,
                sourceId: 'new-room',
                createdAt: DateTime(2026, 5, 4),
              ),
            ],
            settings: SettingsBackup(themeModeIndex: 2),
          ),
        ),
        throwsA(isA<StateError>()),
      );

      expect(await _snapshot(isar), before);
    });

    test('duplicate play history inside one backup is inserted once', () async {
      final playedAt = DateTime(2026, 5, 5, 12, 30);
      final entry = PlayHistoryBackup(
        sourceId: 'dup',
        sourceType: SourceIds.youtube,
        title: 'Duplicated',
        playedAt: playedAt,
      );

      final result = await backupService.importData(
        BackupData(
          version: kBackupVersion,
          exportedAt: DateTime(2026, 5, 5),
          appVersion: 'test',
          playlists: const [],
          tracks: const [],
          playHistory: [entry, entry],
          searchHistory: const [],
          radioStations: const [],
        ),
        importPlaylists: false,
        importPlayHistory: true,
        importSearchHistory: false,
        importRadioStations: false,
        importLyricsMatches: false,
        importSettings: false,
      );

      expect(result.playHistoryImported, 1);
      expect(result.playHistorySkipped, 1);
      expect(await isar.playHistorys.where().findAll(), hasLength(1));
    });

    test(
      'importData restores Netease source types without falling back',
      () async {
        final exportedAt = DateTime(2026, 5, 18);
        final backupData = BackupData(
          version: kBackupVersion,
          exportedAt: exportedAt,
          appVersion: 'test',
          playlists: [
            PlaylistBackup(
              name: 'Netease Import',
              importSourceType: SourceIds.netease,
              trackKeys: const ['netease:netease-song'],
              createdAt: exportedAt,
            ),
          ],
          tracks: [
            TrackBackup(
              sourceId: 'netease-song',
              sourceType: SourceIds.netease,
              title: 'Netease Track',
              createdAt: exportedAt,
            ),
          ],
          playHistory: [
            PlayHistoryBackup(
              sourceId: 'netease-history',
              sourceType: SourceIds.netease,
              title: 'Netease History',
              playedAt: exportedAt,
            ),
          ],
          searchHistory: const [],
          radioStations: [
            RadioStationBackup(
              url: 'https://music.163.com/radio/test',
              title: 'Netease Radio',
              sourceType: SourceIds.netease,
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
        expect(track.sourceType, SourceIds.netease);
        expect(playlist.importSourceType, SourceIds.netease);
        expect(history.sourceType, SourceIds.netease);
        expect(radio.sourceType, SourceIds.netease);
      },
    );

    test('importData keeps a source id it does not recognise', () async {
      // 別人用更新版本（多了第四個音源）匯出的備份，不能在匯入時被靜默
      // 改寫成 B 站 —— 那會產生永遠播不出來的假 B 站曲目，而且不可逆。
      final exportedAt = DateTime(2026, 6, 1);
      const unknown = 'soundcloud';
      final backupData = BackupData(
        version: kBackupVersion,
        exportedAt: exportedAt,
        appVersion: 'test',
        playlists: [
          PlaylistBackup(
            name: 'Future Import',
            importSourceType: unknown,
            trackKeys: const ['$unknown:future-song'],
            createdAt: exportedAt,
          ),
        ],
        tracks: [
          TrackBackup(
            sourceId: 'future-song',
            sourceType: unknown,
            title: 'Future Track',
            createdAt: exportedAt,
          ),
        ],
        playHistory: [
          PlayHistoryBackup(
            sourceId: 'future-history',
            sourceType: unknown,
            title: 'Future History',
            playedAt: exportedAt,
          ),
        ],
        searchHistory: const [],
        radioStations: [
          RadioStationBackup(
            url: 'https://example.invalid/radio/1',
            title: 'Future Radio',
            sourceType: unknown,
            sourceId: 'future-radio',
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

      expect(result.errors, isEmpty);
      expect((await isar.tracks.where().findAll()).single.sourceType, unknown);
      expect(
        (await isar.playlists.where().findAll()).single.importSourceType,
        unknown,
      );
      expect(
        (await isar.playHistorys.where().findAll()).single.sourceType,
        unknown,
      );
      expect(
        (await isar.radioStations.where().findAll()).single.sourceType,
        unknown,
      );
    });

    test(
      'exportData includes lyrics AI settings without secure API key',
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
        final json =
            jsonDecode(await File(outputPath).readAsString())
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
      },
    );

    test('exportData includes v2 playlist track and radio metadata', () async {
      final outputPath = '${tempDir.path}/export_v2.json';
      FilePicker.platform = _FakeFilePicker(saveFilePath: outputPath);
      final createdAt = DateTime(2026, 6, 1, 12);
      final updatedAt = DateTime(2026, 6, 2, 13);
      final refreshedAt = DateTime(2026, 6, 3, 14);
      final lastPlayedAt = DateTime(2026, 6, 4, 15);

      final track = Track()
        ..sourceId = 'track-v2'
        ..sourceType = SourceIds.bilibili
        ..title = 'Track V2'
        ..isAvailable = false
        ..isVip = true
        ..unavailableReason = 'region locked'
        ..bilibiliAid = 987654321
        ..createdAt = createdAt
        ..updatedAt = updatedAt;
      final playlist = Playlist()
        ..name = 'Playlist V2'
        ..sourceUrl = 'https://example.test/playlist'
        ..importSourceType = SourceIds.bilibili
        ..lastRefreshed = refreshedAt
        ..ownerName = 'Owner Name'
        ..ownerUserId = 'owner-1'
        ..useAuthForRefresh = true
        ..createdAt = createdAt
        ..updatedAt = updatedAt;
      final radio = RadioStation()
        ..url = 'https://example.test/live'
        ..title = 'Radio V2'
        ..sourceType = SourceIds.bilibili
        ..sourceId = 'room-v2'
        ..createdAt = createdAt
        ..lastPlayedAt = lastPlayedAt;

      await isar.writeTxn(() async {
        final trackId = await isar.tracks.put(track);
        playlist.trackIds = [trackId];
        await isar.playlists.put(playlist);
        await isar.radioStations.put(radio);
      });

      final exportedPath = await backupService.exportData();

      expect(exportedPath, outputPath);
      final json =
          jsonDecode(await File(outputPath).readAsString())
              as Map<String, dynamic>;
      expect(json['version'], kBackupVersion);
      final playlistJson =
          (json['playlists'] as List<dynamic>).single as Map<String, dynamic>;
      final trackJson =
          (json['tracks'] as List<dynamic>).single as Map<String, dynamic>;
      final radioJson =
          (json['radioStations'] as List<dynamic>).single
              as Map<String, dynamic>;

      expect(playlistJson['lastRefreshed'], refreshedAt.toIso8601String());
      expect(playlistJson['ownerName'], 'Owner Name');
      expect(playlistJson['ownerUserId'], 'owner-1');
      expect(playlistJson['useAuthForRefresh'], isTrue);
      expect(playlistJson['updatedAt'], updatedAt.toIso8601String());
      expect(trackJson['isAvailable'], isFalse);
      expect(trackJson['isVip'], isTrue);
      expect(trackJson['unavailableReason'], 'region locked');
      expect(trackJson['bilibiliAid'], 987654321);
      expect(trackJson['updatedAt'], updatedAt.toIso8601String());
      expect(radioJson['lastPlayedAt'], lastPlayedAt.toIso8601String());
    });

    test('importData restores v2 playlist track and radio metadata', () async {
      final createdAt = DateTime(2026, 6, 1, 12);
      final updatedAt = DateTime(2026, 6, 2, 13);
      final refreshedAt = DateTime(2026, 6, 3, 14);
      final lastPlayedAt = DateTime(2026, 6, 4, 15);

      final backupData = BackupData(
        version: 2,
        exportedAt: DateTime(2026, 6, 5, 16),
        appVersion: 'test',
        playlists: [
          PlaylistBackup(
            name: 'Restored Playlist V2',
            sourceUrl: 'https://example.test/playlist',
            importSourceType: SourceIds.bilibili,
            lastRefreshed: refreshedAt,
            ownerName: 'Owner Name',
            ownerUserId: 'owner-1',
            useAuthForRefresh: true,
            trackKeys: const ['bilibili:track-v2'],
            createdAt: createdAt,
            updatedAt: updatedAt,
          ),
        ],
        tracks: [
          TrackBackup(
            sourceId: 'track-v2',
            sourceType: SourceIds.bilibili,
            title: 'Track V2',
            isAvailable: false,
            isVip: true,
            unavailableReason: 'region locked',
            bilibiliAid: 987654321,
            createdAt: createdAt,
            updatedAt: updatedAt,
          ),
        ],
        playHistory: const [],
        searchHistory: const [],
        radioStations: [
          RadioStationBackup(
            url: 'https://example.test/live',
            title: 'Radio V2',
            sourceType: SourceIds.bilibili,
            sourceId: 'room-v2',
            createdAt: createdAt,
            lastPlayedAt: lastPlayedAt,
          ),
        ],
      );

      final result = await backupService.importData(
        backupData,
        importPlaylists: true,
        importPlayHistory: false,
        importSearchHistory: false,
        importRadioStations: true,
        importLyricsMatches: false,
        importSettings: false,
      );

      final playlist = (await isar.playlists.where().findAll()).single;
      final track = (await isar.tracks.where().findAll()).single;
      final radio = (await isar.radioStations.where().findAll()).single;

      expect(result.errors, isEmpty);
      expect(playlist.lastRefreshed, refreshedAt);
      expect(playlist.ownerName, 'Owner Name');
      expect(playlist.ownerUserId, 'owner-1');
      expect(playlist.useAuthForRefresh, isTrue);
      expect(playlist.updatedAt, updatedAt);
      expect(track.isAvailable, isFalse);
      expect(track.isVip, isTrue);
      expect(track.unavailableReason, 'region locked');
      expect(track.bilibiliAid, 987654321);
      expect(track.updatedAt, updatedAt);
      expect(radio.lastPlayedAt, lastPlayedAt);
    });

    test(
      'validateBackupData rejects backups from newer format versions',
      () async {
        final backupData = BackupData(
          version: kBackupVersion + 1,
          exportedAt: DateTime(2026, 6, 10),
          appVersion: 'future',
          playlists: const [],
          tracks: const [],
          playHistory: const [],
          searchHistory: const [],
          radioStations: const [],
          settings: SettingsBackup(),
        );

        final validation = backupService.validateBackupData(backupData);

        expect(validation.isValid, isFalse);
        expect(validation.code, BackupValidationCode.unsupportedVersion);
        expect(validation.backupVersion, kBackupVersion + 1);
        expect(validation.supportedVersion, kBackupVersion);
        expect(validation.appVersion, 'future');
        expect(validation.message, isEmpty);
      },
    );

    test(
      'validateBackupData rejects backups with no importable sections',
      () async {
        final backupData = BackupData(
          version: kBackupVersion,
          exportedAt: DateTime(2026, 6, 10),
          appVersion: 'test',
          playlists: const [],
          tracks: const [],
          playHistory: const [],
          searchHistory: const [],
          radioStations: const [],
        );

        final validation = backupService.validateBackupData(backupData);

        expect(validation.isValid, isFalse);
        expect(validation.code, BackupValidationCode.emptyBackup);
      },
    );

    test(
      'validateBackupData accepts current backup format with importable data',
      () async {
        final backupData = BackupData(
          version: kBackupVersion,
          exportedAt: DateTime(2026, 6, 10),
          appVersion: 'test',
          playlists: const [],
          tracks: const [],
          playHistory: [
            PlayHistoryBackup(
              sourceId: 'history',
              sourceType: SourceIds.youtube,
              title: 'History',
              playedAt: DateTime(2026, 6, 10),
            ),
          ],
          searchHistory: const [],
          radioStations: const [],
        );

        final validation = backupService.validateBackupData(backupData);

        expect(validation.isValid, isTrue);
        expect(validation.code, BackupValidationCode.valid);
      },
    );

    test('validateBackupData accepts backups containing only tracks', () async {
      final backupData = BackupData(
        version: kBackupVersion,
        exportedAt: DateTime(2026, 6, 10),
        appVersion: 'test',
        playlists: const [],
        tracks: [
          TrackBackup(
            sourceId: 'standalone',
            sourceType: SourceIds.youtube,
            title: 'Standalone Track',
            createdAt: DateTime(2026, 6, 10),
          ),
        ],
        playHistory: const [],
        searchHistory: const [],
        radioStations: const [],
      );

      final validation = backupService.validateBackupData(backupData);

      expect(validation.isValid, isTrue);
      expect(validation.code, BackupValidationCode.valid);
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

/// 逐 collection 的內容快照，用來斷言「一列都沒動」。
Future<Map<String, List<String>>> _snapshot(Isar isar) async {
  return {
    'playlists': [
      for (final p in await isar.playlists.where().findAll())
        '${p.id}|${p.name}|${p.trackIds}|${p.coverUrl}|${p.updatedAt}',
    ],
    'tracks': [
      for (final t in await isar.tracks.where().findAll())
        '${t.id}|${t.uniqueKey}|${t.title}|${t.updatedAt}',
    ],
    'playHistory': [
      for (final h in await isar.playHistorys.where().findAll())
        '${h.id}|${h.trackKey}|${h.playedAt}',
    ],
    'searchHistory': [
      for (final q in await isar.searchHistorys.where().findAll())
        '${q.id}|${q.query}',
    ],
    'radioStations': [
      for (final r in await isar.radioStations.where().findAll())
        '${r.id}|${r.url}|${r.title}',
    ],
    'lyricsMatches': [
      for (final m in await isar.lyricsMatchs.where().findAll())
        '${m.id}|${m.trackUniqueKey}|${m.lyricsSource}',
    ],
    'settings': [
      for (final s in [await isar.settings.get(0)])
        if (s != null) '${s.themeModeIndex}|${s.maxCacheSizeMB}',
    ],
  };
}

/// 在寫入交易的中途拋錯，用來驗證整批回滾。
class _ThrowingMutationRepository extends PlaylistMutationRepository {
  _ThrowingMutationRepository(Isar isar) : super(isar: isar);

  @override
  Future<PlaylistMutationResult> addTracksInTxn(
    int playlistId,
    List<Track> tracks,
  ) async {
    throw StateError('write phase blew up');
  }
}
