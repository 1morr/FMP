import 'dart:convert';
import 'dart:typed_data';

import 'package:fmp/domain/legacy_import.dart';
import 'package:fmp/legacy_import/legacy_snapshot.dart';
import 'package:fmp/legacy_import/legacy_source_ids.dart';

/// 舊版匯出的 JSON 備份檔（`fmp_backup_*.json`）→ [LegacySnapshot]（M5 design §4.2）。
///
/// 格式與讀法以舊專案凍結的 `lib/services/backup/backup_data.dart`（`BackupData.fromJson`、
/// `SettingsBackup.fromJson`、`_readSourceSettings`）與 `backup_service.dart`（`kBackupVersion`、
/// `validateBackupData`）為準；版本史見 `research/legacy-sources.md` §4.2。
///
/// - 版本 1–5；`version` 缺少當 1，比 5 新的拒絕（舊版自己也擋）。**不沿用資料庫的「看
///   `schemaVersion` 決定補不補舊 migration」**：備份有自己的版本語意，而且同一個版本號的檔案
///   欄位集合可能不同（沒升版就加的鍵），所以逐鍵容錯、缺鍵一律走舊版 `fromJson` 的預設，
///   設定列的 `schemaVersion` 直接是 4（沒有要補做的 migration）。
/// - 時間是沒有時區的本機時間字串，`DateTime.parse` 以匯入裝置的本機時區解讀（與舊版相同）。
/// - v3 以前沒有 `sourceSettings`，六個每源具名鍵折疊成三筆（`_readSourceSettings`）。
/// - 備份沒有佇列、帳號、憑證、下載：這些在 snapshot 裡是空的。曲目以 `trackKeys`
///   （`TrackKey` 字面）被歌單參照；找不到曲目的項目帶一個不存在的 `Track.id`，由轉換器算成
///   `danglingTrackId` 並計數。
/// - 曲目、歌單、歷史、電台等沒有舊 `id`：以在檔案裡的位置編號（從 1 起）。
///
/// 必要欄位缺少或型別不對拒絕整份（舊版也是整份失敗）；選用欄位型別不對當成沒有。
/// [read] 不碰任何檔案，也不記錄檔案內容。
final class LegacyBackupReader {
  const LegacyBackupReader();

  /// 舊版最後支援的備份格式版本（`kBackupVersion`）。
  static const supportedVersion = 5;

  /// 解析 [bytes]。不能匯入時拋 [LegacyBackupRejected]。
  ({LegacySnapshot snapshot, int version}) read(Uint8List bytes) {
    final Object? decoded;
    try {
      var text = utf8.decode(bytes);
      if (text.startsWith('\uFEFF')) text = text.substring(1);
      decoded = jsonDecode(text);
    } on FormatException {
      throw const LegacyBackupRejected(LegacyBackupRejection.notBackup);
    }
    if (decoded is! Map<String, dynamic> ||
        !_topLevelKeys.any(decoded.containsKey)) {
      throw const LegacyBackupRejected(LegacyBackupRejection.notBackup);
    }
    final version = _int(decoded['version']) ?? 1;
    if (version > supportedVersion) {
      throw const LegacyBackupRejected(LegacyBackupRejection.newerVersion);
    }
    try {
      final snapshot = _snapshot(decoded);
      if (snapshot.tracks.isEmpty &&
          snapshot.playlists.isEmpty &&
          snapshot.playHistory.isEmpty &&
          snapshot.searchHistory.isEmpty &&
          snapshot.radioStations.isEmpty &&
          snapshot.lyricsMatches.isEmpty &&
          snapshot.settings.isEmpty) {
        throw const LegacyBackupRejected(LegacyBackupRejection.empty);
      }
      return (snapshot: snapshot, version: version);
    } on _Corrupt {
      throw const LegacyBackupRejected(LegacyBackupRejection.corrupt);
    }
  }

  static const _topLevelKeys = [
    'version',
    'exportedAt',
    'appVersion',
    'playlists',
    'tracks',
    'playHistory',
    'searchHistory',
    'radioStations',
    'settings',
    'lyricsMatches',
  ];

