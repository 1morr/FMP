// 這個檔案是 `Settings` 上那些 @Deprecated 每源欄位的**唯一**合法讀者：遷移
// 必須讀得到舊值才能把它們折進 `sourceSettings`。其他任何地方讀到它們都會被
// deprecated_member_use_from_same_package 擋下來，那正是我們要的。
// ignore_for_file: deprecated_member_use_from_same_package

import 'dart:io';

import 'package:isar_community/isar.dart';

import '../../core/constants/app_constants.dart';
import '../../core/logger.dart';
import '../../data/models/lyrics_title_parse_cache.dart';
import '../../data/models/play_queue.dart';
import '../../data/models/settings.dart';
import '../../data/models/source_ids.dart';

/// 目前的持久化 schema 版本。每加一個遷移步驟就 +1。
const int kFmpSchemaVersion = 2;

/// 資料庫啟動時的唯一入口：套用未跑過的遷移步驟，再修復與版本無關的不變式。
///
/// 全部在同一個寫入交易裡完成 —— 半套的遷移比沒遷移更難處理。
Future<void> runDatabaseMigration(Isar isar) async {
  await isar.writeTxn(() async {
    final settings = await isar.settings.get(0);

    if (settings == null) {
      // 全新安裝：沒有任何舊資料可推斷，直接蓋上目前版本。
      await isar.settings
          .put(createBootstrapSettings()..schemaVersion = kFmpSchemaVersion);
    } else {
      final currentVersion = effectiveSchemaVersion(settings);
      for (final step in fmpMigrationSteps) {
        if (currentVersion >= step.to) continue;
        step.run(settings);
        settings.schemaVersion = step.to;
        AppLogger.info(
          'Applied schema migration ${step.from} -> ${step.to}: ${step.name}',
          'DatabaseMigration',
        );
      }
      repairSettingsInvariants(settings);
      await isar.settings.put(settings);
    }

    await _ensureHealthyPlayQueue(isar);

    // AI 標題解析快取是單次工作階段的快取，不是耐久資料。
    await isar.lyricsTitleParseCaches.clear();
  });
}

Future<void> _ensureHealthyPlayQueue(Isar isar) async {
  final queues = await isar.playQueues.where().findAll();
  if (queues.isEmpty) {
    await isar.playQueues.put(PlayQueue());
    return;
  }
  for (final queue in queues) {
    if (hasUnwrittenQueueSignature(queue)) {
      queue.lastVolume = 1.0;
      await isar.playQueues.put(queue);
    }
  }
}

/// 全新安裝的 Settings 初值。行動裝置的快取上限比桌面小。
Settings createBootstrapSettings() {
  final settings = Settings();
  if (Platform.isAndroid || Platform.isIOS) {
    settings.maxCacheSizeMB = 16; // 移动端默认 16MB（桌面端保持 32MB）
  }
  return settings;
}

/// 一個具名的遷移步驟。
///
/// 這取代了先前「N 個欄位同時長得像預設值就當作舊資料」的形狀猜測 ——
/// 那種判斷式不可證偽，而且使用者只要剛好把設定調成那個形狀就會被覆蓋回預設。
class NamedMigrationStep {
  const NamedMigrationStep({
    required this.from,
    required this.to,
    required this.name,
    required this.run,
  });

  final int from;
  final int to;
  final String name;
  final void Function(Settings settings) run;
}

const List<NamedMigrationStep> fmpMigrationSteps = <NamedMigrationStep>[
  NamedMigrationStep(
    from: 0,
    to: 1,
    name: 'infer pre-versioning defaults',
    run: _migrateV0ToV1,
  ),
  NamedMigrationStep(
    from: 1,
    to: 2,
    name: 'fold per-source settings into one list',
    run: _migrateV1ToV2,
  ),
];

/// 讀出這一列真正的 schema 版本。
///
/// **Isar 對舊列缺少的非空 `int` 欄位回傳 `Isar.minLong`，不是 0。**
/// 在使用者的真實資料庫上實測過：新增 `schemaVersion` 之後，Phase 3 之前的那一列
/// 讀出來是 `-9223372036854775808`。所以任何負數都代表「這一列還沒有版本號」= v0。
int effectiveSchemaVersion(Settings settings) =>
    settings.schemaVersion < 0 ? 0 : settings.schemaVersion;

