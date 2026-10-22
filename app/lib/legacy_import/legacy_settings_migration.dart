import 'legacy_snapshot.dart';

/// 舊版啟動時會把設定升到這個 schema 版本；`schemaVersion = 4` 的庫已經是修好的值。
const int legacySettingsSchemaVersion = 4;

/// 設定列的有效 schema 版本：缺欄的非空 `int` 讀出來是 `-2^63`（舊版稱 minLong，負數），
/// 代表這一列還沒有版本號，即 v0。
int effectiveLegacySchemaVersion(int stored) => stored < 0 ? 0 : stored;

/// 在 [settings] 上補做舊版的 migration 0→4 與 `repairSettingsInvariants`。
///
/// 照舊版 `lib/data/database/database_migration.dart` 逐步移植，只改傳進來的
/// 物件（就地），不碰檔案。舊 App 每次啟動都會做這些，所以新版讀到的庫只在
/// `schemaVersion < 4`（從更早的版本直接跳來）時需要補：否則 1→2 沒跑時
/// `sourceSettings` 是空的、缺欄的 bool 讀成 false 會被當成「使用者關掉」。
///
/// 舊版是 isar 的一個寫入交易裡做；這裡沒有資料庫，結果相同。
void replayLegacySettingsMigration(LegacySettings settings) {
  final version = effectiveLegacySchemaVersion(settings.schemaVersion);
  for (final step in _steps) {
    if (version >= step.to) continue;
    step.run(settings);
    settings.schemaVersion = step.to;
  }
  _repairSettingsInvariants(settings);
}

typedef _Step = ({int to, void Function(LegacySettings settings) run});

const List<_Step> _steps = [
  (to: 1, run: _migrateV0ToV1),
  (to: 2, run: _migrateV1ToV2),
  (to: 3, run: _migrateV2ToV3),
  (to: 4, run: _migrateV3ToV4),
];

// 舊版 `SourceIds.values` 的順序與各音源的預設。
const _bilibili = 'bilibili';
const _youtube = 'youtube';
const _netease = 'netease';
const _sourceIds = [_bilibili, _youtube, _netease];

const _defaultStreamPriorityBySource = {
  _bilibili: 'audioOnly,muxed',
  _youtube: 'audioOnly,muxed,hls',
  _netease: 'audioOnly',
};
const _fallbackStreamPriority = 'audioOnly,muxed';
const _defaultUseAuthForPlayBySource = {_bilibili: true, _netease: true};

const _streamTypes = ['audioOnly', 'muxed', 'hls'];

/// v0 → v1：把每次啟動重跑的形狀猜測降級成一次性的「推斷 v0」。
void _migrateV0ToV1(LegacySettings settings) {
  if (_hasLegacyPlaybackAndLyricsDefaultsSignature(settings)) {
    settings.rememberPlaybackPosition = true;
    settings.tempPlayRewindSeconds = 10;
    settings.disabledLyricsSources = 'lrclib';
  }

  // 網易雲欄位是後來才加的：以 neteaseStreamPriority 是否為空判斷還沒遷移過。
  // 必須在 repair 之前跑，否則那個訊號會先被清掉。
  if (settings.neteaseStreamPriority.isEmpty) {
    settings.useNeteaseAuthForPlay = true;
    settings.neteaseStreamPriority = 'audioOnly';
  }

  // 版面欄位是後來才加的，舊列讀成型別預設（bool false、double NaN）。
  settings.railExpanded = false;
  settings.detailPanelExpanded = true;
  settings.detailPanelWidth = 380;
}

bool _hasLegacyPlaybackAndLyricsDefaultsSignature(LegacySettings settings) {
  return settings.neteaseStreamPriority.isEmpty &&
      !settings.useNeteaseAuthForPlay &&
      !settings.rememberPlaybackPosition &&
      settings.tempPlayRewindSeconds == 0 &&
      settings.disabledLyricsSources.isEmpty;
}

