import 'dart:io';

import 'package:clock/clock.dart';
import 'package:isar_community/isar.dart';
import 'package:path/path.dart' as p;

import 'isar/schemas.dart' as legacy;
import 'legacy_settings_migration.dart';
import 'legacy_snapshot.dart';

/// 讀取失敗發生在哪一步。
enum LegacyReadStep { copy, open, read }

/// 讀舊資料庫失敗。訊息只有步驟與原因的型別，不含路徑或任何使用者資料；
/// 原始例外放 [cause]，不寫進訊息，也不要寫進 log。
final class LegacyReadException implements Exception {
  const LegacyReadException(this.step, this.cause);

  final LegacyReadStep step;
  final Object cause;

  @override
  String toString() =>
      'LegacyReadException(step: ${step.name}, cause: ${cause.runtimeType})';
}

/// 讀取器的 log 出口：只寫步驟與筆數。由組裝點接到 `Log`，工具（`dart run`）
/// 接到標準輸出；讀取器本身不 import `lib/core/logging/`（它依賴 Flutter）。
typedef LegacyReadLog = void Function(
  String message,
  Map<String, Object?> fields,
);

/// 舊資料庫的實例名稱與檔名（舊 App 的 `fmpDatabaseName`）。
const legacyDatabaseName = 'fmp_database';
const legacyDatabaseFileName = '$legacyDatabaseName.isar';

/// 把舊版的 Isar 資料庫讀成 [LegacySnapshot]，舊檔一個位元組都不動。
///
/// Isar 沒有唯讀模式：每次開啟都會建 lock 檔，也可能依 schema 差異改寫檔案。
/// 所以先複製到工作目錄、開副本，讀完關閉並刪掉整個工作目錄（成功與失敗都
/// 刪）。lock 檔不複製（design §0.3、§4.1）。
final class LegacyDatabaseReader {
  LegacyDatabaseReader({required this._log});

  final LegacyReadLog _log;

  /// 讀 [database]（舊資料庫檔），工作目錄建在 [workRoot] 底下
  /// （`<資料目錄>/legacy-import/`）。
  ///
  /// 前提：Isar 的原生庫已載入（App 裡由 `isar_community_flutter_libs` 隨建置
  /// 打包、開庫時自動載入；測試與工具見 `test/support/libisar.dart`）。
  Future<LegacySnapshot> read(File database, Directory workRoot) async {
    final stamp = clock.now().toUtc().toIso8601String().replaceAll(
      RegExp('[:.]'),
      '',
    );
    final workDirectory = Directory(p.join(workRoot.path, 'work-$stamp'));
    var step = LegacyReadStep.copy;
    Isar? isar;
    try {
      await workDirectory.create(recursive: true);
      await database.copy(p.join(workDirectory.path, legacyDatabaseFileName));
      _log('Legacy database copied', {'step': step.name});

      step = LegacyReadStep.open;
      isar = await Isar.open(
        legacy.legacyIsarSchemas,
        directory: workDirectory.path,
        name: legacyDatabaseName,
        maxSizeMiB: 2048,
        inspector: false,
      );
      _log('Legacy database opened', {'step': step.name});

      step = LegacyReadStep.read;
      return await _readAll(isar);
    } on Object catch (error) {
      throw LegacyReadException(step, error);
    } finally {
      try {
        await isar?.close();
      } on Object catch (error) {
        _log('Legacy database close failed', {
          'errorType': '${error.runtimeType}',
        });
      }
      try {
        if (workDirectory.existsSync()) {
          await workDirectory.delete(recursive: true);
        }
        _log('Legacy work directory deleted', const {});
      } on Object catch (error) {
        _log('Legacy work directory cleanup failed', {
          'errorType': '${error.runtimeType}',
        });
      }
    }
  }