  LegacySnapshot _snapshot(Map<String, dynamic> json) {
    final tracks = <LegacyTrack>[];
    // 曲目鍵 → 第一個有這個鍵的列（舊版匯入也以 `uniqueKey` 略過重複）。
    final idByKey = <String, int>{};
    for (final (index, item) in _maps(json['tracks']).indexed) {
      final id = index + 1;
      final sourceType = _requiredString(item, 'sourceType');
      final sourceId = _requiredString(item, 'sourceId');
      final cid = _int(item['cid']);
      idByKey.putIfAbsent(_trackKey(sourceType, sourceId, cid), () => id);
      tracks.add(
        LegacyTrack(
          id: id,
          sourceId: sourceId,
          sourceType: sourceType,
          title: _requiredString(item, 'title'),
          artist: _string(item['artist']),
          ownerId: _int(item['ownerId']),
          channelId: _string(item['channelId']),
          durationMs: _int(item['durationMs']),
          thumbnailUrl: _string(item['thumbnailUrl']),
          isAvailable: _bool(item['isAvailable']) ?? true,
          isVip: _bool(item['isVip']) ?? false,
          unavailableReason: _string(item['unavailableReason']),
          // 備份不帶下載路徑與歌單歸屬。
          playlistInfo: const [],
          pageCount: _int(item['pageCount']),
          cid: cid,
          pageNum: _int(item['pageNum']),
          parentTitle: _string(item['parentTitle']),
          bilibiliAid: _int(item['bilibiliAid']),
          originalSongId: _string(item['originalSongId']),
          originalSource: _string(item['originalSource']),
          createdAt: _requiredTime(item, 'createdAt'),
          updatedAt: _time(item['updatedAt']),
        ),
      );
    }

    // 懸空的曲目鍵：不存在的 id，轉換器當作 `danglingTrackId`。
    const missingTrackId = -1;
    final playlists = <LegacyPlaylist>[];
    for (final (index, item) in _maps(json['playlists']).indexed) {
      playlists.add(
        LegacyPlaylist(
          id: index + 1,
          name: _requiredString(item, 'name'),
          description: _string(item['description']),
          coverUrl: _string(item['coverUrl']),
          hasCustomCover: _bool(item['hasCustomCover']) ?? false,
          sourceUrl: _string(item['sourceUrl']),
          importSourceType: _string(item['importSourceType']),
          refreshIntervalHours: _int(item['refreshIntervalHours']),
          lastRefreshed: _time(item['lastRefreshed']),
          notifyOnUpdate: _bool(item['notifyOnUpdate']) ?? true,
          ownerName: _string(item['ownerName']),
          ownerUserId: _string(item['ownerUserId']),
          useAuthForRefresh: _bool(item['useAuthForRefresh']) ?? false,
          isMix: _bool(item['isMix']) ?? false,
          mixPlaylistId: _string(item['mixPlaylistId']),
          mixSeedVideoId: _string(item['mixSeedVideoId']),
          trackIds: [
            for (final key in _list(item['trackKeys']))
              if (key is String) idByKey[key] ?? missingTrackId,
          ],
          createdAt: _requiredTime(item, 'createdAt'),
          updatedAt: _time(item['updatedAt']),
          sortOrder: _int(item['sortOrder']) ?? 0,
        ),
      );
    }

    final history = [
      for (final (index, item) in _maps(json['playHistory']).indexed)
        LegacyPlayHistory(
          id: index + 1,
          sourceId: _requiredString(item, 'sourceId'),
          sourceType: _requiredString(item, 'sourceType'),
          cid: _int(item['cid']),
          title: _requiredString(item, 'title'),
          artist: _string(item['artist']),
          durationMs: _int(item['durationMs']),
          thumbnailUrl: _string(item['thumbnailUrl']),
          playedAt: _requiredTime(item, 'playedAt'),
        ),
    ];

    final searchHistory = [
      for (final (index, item) in _maps(json['searchHistory']).indexed)
        LegacySearchHistory(
          id: index + 1,
          query: _requiredString(item, 'query'),
          timestamp: _requiredTime(item, 'timestamp'),
        ),
    ];

    final radioStations = [
      for (final (index, item) in _maps(json['radioStations']).indexed)
        LegacyRadioStation(
          id: index + 1,
          url: _requiredString(item, 'url'),
          title: _requiredString(item, 'title'),
          thumbnailUrl: _string(item['thumbnailUrl']),
          hostName: _string(item['hostName']),
          hostAvatarUrl: _string(item['hostAvatarUrl']),
          hostUid: _int(item['hostUid']),
          sourceType: _requiredString(item, 'sourceType'),
          sourceId: _requiredString(item, 'sourceId'),
          sortOrder: _int(item['sortOrder']) ?? 0,
          createdAt: _requiredTime(item, 'createdAt'),
          lastPlayedAt: _time(item['lastPlayedAt']),
          isFavorite: _bool(item['isFavorite']) ?? false,
        ),
    ];

    final lyricsMatches = [
      for (final (index, item) in _maps(json['lyricsMatches']).indexed)
        LegacyLyricsMatch(
          id: index + 1,
          trackUniqueKey: _requiredString(item, 'trackUniqueKey'),
          lyricsSource: _requiredString(item, 'lyricsSource'),
          externalId: _requiredString(item, 'externalId'),
          offsetMs: _int(item['offsetMs']) ?? 0,
          matchedAt: _requiredTime(item, 'matchedAt'),
        ),
    ];

    final rawSettings = json['settings'];
    return LegacySnapshot(
      tracks: tracks,
      playlists: playlists,
      playQueues: const [],
      playHistory: history,
      settings: rawSettings is Map<String, dynamic>
          ? [_settings(rawSettings)]
          : const [],
      searchHistory: searchHistory,
      downloadTasks: const [],
      radioStations: radioStations,
      lyricsMatches: lyricsMatches,
      lyricsTitleParseCacheCount: 0,
      accounts: const [],
      // 備份沒有資料庫的 schemaVersion。
      storedSchemaVersion: null,
    );
  }

