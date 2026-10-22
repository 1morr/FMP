import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/legacy_import/legacy_settings_migration.dart';
import 'package:fmp/legacy_import/legacy_snapshot.dart';

import '../support/legacy_database.dart' show legacyNullLong;

/// 舊 migration 0→4 與 `repairSettingsInvariants` 的補做。期望值是照舊版
/// `lib/data/database/database_migration.dart` 逐步推演的結果（舊專案凍結，
/// 沒有辦法在這裡直接跑它）。
void main() {
  List<String> summary(List<LegacySourceSettings> entries) => [
    for (final e in entries)
      '${e.sourceId}|${e.streamPriority}|${e.useAuthForPlay}',
  ];

  /// 一個還沒有任何新欄位的舊列：Isar 對缺欄補型別預設。
  LegacySettings rawV0() => LegacySettings(
    schemaVersion: legacyNullLong,
    neteaseStreamPriority: '',
    useNeteaseAuthForPlay: false,
    rememberPlaybackPosition: false,
    tempPlayRewindSeconds: 0,
    disabledLyricsSources: '',
    youtubeStreamPriority: '',
    bilibiliStreamPriority: '',
    detailPanelWidth: double.nan,
    maxCacheSizeMB: legacyNullLong,
    playHistoryLimit: legacyNullLong,
    maxConcurrentDownloads: legacyNullLong,
    audioQualityLevelIndex: legacyNullLong,
    downloadImageOptionIndex: legacyNullLong,
    lyricsDisplayModeIndex: legacyNullLong,
    maxLyricsCacheFiles: legacyNullLong,
    lyricsAiTimeoutSeconds: legacyNullLong,
    lyricsAiTitleParsingModeIndex: legacyNullLong,
    audioFormatPriority: '',
    lyricsSourcePriority: '',
    rankingRefreshIntervalMinutes: legacyNullLong,
    homeRankingSourcePriority: '',
    radioRefreshIntervalMinutes: legacyNullLong,
  );

  test('a row with no version column is treated as v0', () {
    expect(effectiveLegacySchemaVersion(legacyNullLong), 0);
    expect(effectiveLegacySchemaVersion(0), 0);
    expect(effectiveLegacySchemaVersion(3), 3);
  });

  test('v0 runs every step and the repairs', () {
    final settings = rawV0();
    replayLegacySettingsMigration(settings);

    expect(settings.schemaVersion, 4);
    // 0→1：預設形狀的推斷、網易雲欄位、版面欄位。
    expect(settings.rememberPlaybackPosition, isTrue);
    expect(settings.tempPlayRewindSeconds, 10);
    expect(settings.disabledLyricsSources, 'lrclib');
    expect(settings.neteaseStreamPriority, 'audioOnly');
    expect(settings.useNeteaseAuthForPlay, isTrue);
    expect(settings.railExpanded, isFalse);
    expect(settings.detailPanelExpanded, isTrue);
    expect(settings.detailPanelWidth, 380);
    // 1→2 與 3→4 與 repair：每源設定；每次寫入的項目接在最後。
    expect(summary(settings.sourceSettings), [
      'netease|audioOnly|true',
      'bilibili|audioOnly,muxed|true',
      'youtube|audioOnly,muxed,hls|false',
    ]);
    // repair：型別預設的 int 與空字串補回預設。
    expect(settings.maxCacheSizeMB, 32);
    expect(settings.playHistoryLimit, 10000);
    expect(settings.maxConcurrentDownloads, 3);
    expect(settings.audioQualityLevelIndex, 0);
    expect(settings.downloadImageOptionIndex, 1);
    expect(settings.lyricsDisplayModeIndex, 0);
    expect(settings.maxLyricsCacheFiles, 50);
    expect(settings.lyricsAiTimeoutSeconds, 20);
    expect(settings.lyricsAiTitleParsingModeIndex, 0);
    expect(settings.audioFormatPriority, 'opus,aac');
    expect(settings.lyricsSourcePriority, 'netease,qqmusic,lrclib');
    expect(settings.rankingRefreshIntervalMinutes, 60);
    expect(settings.homeRankingSourcePriority, 'bilibili,youtube,netease');
    expect(settings.radioRefreshIntervalMinutes, 5);
  });

  test(
    'v0 keeps what a user already set when the defaults shape is absent',
    () {
      final settings = rawV0()
        ..rememberPlaybackPosition = true
        ..tempPlayRewindSeconds = 15
        ..disabledLyricsSources = 'netease';
      replayLegacySettingsMigration(settings);

      // 預設形狀的條件不成立：這三個不被推斷覆蓋。
      expect(settings.tempPlayRewindSeconds, 15);
      expect(settings.disabledLyricsSources, 'netease');
      // 網易雲欄位與版面欄位的救援照樣跑（它們各有自己的條件）。
      expect(settings.neteaseStreamPriority, 'audioOnly');
      expect(settings.detailPanelWidth, 380);
    },
  );

  test('v1 folds the per-source fields and turns Bilibili auth on', () {
    final settings = LegacySettings(
      schemaVersion: 1,
      bilibiliStreamPriority: 'muxed,audioOnly',
      useBilibiliAuthForPlay: false,
      youtubeStreamPriority: 'audioOnly,hls',
      useYoutubeAuthForPlay: true,
      neteaseStreamPriority: 'audioOnly',
      useNeteaseAuthForPlay: false,
      // 1 之後的版面欄位屬於使用者，不被 v0 的救援碰。
      railExpanded: true,
      detailPanelExpanded: false,
      detailPanelWidth: 500,
      tempPlayRewindSeconds: 0,
      rememberPlaybackPosition: false,
    );
    replayLegacySettingsMigration(settings);

    expect(settings.schemaVersion, 4);
    expect(summary(settings.sourceSettings), [
      'youtube|audioOnly,hls|true',
      'netease|audioOnly|false',
      'bilibili|muxed,audioOnly|true',
    ]);
    expect(settings.railExpanded, isTrue);
    expect(settings.detailPanelExpanded, isFalse);
    expect(settings.detailPanelWidth, 500);
    expect(settings.tempPlayRewindSeconds, 0);
    expect(settings.rememberPlaybackPosition, isFalse);
  });

  test('v3 only turns Bilibili auth on and leaves the rest alone', () {
    final settings = LegacySettings(
      schemaVersion: 3,
      sourceSettings: [
        const LegacySourceSettings(
          sourceId: 'bilibili',
          streamPriority: 'audioOnly',
          useAuthForPlay: false,
        ),
        const LegacySourceSettings(
          sourceId: 'youtube',
          streamPriority: 'audioOnly,muxed,hls',
          useAuthForPlay: false,
        ),
        const LegacySourceSettings(
          sourceId: 'netease',
          streamPriority: 'audioOnly',
          useAuthForPlay: false,
        ),
      ],
      rememberPlaybackPosition: false,
      detailPanelWidth: 500,
      maxCacheSizeMB: 64,
    );
    replayLegacySettingsMigration(settings);

    expect(settings.schemaVersion, 4);
    expect(summary(settings.sourceSettings), [
      'youtube|audioOnly,muxed,hls|false',
      'netease|audioOnly|false',
      'bilibili|audioOnly|true',
    ]);
    expect(settings.rememberPlaybackPosition, isFalse);
    expect(settings.detailPanelWidth, 500);
    expect(settings.maxCacheSizeMB, 64);
  });

  test('repair clamps an out-of-range panel width instead of resetting it', () {
    final settings = LegacySettings(schemaVersion: 3, detailPanelWidth: 300);
    replayLegacySettingsMigration(settings);
    expect(settings.detailPanelWidth, 320);

    final wide = LegacySettings(schemaVersion: 3, detailPanelWidth: 5000);
    replayLegacySettingsMigration(wide);
    expect(wide.detailPanelWidth, 1600);
  });

  test('repair normalizes the ranking source lists', () {
    final settings = LegacySettings(
      schemaVersion: 3,
      homeRankingSourcePriority: 'netease,unknown,netease',
      // 全部停用不合法，整串清空。
      disabledHomeRankingSources: 'bilibili,youtube,netease',
    );
    replayLegacySettingsMigration(settings);
    expect(settings.homeRankingSourcePriority, 'netease,bilibili,youtube');
    expect(settings.disabledHomeRankingSources, '');
  });

  test('a radio refresh interval of 0 means off and stays', () {
    final settings = LegacySettings(
      schemaVersion: 3,
      radioRefreshIntervalMinutes: 0,
    );
    replayLegacySettingsMigration(settings);
    expect(settings.radioRefreshIntervalMinutes, 0);
  });
}