/// v0 → v1：把原本每次啟動都重跑的形狀猜測降級成一次性的「推斷 v0」。
///
/// 兩個判斷式的字面內容與 Phase 3 之前完全相同 —— 差別只在它們現在**只跑一次**，
/// 跑完就蓋上版本號。這正好修掉「使用者剛好把設定調成那個形狀就被覆蓋」的 bug。
void _migrateV0ToV1(Settings settings) {
  if (_hasLegacyPlaybackAndLyricsDefaultsSignature(settings)) {
    settings.rememberPlaybackPosition = true;
    settings.tempPlayRewindSeconds = 10;
    settings.disabledLyricsSources = 'lrclib';
  }

  // 網易雲相關欄位：舊版本升級時新增欄位會落成 Isar 型別預設值。
  // 以 neteaseStreamPriority 是否為空判斷這一列是否還沒遷移過。
  // 必須在 repairSettingsInvariants 之前跑，否則那個訊號會先被清掉。
  if (settings.neteaseStreamPriority.isEmpty) {
    settings.useNeteaseAuthForPlay = true;
    settings.neteaseStreamPriority = 'audioOnly';
  }

  // 版面欄位是 Phase 3 新增的，舊列一律讀成 Isar 的預設（bool false、
  // double NaN）。detailPanelExpanded 的業務預設是 true，而 false 在這裡
  // 不可能是使用者的選擇 —— 這一列從來沒有寫過這個欄位。
  settings.railExpanded = false;
  settings.detailPanelExpanded = true;
  settings.detailPanelWidth = 380;
}

/// v1 → v2：把六個每源具名欄位折成一份 `sourceSettings`。
///
/// **只搬不刪。** 舊欄位刻意保留原值，理由有二：
///
/// 1. 遷移是在 `Isar.open(fmpDatabaseSchemas)` **之後**才跑的。欄位一旦從
///    `settings.dart` 刪掉，生成的反序列化器裡就沒有它，這個函式會讀不到，
///    三筆 entry 全部拿到空值 —— 直接的使用者設定遺失。
/// 2. 不清空舊欄位，降級（裝回舊版 APK）時每源設定是**無損**的。若在這裡把
///    它們清成 ''，舊版的預設值修復會把使用者的選擇覆蓋掉。
///
/// 舊欄位在 schema v3 才刪。
void _migrateV1ToV2(Settings settings) {
  settings.sourceSettings = [
    SourceSettingsEntry()
      ..sourceId = SourceIds.bilibili
      ..streamPriority = settings.bilibiliStreamPriority
      ..useAuthForPlay = settings.useBilibiliAuthForPlay,
    SourceSettingsEntry()
      ..sourceId = SourceIds.youtube
      ..streamPriority = settings.youtubeStreamPriority
      ..useAuthForPlay = settings.useYoutubeAuthForPlay,
    SourceSettingsEntry()
      ..sourceId = SourceIds.netease
      ..streamPriority = settings.neteaseStreamPriority
      ..useAuthForPlay = settings.useNeteaseAuthForPlay,
  ];
}

bool _hasLegacyPlaybackAndLyricsDefaultsSignature(Settings settings) {
  return settings.neteaseStreamPriority.isEmpty &&
      !settings.useNeteaseAuthForPlay &&
      !settings.rememberPlaybackPosition &&
      settings.tempPlayRewindSeconds == 0 &&
      settings.disabledLyricsSources.isEmpty;
}