  Future<LegacySnapshot> _readAll(Isar isar) async {
    final tracks = await isar.tracks.where().findAll();
    final playlists = await isar.playlists.where().findAll();
    final playQueues = await isar.playQueues.where().findAll();
    final playHistory = await isar.playHistorys.where().findAll();
    final settings = await isar.settings.where().findAll();
    final searchHistory = await isar.searchHistorys.where().findAll();
    final downloadTasks = await isar.downloadTasks.where().findAll();
    final radioStations = await isar.radioStations.where().findAll();
    final lyricsMatches = await isar.lyricsMatchs.where().findAll();
    final titleParseCacheCount = await isar.lyricsTitleParseCaches.count();
    final accounts = await isar.accounts.where().findAll();

    // 舊 App 每次啟動都寫設定列（id 0，`runDatabaseMigration`），所以沒有設定列
    // 的就不是可用的舊庫。最常見的是太小或壞掉的檔：libmdbx 把它當成新庫開，
    // 不報錯，讀出來全空；不擋的話呼叫端會把它當成「舊資料是空的」匯入。
    if (settings.isEmpty) {
      throw StateError('The legacy database has no settings row');
    }

    final snapshotSettings = settings.map(_settings).toList();
    final stored = effectiveLegacySchemaVersion(
      snapshotSettings.first.schemaVersion,
    );
    for (final row in snapshotSettings) {
      if (effectiveLegacySchemaVersion(row.schemaVersion) <
          legacySettingsSchemaVersion) {
        replayLegacySettingsMigration(row);
      }
    }

    final snapshot = LegacySnapshot(
      tracks: tracks.map(_track).toList(),
      playlists: playlists.map(_playlist).toList(),
      playQueues: playQueues.map(_playQueue).toList(),
      playHistory: playHistory.map(_playHistory).toList(),
      settings: snapshotSettings,
      searchHistory: searchHistory.map(_searchHistory).toList(),
      downloadTasks: downloadTasks.map(_downloadTask).toList(),
      radioStations: radioStations.map(_radioStation).toList(),
      lyricsMatches: lyricsMatches.map(_lyricsMatch).toList(),
      lyricsTitleParseCacheCount: titleParseCacheCount,
      accounts: accounts.map(_account).toList(),
      storedSchemaVersion: stored,
    );
    for (final MapEntry(:key, :value) in snapshot.counts.entries) {
      _log('Legacy collection read', {'collection': key, 'count': value});
    }
    return snapshot;
  }
}

LegacyTrack _track(legacy.Track t) => LegacyTrack(
  id: t.id,
  sourceId: t.sourceId,
  sourceType: t.sourceType,
  title: t.title,
  artist: t.artist,
  ownerId: t.ownerId,
  channelId: t.channelId,
  durationMs: t.durationMs,
  thumbnailUrl: t.thumbnailUrl,
  isAvailable: t.isAvailable,
  isVip: t.isVip,
  unavailableReason: t.unavailableReason,
  playlistInfo: [
    for (final info in t.playlistInfo)
      LegacyPlaylistDownloadInfo(
        playlistId: info.playlistId,
        playlistName: info.playlistName,
        downloadPath: info.downloadPath,
      ),
  ],
  pageCount: t.pageCount,
  cid: t.cid,
  pageNum: t.pageNum,
  parentTitle: t.parentTitle,
  bilibiliAid: t.bilibiliAid,
  originalSongId: t.originalSongId,
  originalSource: t.originalSource,
  createdAt: t.createdAt,
  updatedAt: t.updatedAt,
);

LegacyPlaylist _playlist(legacy.Playlist p) => LegacyPlaylist(
  id: p.id,
  name: p.name,
  description: p.description,
  coverUrl: p.coverUrl,
  hasCustomCover: p.hasCustomCover,
  sourceUrl: p.sourceUrl,
  importSourceType: p.importSourceType,
  refreshIntervalHours: p.refreshIntervalHours,
  lastRefreshed: p.lastRefreshed,
  notifyOnUpdate: p.notifyOnUpdate,
  ownerName: p.ownerName,
  ownerUserId: p.ownerUserId,
  useAuthForRefresh: p.useAuthForRefresh,
  isMix: p.isMix,
  mixPlaylistId: p.mixPlaylistId,
  mixSeedVideoId: p.mixSeedVideoId,
  trackIds: List.of(p.trackIds),
  createdAt: p.createdAt,
  updatedAt: p.updatedAt,
  sortOrder: p.sortOrder,
);

