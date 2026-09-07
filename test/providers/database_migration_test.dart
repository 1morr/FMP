import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/constants/app_layout.dart';
import 'package:fmp/data/models/lyrics_title_parse_cache.dart';
import 'package:fmp/data/models/play_queue.dart';
import 'package:fmp/data/models/settings.dart';
import 'package:fmp/data/models/source_ids.dart';
import 'package:fmp/providers/database/database_migration.dart';
import 'package:fmp/providers/database/database_provider.dart';
import 'package:isar_community/isar.dart';
import '../support/isar_test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('database migration', () {
    late Directory tempDir;
    late Isar isar;

    setUpAll(() async {
      await initializeIsarForTests();
    });

    tearDown(() async {
      await isar.close(deleteFromDisk: true);
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    Future<void> openTestDatabase() async {
      tempDir = await Directory.systemTemp.createTemp(
        'database_migration_test_',
      );
      isar = await Isar.open(
        [SettingsSchema, PlayQueueSchema, LyricsTitleParseCacheSchema],
        directory: tempDir.path,
        name: 'database_migration_test',
      );
    }

    test('initializes bootstrap defaults for settings and queue', () async {
      await openTestDatabase();

      await runDatabaseMigration(isar);

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

    test('initializes Home ranking source defaults', () async {
      await openTestDatabase();

      await runDatabaseMigration(isar);

      final settings = await isar.settings.get(0);
      expect(settings, isNotNull);
      expect(settings!.homeRankingSourcePriority, 'bilibili,youtube,netease');
      expect(settings.homeRankingSourcePriorityList, [
        'bilibili',
        'youtube',
        'netease',
      ]);
      expect(settings.disabledHomeRankingSources, '');
      expect(settings.disabledHomeRankingSourcesSet, isEmpty);
    });

    test('repairs empty Home ranking source priority', () async {
      await openTestDatabase();

      final upgradedSettings = Settings()
        ..homeRankingSourcePriority = ''
        ..disabledHomeRankingSources = '';
      await isar.writeTxn(() async {
        await isar.settings.put(upgradedSettings);
      });

      await runDatabaseMigrationForTesting(isar);

      final migratedSettings = await isar.settings.get(0);
      expect(migratedSettings, isNotNull);
      expect(
        migratedSettings!.homeRankingSourcePriority,
        'bilibili,youtube,netease',
      );
      expect(migratedSettings.disabledHomeRankingSources, '');
    });

    test(
      'normalizes Home ranking source priority and preserves disabled sources',
      () async {
        await openTestDatabase();

        final settings = Settings()
          ..homeRankingSourcePriority = 'youtube,unknown,bilibili,youtube'
          ..disabledHomeRankingSources = 'netease,unknown';
        await isar.writeTxn(() async {
          await isar.settings.put(settings);
        });

        await runDatabaseMigrationForTesting(isar);

        final migratedSettings = await isar.settings.get(0);
        expect(migratedSettings, isNotNull);
        expect(
          migratedSettings!.homeRankingSourcePriority,
          'youtube,bilibili,netease',
        );
        expect(migratedSettings!.homeRankingSourcePriorityList, [
          'youtube',
          'bilibili',
          'netease',
        ]);
        expect(migratedSettings.disabledHomeRankingSources, 'netease');
        expect(migratedSettings.disabledHomeRankingSourcesSet, {'netease'});
      },
    );

    test('repairs all disabled Home ranking sources', () async {
      await openTestDatabase();

      final settings = Settings()
        ..homeRankingSourcePriority = 'netease,youtube,bilibili'
        ..disabledHomeRankingSources = 'bilibili,youtube,netease';
      await isar.writeTxn(() async {
        await isar.settings.put(settings);
      });

      await runDatabaseMigrationForTesting(isar);

      final migratedSettings = await isar.settings.get(0);
      expect(migratedSettings, isNotNull);
      expect(
        migratedSettings!.homeRankingSourcePriority,
        'netease,youtube,bilibili',
      );
      expect(migratedSettings.disabledHomeRankingSources, '');
      expect(migratedSettings.disabledHomeRankingSourcesSet, isEmpty);
    });

    test('clears AI title parse cache during startup migration', () async {
      await openTestDatabase();
      final cache = LyricsTitleParseCache()
        ..trackUniqueKey = 'youtube:abc'
        ..sourceType = 'youtube'
        ..parsedTrackName = 'Old song'
        ..confidence = 1
        ..provider = 'openai-compatible'
        ..model = 'test-model';
      await isar.writeTxn(() => isar.lyricsTitleParseCaches.put(cache));

      await runDatabaseMigrationForTesting(isar);

      expect(await isar.lyricsTitleParseCaches.count(), 0);
    });

    test(
      'repairs AI title parsing fields from Isar upgrade defaults',
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
        expect(migratedSettings!.lyricsAiTitleParsingModeIndex, 0);
        expect(
          migratedSettings.lyricsAiTitleParsingMode,
          LyricsAiTitleParsingMode.off,
        );
        expect(migratedSettings.lyricsAiTimeoutSeconds, 20);
        expect(migratedSettings.lyricsAiEndpoint, isEmpty);
        expect(migratedSettings.lyricsAiModel, isEmpty);
      },
    );

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
      expect(migratedSettings!.lyricsAiTitleParsingModeIndex, 0);
      expect(
        migratedSettings.lyricsAiTitleParsingMode,
        LyricsAiTitleParsingMode.off,
      );
      expect(migratedSettings.lyricsAiTimeoutSeconds, 10);
    });

    test('repairs empty audio stream defaults to current priorities', () async {
      await openTestDatabase();

      final settings = Settings()
        ..audioFormatPriority = ''
        ..youtubeStreamPriority = ''
        ..bilibiliStreamPriority = '';
      await isar.writeTxn(() async {
        await isar.settings.put(settings);
      });

      await runDatabaseMigrationForTesting(isar);

      final migratedSettings = await isar.settings.get(0);
      expect(migratedSettings, isNotNull);
      expect(migratedSettings!.audioFormatPriority, 'opus,aac');
      expect(migratedSettings.streamPriorityFor(SourceIds.youtube), [
        StreamType.audioOnly,
        StreamType.muxed,
        StreamType.hls,
      ]);
      expect(migratedSettings.streamPriorityFor(SourceIds.bilibili), [
        StreamType.audioOnly,
        StreamType.muxed,
      ]);
    });

    test('repairs legacy fallback AI mode index to off', () async {
      await openTestDatabase();
      final settings = Settings()
        ..lyricsAiTitleParsingModeIndex = 1
        ..lyricsAiTimeoutSeconds = 10;
      await isar.writeTxn(() async => isar.settings.put(settings));
      await runDatabaseMigrationForTesting(isar);
      final migratedSettings = await isar.settings.get(0);
      expect(migratedSettings!.lyricsAiTitleParsingModeIndex, 0);
      expect(
        migratedSettings.lyricsAiTitleParsingMode,
        LyricsAiTitleParsingMode.off,
      );
    });

    test(
      'repairs legacy playback and lyrics defaults only for legacy signature',
      () async {
        await openTestDatabase();

        final legacySettings = Settings()
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
      },
    );

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

    test(
      'preserves intentional legacy-shaped playback and lyrics values',
      () async {
        await openTestDatabase();

        final intentionallyConfiguredSettings = Settings()
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
      },
    );

    test(
      'migrates NetEase defaults when old settings have empty priority',
      () async {
        await openTestDatabase();

        final legacySettings = Settings()
          ..useNeteaseAuthForPlay = false
          ..neteaseStreamPriority = '';
        await isar.writeTxn(() async {
          await isar.settings.put(legacySettings);
        });

        await runDatabaseMigrationForTesting(isar);

        final migratedSettings = await isar.settings.get(0);
        expect(migratedSettings, isNotNull);
        expect(migratedSettings!.useNeteaseAuthForPlay, isTrue);
        expect(migratedSettings.neteaseStreamPriority, 'audioOnly');
      },
    );

    test(
      'preserves intentional NetEase opt-out on repeated migration runs',
      () async {
        await openTestDatabase();

        final modernSettings = Settings()
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
        expect(migratedSettings.neteaseStreamPriority, 'audioOnly');
      },
    );

    test('rescues layout fields from their Isar upgrade defaults', () async {
      await openTestDatabase();

      // 模擬 Phase 3 之前的那一列：新欄位讀出來會是 bool false / double NaN，
      // 而 detailPanelExpanded 的業務預設是 true。
      final legacySettings = Settings()
        ..schemaVersion = -9223372036854775808
        ..railExpanded = false
        ..detailPanelExpanded = false
        ..detailPanelWidth = double.nan;
      await isar.writeTxn(() async {
        await isar.settings.put(legacySettings);
      });

      await runDatabaseMigration(isar);

      final migrated = await isar.settings.get(0);
      expect(migrated!.railExpanded, isFalse);
      expect(migrated.detailPanelExpanded, isTrue);
      expect(migrated.detailPanelWidth, 380);
    });

    test(
      'clamps a layout width that is out of range on every launch',
      () async {
        await openTestDatabase();

        final settings = Settings()
          ..schemaVersion = 1
          ..detailPanelWidth = 9999;
        await isar.writeTxn(() async {
          await isar.settings.put(settings);
        });

        await runDatabaseMigration(isar);

        // 夾到邊界，不是重設成預設值：這條不變式只負責「不是垃圾值」，真正的
        // 上限是視窗寬的一個比例，由 AppLayout.detailPanelWidthFor 在渲染期收斂。
        expect(
          (await isar.settings.get(0))!.detailPanelWidth,
          AppLayout.detailPanelStoredMax,
        );
      },
    );

    test('lifts a stored width that is below the new minimum', () async {
      await openTestDatabase();

      // 面板下限從 280 提到 320。停在 300 的使用者應該得到 320，而不是被丟回
      // 預設值 —— 重設會抹掉他們真的做過的選擇。
      final settings = Settings()
        ..schemaVersion = 1
        ..detailPanelWidth = 300;
      await isar.writeTxn(() async {
        await isar.settings.put(settings);
      });

      await runDatabaseMigration(isar);

      expect(
        (await isar.settings.get(0))!.detailPanelWidth,
        AppLayout.detailPanelMin,
      );
    });

    test('a non-finite width falls back to the default', () async {
      await openTestDatabase();

      final settings = Settings()
        ..schemaVersion = 1
        ..detailPanelWidth = double.nan;
      await isar.writeTxn(() async {
        await isar.settings.put(settings);
      });

      await runDatabaseMigration(isar);

      expect(
        (await isar.settings.get(0))!.detailPanelWidth,
        AppLayout.detailPanelDefault,
      );
    });

    test('treats Isar minLong as version zero', () async {
      await openTestDatabase();

      // Isar 對舊列缺少的非空 int 欄位回傳 minLong 而不是 0 —— 在真實資料庫上
      // 實測過。版本比對如果只看 == 0 就會漏掉所有真正的舊資料庫。
      final legacySettings = Settings()
        ..schemaVersion = -9223372036854775808
        ..useNeteaseAuthForPlay = false
        ..neteaseStreamPriority = '';
      await isar.writeTxn(() async {
        await isar.settings.put(legacySettings);
      });

      await runDatabaseMigration(isar);

      final migrated = await isar.settings.get(0);
      expect(migrated!.schemaVersion, kFmpSchemaVersion);
      expect(
        migrated.useAuthForPlay(SourceIds.netease),
        isTrue,
        reason: 'the v0 step must have run and been folded by v1 to v2',
      );
    });

    test(
      'the v1 to v2 step folds the six named fields into sourceSettings',
      () async {
        await openTestDatabase();

        final v1 = Settings()
          ..schemaVersion = 1
          ..bilibiliStreamPriority = 'muxed'
          ..youtubeStreamPriority = 'hls,audioOnly'
          ..neteaseStreamPriority = 'audioOnly,muxed'
          ..useBilibiliAuthForPlay = true
          ..useYoutubeAuthForPlay = false
          ..useNeteaseAuthForPlay = false;
        await isar.writeTxn(() async => isar.settings.put(v1));

        await runDatabaseMigration(isar);

        final after = (await isar.settings.get(0))!;
        expect(after.schemaVersion, 2);
        expect(after.streamPriorityFor(SourceIds.bilibili), [StreamType.muxed]);
        expect(after.streamPriorityFor(SourceIds.youtube), [
          StreamType.hls,
          StreamType.audioOnly,
        ]);
        expect(after.streamPriorityFor(SourceIds.netease), [
          StreamType.audioOnly,
          StreamType.muxed,
        ]);
        expect(after.useAuthForPlay(SourceIds.bilibili), isTrue);
        expect(after.useAuthForPlay(SourceIds.youtube), isFalse);
        expect(after.useAuthForPlay(SourceIds.netease), isFalse);
      },
    );

    test('the v1 to v2 step leaves the legacy fields untouched', () async {
      // 降級（裝回舊版 APK）時舊版只讀得到這六個欄位。折疊如果把它們清空，
      // 舊版的不變式修復會把使用者的選擇覆蓋成預設 —— 每源設定就這樣沒了。
      await openTestDatabase();

      final v1 = Settings()
        ..schemaVersion = 1
        ..bilibiliStreamPriority = 'muxed'
        ..useBilibiliAuthForPlay = true;
      await isar.writeTxn(() async => isar.settings.put(v1));

      await runDatabaseMigration(isar);

      final after = (await isar.settings.get(0))!;
      expect(after.bilibiliStreamPriority, 'muxed');
      expect(after.useBilibiliAuthForPlay, isTrue);
    });

    test('a database already at v2 is not folded again', () async {
      await openTestDatabase();

      // 使用者在 v2 之後改了設定，舊欄位仍停在遷移當下的舊值。
      // 再跑一次遷移絕對不可以拿舊欄位覆蓋回去。
      final v2 = Settings()
        ..schemaVersion = 2
        ..bilibiliStreamPriority = 'audioOnly,muxed'
        ..useBilibiliAuthForPlay = false;
      v2.setStreamPriorityFor(SourceIds.bilibili, [StreamType.muxed]);
      v2.setUseAuthForPlay(SourceIds.bilibili, true);
      await isar.writeTxn(() async => isar.settings.put(v2));

      await runDatabaseMigration(isar);

      final after = (await isar.settings.get(0))!;
      expect(after.streamPriorityFor(SourceIds.bilibili), [StreamType.muxed]);
      expect(after.useAuthForPlay(SourceIds.bilibili), isTrue);
    });

    test('stamps the current schema version on a fresh install', () async {
      await openTestDatabase();

      await runDatabaseMigration(isar);

      final settings = await isar.settings.get(0);
      expect(settings!.schemaVersion, kFmpSchemaVersion);
    });

    test('applies the v0 step once and stamps the version', () async {
      await openTestDatabase();

      final legacySettings = Settings()
        ..useNeteaseAuthForPlay = false
        ..neteaseStreamPriority = ''
        ..rememberPlaybackPosition = false
        ..tempPlayRewindSeconds = 0
        ..disabledLyricsSources = '';
      await isar.writeTxn(() async {
        await isar.settings.put(legacySettings);
      });

      await runDatabaseMigration(isar);

      final migrated = await isar.settings.get(0);
      expect(migrated!.schemaVersion, kFmpSchemaVersion);
      expect(migrated.rememberPlaybackPosition, isTrue);
      expect(migrated.tempPlayRewindSeconds, 10);
      expect(migrated.disabledLyricsSources, 'lrclib');
    });

    test('does not re-run the v0 step on a database already past it', () async {
      await openTestDatabase();

      // 一個使用者刻意把設定調成「長得像未遷移」的形狀，但版本號已經是 1。
      // v0 的推斷絕對不可以再碰它 —— 這正是形狀猜測修不掉的那個 bug。
      final modern = Settings()
        ..schemaVersion = 1
        ..useNeteaseAuthForPlay = false
        ..neteaseStreamPriority = ''
        ..rememberPlaybackPosition = false
        ..tempPlayRewindSeconds = 0
        ..disabledLyricsSources = '';
      await isar.writeTxn(() async {
        await isar.settings.put(modern);
      });

      await runDatabaseMigration(isar);

      final after = await isar.settings.get(0);
      expect(after!.schemaVersion, kFmpSchemaVersion);
      expect(after.rememberPlaybackPosition, isFalse);
      expect(after.tempPlayRewindSeconds, 0);
      expect(after.disabledLyricsSources, '');
      expect(after.useAuthForPlay(SourceIds.netease), isFalse);
      // 不變式修復與版本無關，所以空的優先級仍然會被補回預設。
      expect(after.streamPriorityFor(SourceIds.netease), [
        StreamType.audioOnly,
      ]);
    });

    test(
      'repairs legacy queue volume without changing current queue state',
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
      },
    );

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