/// v1 → v2：六個每源欄位折成一份 `sourceSettings`（只搬不刪）。
void _migrateV1ToV2(LegacySettings settings) {
  settings.sourceSettings = [
    LegacySourceSettings(
      sourceId: _bilibili,
      streamPriority: settings.bilibiliStreamPriority,
      useAuthForPlay: settings.useBilibiliAuthForPlay,
    ),
    LegacySourceSettings(
      sourceId: _youtube,
      streamPriority: settings.youtubeStreamPriority,
      useAuthForPlay: settings.useYoutubeAuthForPlay,
    ),
    LegacySourceSettings(
      sourceId: _netease,
      streamPriority: settings.neteaseStreamPriority,
      useAuthForPlay: settings.useNeteaseAuthForPlay,
    ),
  ];
}

/// v2 → v3：舊版把 `autoCheckUpdates` 打開，那個欄位早已刪除，沒有內容。
void _migrateV2ToV3(LegacySettings settings) {}

/// v3 → v4：Bilibili 的 `useAuthForPlay` 一律打開。
void _migrateV3ToV4(LegacySettings settings) {
  _putEntry(settings, _entryFor(settings, _bilibili, useAuthForPlay: true));
}

LegacySourceSettings _entryFor(
  LegacySettings settings,
  String sourceId, {
  String? streamPriority,
  bool? useAuthForPlay,
}) {
  final stored = settings.sourceSettings
      .where((entry) => entry.sourceId == sourceId)
      .firstOrNull;
  return LegacySourceSettings(
    sourceId: sourceId,
    streamPriority:
        streamPriority ??
        stored?.streamPriority ??
        _defaultStreamPriorityBySource[sourceId] ??
        _fallbackStreamPriority,
    useAuthForPlay:
        useAuthForPlay ??
        stored?.useAuthForPlay ??
        _defaultUseAuthForPlayBySource[sourceId] ??
        false,
  );
}

/// 舊版 `_putEntry`：其他音源的項目照舊順序在前，這一項接在最後。
void _putEntry(LegacySettings settings, LegacySourceSettings entry) {
  settings.sourceSettings = [
    for (final existing in settings.sourceSettings)
      if (existing.sourceId != entry.sourceId) existing,
    entry,
  ];
}

/// 舊版 `parseStreamPriority`：認不得的 token 丟掉，不重複。
List<String> _parseStreamPriority(String value) {
  final result = <String>[];
  for (final raw in value.split(',')) {
    final token = raw.trim();
    if (_streamTypes.contains(token) && !result.contains(token)) {
      result.add(token);
    }
  }
  return result;
}

List<String> _streamPriorityFor(LegacySettings settings, String sourceId) {
  final parsed = _parseStreamPriority(
    _entryFor(settings, sourceId).streamPriority,
  );
  if (parsed.isNotEmpty) return parsed;
  return _parseStreamPriority(
    _defaultStreamPriorityBySource[sourceId] ?? _fallbackStreamPriority,
  );
}

List<String> _normalizeHomeRankingSourcePriority(String value) {
  final seen = <String>{};
  final normalized = <String>[];
  for (final raw in value.split(',')) {
    final source = raw.trim();
    if (!_sourceIds.contains(source) || !seen.add(source)) continue;
    normalized.add(source);
  }
  for (final source in _sourceIds) {
    if (seen.add(source)) normalized.add(source);
  }
  return normalized;
}

Set<String> _normalizeDisabledHomeRankingSources(String value) {
  if (value.isEmpty) return <String>{};
  final disabled = value
      .split(',')
      .map((s) => s.trim())
      .where(_sourceIds.contains)
      .toSet();
  if (disabled.length >= _sourceIds.length) return <String>{};
  return disabled;
}

// 舊版 `AppLayout` 的詳情面板寬度常數。
const double _detailPanelDefault = 412.0;
const double _detailPanelMin = 320.0;
const double _detailPanelStoredMax = 1600.0;