LegacyPlayQueue _playQueue(legacy.PlayQueue q) => LegacyPlayQueue(
  id: q.id,
  trackIds: List.of(q.trackIds),
  currentIndex: q.currentIndex,
  lastPositionMs: q.lastPositionMs,
  isShuffleEnabled: q.isShuffleEnabled,
  loopMode: switch (q.loopMode) {
    legacy.LoopMode.none => LegacyLoopMode.none,
    legacy.LoopMode.all => LegacyLoopMode.all,
    legacy.LoopMode.one => LegacyLoopMode.one,
  },
  originalOrder: q.originalOrder == null ? null : List.of(q.originalOrder!),
  lastVolume: q.lastVolume,
  lastUpdated: q.lastUpdated,
  isMixMode: q.isMixMode,
  mixPlaylistId: q.mixPlaylistId,
  mixSeedVideoId: q.mixSeedVideoId,
  mixTitle: q.mixTitle,
);

LegacyPlayHistory _playHistory(legacy.PlayHistory h) => LegacyPlayHistory(
  id: h.id,
  sourceId: h.sourceId,
  sourceType: h.sourceType,
  cid: h.cid,
  title: h.title,
  artist: h.artist,
  durationMs: h.durationMs,
  thumbnailUrl: h.thumbnailUrl,
  playedAt: h.playedAt,
);

LegacySearchHistory _searchHistory(legacy.SearchHistory s) =>
    LegacySearchHistory(id: s.id, query: s.query, timestamp: s.timestamp);

LegacyDownloadTask _downloadTask(legacy.DownloadTask d) => LegacyDownloadTask(
  id: d.id,
  trackId: d.trackId,
  playlistId: d.playlistId,
  playlistName: d.playlistName,
  savePath: d.savePath,
  status: switch (d.status) {
    legacy.DownloadStatus.pending => LegacyDownloadStatus.pending,
    legacy.DownloadStatus.downloading => LegacyDownloadStatus.downloading,
    legacy.DownloadStatus.paused => LegacyDownloadStatus.paused,
    legacy.DownloadStatus.completed => LegacyDownloadStatus.completed,
    legacy.DownloadStatus.failed => LegacyDownloadStatus.failed,
  },
  progress: d.progress,
  downloadedBytes: d.downloadedBytes,
  totalBytes: d.totalBytes,
  errorMessage: d.errorMessage,
  tempFilePath: d.tempFilePath,
  priority: d.priority,
  createdAt: d.createdAt,
  completedAt: d.completedAt,
);

LegacyRadioStation _radioStation(legacy.RadioStation r) => LegacyRadioStation(
  id: r.id,
  url: r.url,
  title: r.title,
  thumbnailUrl: r.thumbnailUrl,
  hostName: r.hostName,
  hostAvatarUrl: r.hostAvatarUrl,
  hostUid: r.hostUid,
  sourceType: r.sourceType,
  sourceId: r.sourceId,
  sortOrder: r.sortOrder,
  createdAt: r.createdAt,
  lastPlayedAt: r.lastPlayedAt,
  isFavorite: r.isFavorite,
);

LegacyLyricsMatch _lyricsMatch(legacy.LyricsMatch m) => LegacyLyricsMatch(
  id: m.id,
  trackUniqueKey: m.trackUniqueKey,
  lyricsSource: m.lyricsSource,
  externalId: m.externalId,
  offsetMs: m.offsetMs,
  matchedAt: m.matchedAt,
);

LegacyAccount _account(legacy.Account a) => LegacyAccount(
  id: a.id,
  platform: a.platform,
  userId: a.userId,
  userName: a.userName,
  avatarUrl: a.avatarUrl,
  isLoggedIn: a.isLoggedIn,
  lastRefreshed: a.lastRefreshed,
  loginAt: a.loginAt,
  isVip: a.isVip,
  sessionExpired: a.sessionExpired,
);