  /// `SettingsBackup.fromJson`：缺鍵走 [LegacySettings] 的建構子預設（＝舊版欄位初始值，與
  /// `SettingsBackup` 的預設相同）。`maxCacheSizeMB` 舊版預設依平台是 16 或 32，兩個都算沒改過
  /// （設定的轉換器），缺鍵時取 32。
  LegacySettings _settings(Map<String, dynamic> json) => LegacySettings(
    // 備份的設定不需要補做舊 migration（見類別說明）。
    schemaVersion: 4,
    themeModeIndex: _int(json['themeModeIndex']) ?? 0,
    primaryColor: _int(json['primaryColor']),
    railExpanded: _bool(json['railExpanded']) ?? false,
    detailPanelExpanded: _bool(json['detailPanelExpanded']) ?? false,
    detailPanelWidth: _double(json['detailPanelWidth']) ?? 412.0,
    maxCacheSizeMB: _int(json['maxCacheSizeMB']) ?? 32,
    hotkeyConfig: _string(json['hotkeyConfig']),
    autoScrollToCurrentTrack: _bool(json['autoScrollToCurrentTrack']) ?? false,
    rememberPlaybackPosition: _bool(json['rememberPlaybackPosition']) ?? true,
    restartRewindSeconds: _int(json['restartRewindSeconds']) ?? 0,
    tempPlayRewindSeconds: _int(json['tempPlayRewindSeconds']) ?? 10,
    playHistoryLimit: _int(json['playHistoryLimit']) ?? 10000,
    maxConcurrentDownloads: _int(json['maxConcurrentDownloads']) ?? 3,
    downloadImageOptionIndex: _int(json['downloadImageOptionIndex']) ?? 1,
    minimizeToTrayOnClose: _bool(json['minimizeToTrayOnClose']) ?? false,
    enableGlobalHotkeys: _bool(json['enableGlobalHotkeys']) ?? false,
    launchAtStartup: _bool(json['launchAtStartup']) ?? false,
    launchMinimized: _bool(json['launchMinimized']) ?? false,
    fontFamily: _string(json['fontFamily']),
    locale: _string(json['locale']),
    audioQualityLevelIndex: _int(json['audioQualityLevelIndex']) ?? 0,
    audioFormatPriority: _string(json['audioFormatPriority']) ?? 'opus,aac',
    sourceSettings: _sourceSettings(json),
    autoMatchLyrics: _bool(json['autoMatchLyrics']) ?? false,
    maxLyricsCacheFiles: _int(json['maxLyricsCacheFiles']) ?? 50,
    lyricsDisplayModeIndex: _int(json['lyricsDisplayModeIndex']) ?? 0,
    lyricsSourcePriority:
        _string(json['lyricsSourcePriority']) ?? 'netease,qqmusic,lrclib',
    disabledLyricsSources: _string(json['disabledLyricsSources']) ?? 'lrclib',
    lyricsAiTitleParsingModeIndex:
        _int(json['lyricsAiTitleParsingModeIndex']) ?? 0,
    allowPlainLyricsAutoMatch:
        _bool(json['allowPlainLyricsAutoMatch']) ?? false,
    lyricsAiEndpoint: _string(json['lyricsAiEndpoint']) ?? '',
    lyricsAiModel: _string(json['lyricsAiModel']) ?? '',
    lyricsAiTimeoutSeconds: _int(json['lyricsAiTimeoutSeconds']) ?? 20,
    lyricsWindowTextColor: _int(json['lyricsWindowTextColor']),
    lyricsWindowSecondaryTextColor: _int(
      json['lyricsWindowSecondaryTextColor'],
    ),
    lyricsWindowInactiveTextOpacity: _double(
      json['lyricsWindowInactiveTextOpacity'],
    ),
    lyricsWindowOutlineEnabled: _bool(json['lyricsWindowOutlineEnabled']),
    lyricsWindowOutlineColor: _int(json['lyricsWindowOutlineColor']),
    lyricsWindowOutlineWidth: _double(json['lyricsWindowOutlineWidth']),
    lyricsWindowShadowEnabled: _bool(json['lyricsWindowShadowEnabled']),
    lyricsWindowShadowColor: _int(json['lyricsWindowShadowColor']),
    lyricsWindowShadowBlurRadius: _double(json['lyricsWindowShadowBlurRadius']),
    lyricsWindowShadowOffsetX: _double(json['lyricsWindowShadowOffsetX']),
    lyricsWindowShadowOffsetY: _double(json['lyricsWindowShadowOffsetY']),
    rankingRefreshIntervalMinutes:
        _int(json['rankingRefreshIntervalMinutes']) ?? 60,
    homeRankingSourcePriority:
        _string(json['homeRankingSourcePriority']) ??
        'bilibili,youtube,netease',
    disabledHomeRankingSources:
        _string(json['disabledHomeRankingSources']) ?? '',
    radioRefreshIntervalMinutes: _int(json['radioRefreshIntervalMinutes']) ?? 5,
  );