/// 值域夾取與空字串補預設（舊版 `repairSettingsInvariants`，不掛版本號）。
void _repairSettingsInvariants(LegacySettings settings) {
  if (settings.maxConcurrentDownloads < 1 ||
      settings.maxConcurrentDownloads > 5) {
    settings.maxConcurrentDownloads = 3;
  }
  if (settings.maxCacheSizeMB < 1) settings.maxCacheSizeMB = 32;
  if (settings.audioQualityLevelIndex < 0 ||
      settings.audioQualityLevelIndex > 2) {
    settings.audioQualityLevelIndex = 0;
  }
  if (settings.downloadImageOptionIndex < 0 ||
      settings.downloadImageOptionIndex > 2) {
    settings.downloadImageOptionIndex = 1;
  }
  if (settings.lyricsDisplayModeIndex < 0 ||
      settings.lyricsDisplayModeIndex > 2) {
    settings.lyricsDisplayModeIndex = 0;
  }
  if (settings.maxLyricsCacheFiles < 1) settings.maxLyricsCacheFiles = 50;
  if (settings.playHistoryLimit < 1) settings.playHistoryLimit = 10000;
  if (settings.lyricsAiTimeoutSeconds < 1) settings.lyricsAiTimeoutSeconds = 20;
  if (settings.lyricsAiTitleParsingModeIndex == 1 ||
      settings.lyricsAiTitleParsingModeIndex < 0 ||
      settings.lyricsAiTitleParsingModeIndex > 3) {
    settings.lyricsAiTitleParsingModeIndex = 0;
  }

  if (settings.audioFormatPriority.isEmpty) {
    settings.audioFormatPriority = 'opus,aac';
  }
  // 每個內建音源都要有一筆設定，而且串流優先序不能是空字串。
  for (final sourceId in _sourceIds) {
    final stored = settings.sourceSettings
        .where((entry) => entry.sourceId == sourceId)
        .firstOrNull;
    if (stored == null || stored.streamPriority.trim().isEmpty) {
      _putEntry(
        settings,
        _entryFor(
          settings,
          sourceId,
          streamPriority: _streamPriorityFor(settings, sourceId).join(','),
        ),
      );
    }
  }
  if (settings.lyricsSourcePriority.isEmpty) {
    settings.lyricsSourcePriority = 'netease,qqmusic,lrclib';
  }

  if (settings.rankingRefreshIntervalMinutes < 1) {
    settings.rankingRefreshIntervalMinutes = 60;
  }
  if (settings.homeRankingSourcePriority.isEmpty) {
    settings.homeRankingSourcePriority = 'bilibili,youtube,netease';
  }
  final normalizedPriority = _normalizeHomeRankingSourcePriority(
    settings.homeRankingSourcePriority,
  ).join(',');
  if (settings.homeRankingSourcePriority != normalizedPriority) {
    settings.homeRankingSourcePriority = normalizedPriority;
  }
  final normalizedDisabled = _normalizeDisabledHomeRankingSources(
    settings.disabledHomeRankingSources,
  ).join(',');
  if (settings.disabledHomeRankingSources != normalizedDisabled) {
    settings.disabledHomeRankingSources = normalizedDisabled;
  }

  // 0 是「關閉」，不是壞值。
  if (settings.radioRefreshIntervalMinutes < 0) {
    settings.radioRefreshIntervalMinutes = 5;
  }

  // 版面寬度：不是有限值就重設，越界的夾到邊界。
  final width = settings.detailPanelWidth;
  if (!width.isFinite) {
    settings.detailPanelWidth = _detailPanelDefault;
  } else if (width < _detailPanelMin || width > _detailPanelStoredMax) {
    settings.detailPanelWidth = width.clamp(
      _detailPanelMin,
      _detailPanelStoredMax,
    );
  }
}
