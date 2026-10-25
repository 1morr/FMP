import 'dart:ui' show Color;

import 'package:fmp/data/repositories/appearance_settings_repository.dart';
import 'package:fmp/data/repositories/layout_state_repository.dart';
import 'package:fmp/data/repositories/network_settings_repository.dart';
import 'package:fmp/data/repositories/playback_settings_repository.dart';
import 'package:fmp/domain/appearance.dart';
import 'package:fmp/domain/legacy_import.dart';
import 'package:fmp/domain/stream_preferences.dart';
import 'package:fmp/legacy_import/legacy_snapshot.dart';
import 'package:fmp/legacy_import/legacy_source_ids.dart';
import 'package:fmp/legacy_import/legacy_track_catalog.dart';
import 'package:fmp/legacy_import/play_history_limit.dart';
import 'package:fmp/settings/network_settings.dart';
import 'package:fmp/settings/playback_settings.dart';

// 舊 `Settings` → 新版的設定組（M5 design §5.9、§1.3）。純函式，不改 [LegacySettings]。
//
// 通則：只寫使用者在舊版改過的值，也就是不等於舊版預設的值（預設是舊專案
// `lib/data/models/settings.dart` 的欄位初始值，行號寫在各常數旁）；等於舊預設、或不在合法值域
// （Isar 對缺欄補的 `minLong`、NaN、不認得的字串）的，新版欄位留空，新版自己的預設生效
// （ADR 0011：空＝沒設定過）。不在新版選項裡的數值取最接近的選項，等距取大的。

/// `ImportSummary.unimportedSettings` 的識別字（結果對話框依它查翻譯）；只有使用者改過的才列。
abstract final class UnimportedSetting {
  static const streamPriority = 'streamPriority';
  static const cacheLimit = 'cacheLimit';
  static const homeRanking = 'homeRanking';
  static const searchHistory = 'searchHistory';
}

/// 設定段的結果，由轉換器併進匯入包與摘要。
final class ConvertedSettings {
  const ConvertedSettings({
    this.appearance = AppearanceSettings.empty,
    this.network = NetworkSettings.empty,
    this.playback = PlaybackSettings.empty,
    this.browseAsLoggedIn = const {},
    this.layout = LayoutState.empty,
    this.unimported = const [],
  });

  static const empty = ConvertedSettings();

  final AppearanceSettings appearance;
  final NetworkSettings network;
  final PlaybackSettings playback;
  final Map<String, bool> browseAsLoggedIn;
  final LayoutState layout;
  final List<String> unimported;
}

// 舊預設（舊專案 `lib/data/models/settings.dart`）。
const _defaultAudioQualityIndex = 0; // :309
const _defaultRememberPosition = true; // :259
const _defaultTempPlayRewindSeconds = 10; // :265
const _defaultRestartRewindSeconds = 0; // :262
const _defaultAutoScroll = false; // :256
const _defaultRadioRefreshMinutes = 5; // :443
const _defaultRankingRefreshMinutes = 60; // :434
/// 快取上限（MB）的歷代預設，都算沒改過：2048 → 128 → 32（舊專案 git 歷史：`c51a95f9`、`b8ed9699`，
/// 現值 :247），行動裝置全新安裝的初值 16（`createBootstrapSettings`，`database_migration.dart:109`）。
const _historicalMaxCacheSizeMB = {2048, 128, 32, 16};
const _defaultMaxLyricsCacheFiles = 50; // :350
const _defaultHomeRankingPriority = 'bilibili,youtube,netease'; // :172

/// 各音源的預設串流優先序（`kDefaultStreamPriorityBySource`，:59-63）與沒有專屬預設時的
/// （`kFallbackStreamPriority`，:68）。
const _defaultStreamPriority = {
  legacyBilibili: 'audioOnly,muxed',
  legacyYoutube: 'audioOnly,muxed,hls',
  legacyNetease: 'audioOnly',
};
const _fallbackStreamPriority = 'audioOnly,muxed';