LegacySettings _settings(legacy.Settings s) => LegacySettings(
  id: s.id,
  schemaVersion: s.schemaVersion,
  themeModeIndex: s.themeModeIndex,
  primaryColor: s.primaryColor,
  railExpanded: s.railExpanded,
  detailPanelExpanded: s.detailPanelExpanded,
  detailPanelWidth: s.detailPanelWidth,
  maxCacheSizeMB: s.maxCacheSizeMB,
  customDownloadDir: s.customDownloadDir,
  hotkeyConfig: s.hotkeyConfig,
  autoScrollToCurrentTrack: s.autoScrollToCurrentTrack,
  rememberPlaybackPosition: s.rememberPlaybackPosition,
  restartRewindSeconds: s.restartRewindSeconds,
  tempPlayRewindSeconds: s.tempPlayRewindSeconds,
  playHistoryLimit: s.playHistoryLimit,
  maxConcurrentDownloads: s.maxConcurrentDownloads,
  downloadImageOptionIndex: s.downloadImageOptionIndex,
  minimizeToTrayOnClose: s.minimizeToTrayOnClose,
  enableGlobalHotkeys: s.enableGlobalHotkeys,
  launchAtStartup: s.launchAtStartup,
  launchMinimized: s.launchMinimized,
  fontFamily: s.fontFamily,
  locale: s.locale,
  audioQualityLevelIndex: s.audioQualityLevelIndex,
  audioFormatPriority: s.audioFormatPriority,
  sourceSettings: [
    for (final entry in s.sourceSettings)
      LegacySourceSettings(
        sourceId: entry.sourceId,
        streamPriority: entry.streamPriority,
        useAuthForPlay: entry.useAuthForPlay,
      ),
  ],
  youtubeStreamPriority: s.youtubeStreamPriority,
  bilibiliStreamPriority: s.bilibiliStreamPriority,
  neteaseStreamPriority: s.neteaseStreamPriority,
  preferredAudioDeviceId: s.preferredAudioDeviceId,
  preferredAudioDeviceName: s.preferredAudioDeviceName,
  autoMatchLyrics: s.autoMatchLyrics,
  maxLyricsCacheFiles: s.maxLyricsCacheFiles,
  lyricsDisplayModeIndex: s.lyricsDisplayModeIndex,
  lyricsSourcePriority: s.lyricsSourcePriority,
  disabledLyricsSources: s.disabledLyricsSources,
  lyricsAiTitleParsingModeIndex: s.lyricsAiTitleParsingModeIndex,
  allowPlainLyricsAutoMatch: s.allowPlainLyricsAutoMatch,
  lyricsAiEndpoint: s.lyricsAiEndpoint,
  lyricsAiModel: s.lyricsAiModel,
  lyricsAiTimeoutSeconds: s.lyricsAiTimeoutSeconds,
  lyricsWindowTextColor: s.lyricsWindowTextColor,
  lyricsWindowSecondaryTextColor: s.lyricsWindowSecondaryTextColor,
  lyricsWindowInactiveTextOpacity: s.lyricsWindowInactiveTextOpacity,
  lyricsWindowOutlineEnabled: s.lyricsWindowOutlineEnabled,
  lyricsWindowOutlineColor: s.lyricsWindowOutlineColor,
  lyricsWindowOutlineWidth: s.lyricsWindowOutlineWidth,
  lyricsWindowShadowEnabled: s.lyricsWindowShadowEnabled,
  lyricsWindowShadowColor: s.lyricsWindowShadowColor,
  lyricsWindowShadowBlurRadius: s.lyricsWindowShadowBlurRadius,
  lyricsWindowShadowOffsetX: s.lyricsWindowShadowOffsetX,
  lyricsWindowShadowOffsetY: s.lyricsWindowShadowOffsetY,
  useBilibiliAuthForPlay: s.useBilibiliAuthForPlay,
  useYoutubeAuthForPlay: s.useYoutubeAuthForPlay,
  useNeteaseAuthForPlay: s.useNeteaseAuthForPlay,
  rankingRefreshIntervalMinutes: s.rankingRefreshIntervalMinutes,
  homeRankingSourcePriority: s.homeRankingSourcePriority,
  disabledHomeRankingSources: s.disabledHomeRankingSources,
  radioRefreshIntervalMinutes: s.radioRefreshIntervalMinutes,
);