  // 舊版 `kDefaultStreamPriorityBySource`、`kDefaultUseAuthForPlayBySource`。
  static const _defaultStreamPriority = {
    legacyBilibili: 'audioOnly,muxed',
    legacyYoutube: 'audioOnly,muxed,hls',
    legacyNetease: 'audioOnly',
  };
  static const _defaultUseAuth = {legacyBilibili: true, legacyNetease: true};

  /// 舊版 `_readSourceSettings`：v4 起是 `sourceSettings` 陣列；v3 以前是六個具名鍵，折疊成
  /// 三個音源各一筆，缺鍵用該音源的預設。
  List<LegacySourceSettings> _sourceSettings(Map<String, dynamic> json) {
    final raw = json['sourceSettings'];
    if (raw is List) {
      return [
        for (final entry in raw)
          if (entry is Map<String, dynamic>)
            LegacySourceSettings(
              sourceId: _string(entry['sourceId']) ?? '',
              streamPriority: _string(entry['streamPriority']) ?? '',
              useAuthForPlay:
                  _bool(entry['useAuthForPlay']) ??
                  (_defaultUseAuth[_string(entry['sourceId']) ?? ''] ?? false),
            ),
      ];
    }
    const keys = {
      legacyBilibili: ('bilibiliStreamPriority', 'useBilibiliAuthForPlay'),
      legacyYoutube: ('youtubeStreamPriority', 'useYoutubeAuthForPlay'),
      legacyNetease: ('neteaseStreamPriority', 'useNeteaseAuthForPlay'),
    };
    return [
      for (final MapEntry(key: sourceId, value: names) in keys.entries)
        LegacySourceSettings(
          sourceId: sourceId,
          streamPriority:
              _string(json[names.$1]) ?? _defaultStreamPriority[sourceId]!,
          useAuthForPlay:
              _bool(json[names.$2]) ?? (_defaultUseAuth[sourceId] ?? false),
        ),
    ];
  }

  /// 舊版 `TrackKey.format`。
  static String _trackKey(String sourceType, String sourceId, int? cid) =>
      cid != null ? '$sourceType:$sourceId:$cid' : '$sourceType:$sourceId';

  // ---- 欄位讀取 ----

  static List<Object?> _list(Object? value) => value is List ? value : const [];

  /// 清單裡的物件；不是物件的項目整份壞了。
  static Iterable<Map<String, dynamic>> _maps(Object? value) sync* {
    for (final item in _list(value)) {
      if (item is! Map<String, dynamic>) throw const _Corrupt();
      yield item;
    }
  }

  static String _requiredString(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is! String) throw const _Corrupt();
    return value;
  }

  static DateTime _requiredTime(Map<String, dynamic> json, String key) =>
      _time(json[key]) ?? (throw const _Corrupt());

  static String? _string(Object? value) => value is String ? value : null;

  static bool? _bool(Object? value) => value is bool ? value : null;

  static int? _int(Object? value) {
    if (value is int) return value;
    if (value is num && value.isFinite && value == value.truncate()) {
      return value.toInt();
    }
    return null;
  }

  static double? _double(Object? value) =>
      value is num ? value.toDouble() : null;

  /// 沒有時區的字串以本機時區解讀（`DateTime.parse`）；解不開當成沒有。
  static DateTime? _time(Object? value) =>
      value is String ? DateTime.tryParse(value) : null;
}

/// 必要欄位缺少或型別不對。
final class _Corrupt implements Exception {
  const _Corrupt();
}