/// 各音源「播放帶登入」的預設（`kDefaultUseAuthForPlayBySource`，:76-79）；沒列的是關。
const _defaultUseAuth = {legacyBilibili: true, legacyNetease: true};

/// 面板寬度的資料庫上限（`layout_state.panel_width` 的 CHECK）。
const _maxPanelWidth = 1600.0;

/// 把 [snapshot] 的設定列轉成新版的設定。[fontChoices] 是目前平台外觀設定可選的字型：舊字型不在裡面
/// 就留空（系統預設），轉換器不判斷平台。[importOutputDevice] 由呼叫端依平台給（只有 Windows 的新版
/// 有輸出裝置選擇）；[source] 不是資料庫時不寫版面（備份檔不帶版面，design §5.9）。
ConvertedSettings convertLegacySettings(
  LegacySnapshot snapshot, {
  required LegacyImportSource source,
  required bool importOutputDevice,
  required List<String> fontChoices,
}) {
  if (snapshot.settings.isEmpty) return ConvertedSettings.empty;
  final s = snapshot.settings.first;

  // 主題預設 0（跟隨系統，:224）；0、型別預設與不認得的值都不寫。
  final themeMode = switch (s.themeModeIndex) {
    1 => ThemeModeSetting.light,
    2 => ThemeModeSetting.dark,
    _ => null,
  };
  // 語言預設 null（跟隨系統，:304）。
  final locale = switch (s.locale) {
    'zh_TW' => LocaleSetting.zhTw,
    'zh_CN' => LocaleSetting.zhCn,
    'en' => LocaleSetting.en,
    _ => null,
  };

  // 主題色預設是紫（`defaultThemePrimaryColor`）；null 與預設都不寫。舊版存的是 ARGB 整數，
  // 取低 24 位當不透明的 seed。
  final primary = s.primaryColor;
  final seedColor = primary == null || primary < 0 || primary > 0xFFFFFFFF
      ? null
      : Color(0xFF000000 | (primary & 0xFFFFFF));
  // 字型預設 null（系統預設）；不在新平台清單的退回預設。
  final font = blankToNull(s.fontFamily);
  final fontFamily = font != null && fontChoices.contains(font) ? font : null;

  final quality = s.audioQualityLevelIndex == _defaultAudioQualityIndex
      ? null
      : switch (s.audioQualityLevelIndex) {
          1 => AudioQuality.medium,
          2 => AudioQuality.low,
          _ => null,
        };
  final formatPriority = switch (s.audioFormatPriority) {
    'aac,opus' => AudioFormatPriority.aacFirst,
    _ => null, // 預設 `opus,aac`（:313）與不認得的字串
  };

  final deviceId = importOutputDevice
      ? blankToNull(s.preferredAudioDeviceId)
      : null;

  final playback = PlaybackSettings(
    audioQuality: quality,
    audioFormatPriority: formatPriority,
    rememberPosition: s.rememberPlaybackPosition == _defaultRememberPosition
        ? null
        : s.rememberPlaybackPosition,
    tempPlayRewindSeconds: _nearestChanged(
      s.tempPlayRewindSeconds,
      _defaultTempPlayRewindSeconds,
      tempPlayRewindOptionsSeconds,
    ),
    restartRewindSeconds: _nearestChanged(
      s.restartRewindSeconds,
      _defaultRestartRewindSeconds,
      restartRewindOptionsSeconds,
    ),
    playHistoryLimit: convertPlayHistoryLimit(s.playHistoryLimit),
    autoScrollToCurrent: s.autoScrollToCurrentTrack == _defaultAutoScroll
        ? null
        : s.autoScrollToCurrentTrack,
    outputDeviceId: deviceId,
    outputDeviceName: deviceId == null
        ? null
        : blankToNull(s.preferredAudioDeviceName),
  );

  // `cacheLimitMebibytes` 一律留空（ADR 0016 §決定 3）。
  final network = NetworkSettings(
    radioStatusIntervalMinutes: _nearestChanged(
      s.radioRefreshIntervalMinutes,
      _defaultRadioRefreshMinutes,
      radioStatusIntervalOptionsMinutes,
    ),
    chartRefreshIntervalMinutes: _nearestChanged(
      s.rankingRefreshIntervalMinutes,
      _defaultRankingRefreshMinutes,
      chartRefreshIntervalOptionsMinutes,
    ),
  );

  // 三個音源都照舊值寫：舊預設（B 站、網易開，YouTube 關）與新版預設（都開）不同，等於舊預設
  // 也要寫。沒有那個音源的列時，舊版用該音源的預設（`_entryFor`，:684-692）。
  final browse = <String, bool>{
    for (final id in legacySourceIds)
      id: _entryOf(s, id)?.useAuthForPlay ?? (_defaultUseAuth[id] ?? false),
  };

  // `layout_state` 是上次的狀態、不是設定組：照舊值寫，不論是否等於舊預設。使用者主動收起面板存的是
  // false（剛好等於舊預設），只寫改過的值會把它的選擇換成新版的預設（展開），違反 ADR 0010 §決定 3。
  // 只有不合法的值（型別預設、NaN、≤0）留空。
  // 側欄的展開狀態兩種來源都有（ADR 0035 §決定 12）；面板的欄位只有資料庫來源。
  final width = s.detailPanelWidth;
  final fromDatabase = source == LegacyImportSource.database;
  final layout = LayoutState(
    panelExpanded: fromDatabase ? s.detailPanelExpanded : null,
    panelWidth: fromDatabase && width.isFinite && width > 0
        ? width.clamp(0, _maxPanelWidth).toDouble()
        : null,
    railExpanded: s.railExpanded,
  );

  return ConvertedSettings(
    appearance: AppearanceSettings(
      themeMode: themeMode,
      locale: locale,
      seedColor: seedColor == appSeedColor ? null : seedColor,
      fontFamily: fontFamily,
    ),
    network: network,
    playback: playback,
    browseAsLoggedIn: browse,
    layout: layout,
    unimported: _unimported(snapshot, s),
  );
}