/// 值域夾取與空字串補預設。
///
/// **這不是遷移，不掛版本號。** 它同時要防的是壞掉的備份匯入、降級之後再升級，
/// 以及任何把欄位寫成非法值的路徑，所以每次啟動都要跑。
bool repairSettingsInvariants(Settings settings) {
  var changed = false;

  void fix(bool broken, void Function() repair) {
    if (!broken) return;
    repair();
    changed = true;
  }

  fix(
      settings.maxConcurrentDownloads < 1 ||
          settings.maxConcurrentDownloads > 5,
      () => settings.maxConcurrentDownloads = 3);
  fix(settings.maxCacheSizeMB < 1, () => settings.maxCacheSizeMB = 32);
  fix(
      settings.audioQualityLevelIndex < 0 || settings.audioQualityLevelIndex > 2,
      () => settings.audioQualityLevelIndex = 0);
  fix(
      settings.downloadImageOptionIndex < 0 ||
          settings.downloadImageOptionIndex > 2,
      () => settings.downloadImageOptionIndex = 1);
  fix(
      settings.lyricsDisplayModeIndex < 0 || settings.lyricsDisplayModeIndex > 2,
      () => settings.lyricsDisplayModeIndex = 0);
  fix(settings.maxLyricsCacheFiles < 1, () => settings.maxLyricsCacheFiles = 50);
  fix(
      settings.lyricsAiTimeoutSeconds < 1,
      () => settings.lyricsAiTimeoutSeconds =
          AppConstants.lyricsAiDefaultTimeoutSeconds);
  fix(
      settings.lyricsAiTitleParsingModeIndex == 1 ||
          settings.lyricsAiTitleParsingModeIndex < 0 ||
          settings.lyricsAiTitleParsingModeIndex > 3,
      () => settings.lyricsAiTitleParsingModeIndex = 0);

  fix(settings.audioFormatPriority.isEmpty,
      () => settings.audioFormatPriority = 'opus,aac');
  // 每個內建音源都要有一筆設定，而且串流優先序不能是空字串。
  // 這是不變式不是遷移：它也要擋下壞掉的備份匯入與降級後的往返。
  for (final sourceId in SourceIds.values) {
    final stored = settings.sourceSettings
        .where((entry) => entry.sourceId == sourceId)
        .firstOrNull;
    fix(
      stored == null || stored.streamPriority.trim().isEmpty,
      () => settings.setStreamPriorityFor(
        sourceId,
        settings.streamPriorityFor(sourceId),
      ),
    );
  }
  fix(settings.lyricsSourcePriority.isEmpty,
      () => settings.lyricsSourcePriority = 'netease,qqmusic,lrclib');

  fix(settings.rankingRefreshIntervalMinutes < 1,
      () => settings.rankingRefreshIntervalMinutes = 60);
  fix(settings.homeRankingSourcePriority.isEmpty,
      () => settings.homeRankingSourcePriority = defaultHomeRankingSourcePriority);

  final normalizedPriority = settings.homeRankingSourcePriorityList.join(',');
  fix(settings.homeRankingSourcePriority != normalizedPriority,
      () => settings.homeRankingSourcePriority = normalizedPriority);

  final normalizedDisabled = settings.disabledHomeRankingSourcesSet.join(',');
  fix(settings.disabledHomeRankingSources != normalizedDisabled,
      () => settings.disabledHomeRankingSources = normalizedDisabled);

  fix(settings.radioRefreshIntervalMinutes < 1,
      () => settings.radioRefreshIntervalMinutes = 5);

  // 版面欄位：Isar 給舊列的 double 是 NaN、bool 是 false，兩者都不是業務預設。
  // detailPanelExpanded 的 false 無法與「使用者真的收起了」區分，所以只在
  // 整列還沒有版本號時才救 —— 那是 v0 步驟的事，這裡只擋掉不合法的寬度。
  fix(
      !settings.detailPanelWidth.isFinite ||
          settings.detailPanelWidth < 280 ||
          settings.detailPanelWidth > 500,
      () => settings.detailPanelWidth = 380);

  return changed;
}

/// 整列都是型別預設值的佇列 —— 那是「這一列從來沒被寫過」，不是使用者把音量調成 0。
///
/// 這條也**不是**遷移：它與版本無關，而且
/// `database_migration_test.dart` 有一條測試在沒有 Settings 列的情況下
/// （也就是全新安裝的快速路徑）就期望它生效。
bool hasUnwrittenQueueSignature(PlayQueue queue) {
  return queue.lastVolume == 0 &&
      queue.trackIds.isEmpty &&
      queue.currentIndex == 0 &&
      queue.lastPositionMs == 0 &&
      !queue.isShuffleEnabled &&
      queue.loopMode == LoopMode.none &&
      queue.originalOrder == null &&
      queue.lastUpdated == null &&
      !queue.isMixMode &&
      queue.mixPlaylistId == null &&
      queue.mixSeedVideoId == null &&
      queue.mixTitle == null;
}