LegacySourceSettings? _entryOf(LegacySettings s, String sourceId) {
  for (final entry in s.sourceSettings) {
    if (entry.sourceId == sourceId) return entry;
  }
  return null;
}

/// 舊值（合法值域：不小於零）與舊預設不同時，取 [options] 裡最接近的（等距取大的）；否則 `null`。
int? _nearestChanged(int legacy, int legacyDefault, List<int> options) {
  if (legacy < 0 || legacy == legacyDefault) return null;
  var best = options.first;
  for (final option in options) {
    final diff = (option - legacy).abs();
    final bestDiff = (best - legacy).abs();
    if (diff < bestDiff || (diff == bestDiff && option > best)) best = option;
  }
  return best;
}

/// 舊版有、新版沒有落腳處，而且使用者改過的設定。
List<String> _unimported(LegacySnapshot snapshot, LegacySettings s) => [
  if (s.sourceSettings.any(_streamPriorityChanged))
    UnimportedSetting.streamPriority,
  if ((s.maxCacheSizeMB > 0 &&
          !_historicalMaxCacheSizeMB.contains(s.maxCacheSizeMB)) ||
      (s.maxLyricsCacheFiles > 0 &&
          s.maxLyricsCacheFiles != _defaultMaxLyricsCacheFiles))
    UnimportedSetting.cacheLimit,
  if ((blankToNull(s.homeRankingSourcePriority) != null &&
          s.homeRankingSourcePriority != _defaultHomeRankingPriority) ||
      s.disabledHomeRankingSources.trim().isNotEmpty)
    UnimportedSetting.homeRanking,
  if (snapshot.searchHistory.isNotEmpty) UnimportedSetting.searchHistory,
];

bool _streamPriorityChanged(LegacySourceSettings entry) {
  if (entry.streamPriority.trim().isEmpty) return false; // 空＝用預設
  final fallback =
      _defaultStreamPriority[entry.sourceId] ?? _fallbackStreamPriority;
  return entry.streamPriority != fallback;
}
