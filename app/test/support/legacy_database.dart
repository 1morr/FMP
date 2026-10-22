import 'dart:io';

import 'package:fmp/legacy_import/isar/schemas.dart';
import 'package:isar_community/isar.dart';
import 'package:path/path.dart' as p;

/// Isar 讀缺欄的非空 `int` 得到的值（-2^63，舊版稱 minLong）。
const legacyNullLong = -9223372036854775808;

/// 合成的舊版（Isar）資料庫，全部是編造的資料，沒有任何真實使用者內容。
///
/// 純 Dart（不 import flutter_test）：`tool/legacy_fixture.dart` 也用它寫一份
/// 給實機驗證用的舊庫。開庫前原生庫要先載入（`support/libisar.dart`）。
///
/// 涵蓋 design §9 要求的情境：缺欄的型別預設值（`legacyNullLong`、NaN）、同一個
/// 曲目鍵的兩列、指向不存在曲目的 id、B 站的兩段與三段曲目鍵、多 P 與單 P。
/// 曲目 id 固定，測試可以直接引用。
abstract final class SyntheticLegacy {
  /// 多 P 影片 BV1 的第 1、2 P（有 cid）。
  static const multiPartOne = 1;
  static const multiPartTwo = 2;

  /// 單 P、沒有 cid 的 B 站曲目（兩段鍵）。
  static const singleNoCid = 3;

  /// 單 P、有 cid 的 B 站曲目（三段鍵）。
  static const singleWithCid = 4;
  static const youtube = 5;

  /// 網易雲，有下載路徑與 `playlistId = 0` 的本機檔案項目。
  static const netease = 6;

  /// 和 [youtube] 同一個曲目鍵的第二列。
  static const youtubeDuplicate = 7;

  /// 不存在的曲目 id（歌單與佇列裡的懸空引用）。
  static const danglingTrackId = 9999;

  static const trackCount = 7;
  static const playlistCount = 3;
  static const playHistoryCount = 4;
  static const searchHistoryCount = 2;
  static const downloadTaskCount = 2;
  static const radioStationCount = 2;
  static const lyricsMatchCount = 2;
  static const lyricsTitleParseCacheCount = 1;
  static const accountCount = 2;

  /// 供比對時間值的固定時間（UTC）。
  static final baseTime = DateTime.utc(2025, 3, 14, 15, 9, 26);
}

/// 在 [directory] 寫一份合成的舊庫 `fmp_database.isar`，回傳那個檔案。
///
/// [schemaVersion] 為 `null` 時設定列沒有版本欄位（Isar 讀成 `legacyNullLong`，
/// 即 v0）。[withSettings] 為 false 時不寫設定列（舊 App 不會產生這種庫）。
Future<File> writeSyntheticLegacyDatabase(
  Directory directory, {
  int? schemaVersion = 4,
  bool withSettings = true,
}) async {
  await directory.create(recursive: true);
  final isar = await Isar.open(
    legacyIsarSchemas,
    directory: directory.path,
    name: 'fmp_database',
    inspector: false,
  );
  try {
    await isar.writeTxn(() async {
      await isar.tracks.putAll(_tracks());
      await isar.playlists.putAll(_playlists());
      await isar.playQueues.put(_queue());
      await isar.playHistorys.putAll(_history());
      if (withSettings) {
        await isar.settings.put(_settings(schemaVersion ?? legacyNullLong));
      }
      await isar.searchHistorys.putAll([
        SearchHistory()
          ..id = 1
          ..query = 'synthetic query one'
          ..timestamp = SyntheticLegacy.baseTime,
        SearchHistory()
          ..id = 2
          ..query = 'synthetic query two'
          ..timestamp = SyntheticLegacy.baseTime.add(const Duration(days: 1)),
      ]);
      await isar.downloadTasks.putAll(_downloads());
      await isar.radioStations.putAll(_radio());
      await isar.lyricsMatchs.putAll([
        LyricsMatch()
          ..id = 1
          ..trackUniqueKey = 'bilibili:BV1synthetic0001:1001'
          ..lyricsSource = 'netease'
          ..externalId = '10001'
          ..offsetMs = -250
          ..matchedAt = SyntheticLegacy.baseTime,
        // 兩段鍵：曲目後來補了 cid，這列還沒改鍵。
        LyricsMatch()
          ..id = 2
          ..trackUniqueKey = 'bilibili:BV3synthetic0003'
          ..lyricsSource = 'lrclib'
          ..externalId = '20002'
          ..matchedAt = SyntheticLegacy.baseTime,
      ]);
      await isar.lyricsTitleParseCaches.put(
        LyricsTitleParseCache()
          ..id = 1
          ..trackUniqueKey = 'youtube:ytsynthetic01'
          ..sourceType = 'youtube'
          ..parsedTrackName = 'Synthetic Song'
          ..provider = 'synthetic'
          ..model = 'synthetic-model',
      );
      await isar.accounts.putAll(_accounts());
    });
  } finally {
    await isar.close();
  }
  return File(p.join(directory.path, 'fmp_database.isar'));
}

List<Track> _tracks() {
  final base = SyntheticLegacy.baseTime;
  return [
    Track()
      ..id = SyntheticLegacy.multiPartOne
      ..sourceId = 'BV1synthetic0001'
      ..sourceType = 'bilibili'
      ..title = 'Synthetic Multi P1'
      ..artist = 'Synthetic Uploader'
      ..ownerId = 1001
      ..durationMs = 180000
      ..thumbnailUrl = 'https://example.invalid/cover1.jpg'
      ..audioUrl = 'https://example.invalid/expired.m4s?sign=FAKE'
      ..audioUrlExpiry = base
      ..pageCount = 2
      ..cid = 1001
      ..pageNum = 1
      ..parentTitle = 'Synthetic Multi Part Video'
      ..bilibiliAid = 777
      ..createdAt = base
      ..updatedAt = base
      ..playlistInfo = [
        PlaylistDownloadInfo()
          ..playlistId = 1
          ..playlistName = 'Synthetic Local',
      ],
    Track()
      ..id = SyntheticLegacy.multiPartTwo
      ..sourceId = 'BV1synthetic0001'
      ..sourceType = 'bilibili'
      ..title = 'Synthetic Multi P2'
      ..artist = 'Synthetic Uploader'
      ..durationMs = 200000
      ..pageCount = 2
      ..cid = 1002
      ..pageNum = 2
      ..parentTitle = 'Synthetic Multi Part Video'
      ..createdAt = base
      ..playlistInfo = [
        PlaylistDownloadInfo()
          ..playlistId = 1
          ..playlistName = 'Synthetic Local',
      ],
    Track()
      ..id = SyntheticLegacy.singleNoCid
      ..sourceId = 'BV3synthetic0003'
      ..sourceType = 'bilibili'
      ..title = 'Synthetic Single No Cid'
      ..pageCount = 1
      ..pageNum = 1
      ..isAvailable = false
      ..unavailableReason = 'synthetic reason'
      ..createdAt = base,
    Track()
      ..id = SyntheticLegacy.singleWithCid
      ..sourceId = 'BV4synthetic0004'
      ..sourceType = 'bilibili'
      ..title = 'Synthetic Single With Cid'
      ..pageCount = 1
      ..cid = 4004
      ..pageNum = 1
      ..isVip = true
      ..createdAt = base,
    Track()
      ..id = SyntheticLegacy.youtube
      ..sourceId = 'ytsynthetic01'
      ..sourceType = 'youtube'
      ..title = 'Synthetic YouTube'
      ..channelId = 'UCsynthetic'
      ..durationMs = 120000
      ..createdAt = base,
    Track()
      ..id = SyntheticLegacy.netease
      ..sourceId = '10001'
      ..sourceType = 'netease'
      ..title = 'Synthetic Netease'
      ..originalSongId = '10001'
      ..originalSource = 'netease'
      ..createdAt = base
      ..playlistInfo = [
        PlaylistDownloadInfo()
          ..playlistId = 1
          ..playlistName = 'Synthetic Local'
          ..downloadPath = '/synthetic/music/Synthetic Local/10001_x/audio.m4a',
        PlaylistDownloadInfo()
          ..playlistId = 0
          ..downloadPath = '/synthetic/music/scanned/audio.m4a',
      ],
    Track()
      ..id = SyntheticLegacy.youtubeDuplicate
      ..sourceId = 'ytsynthetic01'
      ..sourceType = 'youtube'
      ..title = 'Synthetic YouTube (duplicate key)'
      ..createdAt = base,
  ];
}

List<Playlist> _playlists() {
  final base = SyntheticLegacy.baseTime;
  return [
    Playlist()
      ..id = 1
      ..name = 'Synthetic Local'
      ..description = 'a synthetic playlist'
      ..hasCustomCover = true
      ..coverUrl = 'https://example.invalid/pl1.jpg'
      ..trackIds = [
        SyntheticLegacy.multiPartOne,
        SyntheticLegacy.multiPartTwo,
        SyntheticLegacy.singleNoCid,
        SyntheticLegacy.youtube,
        SyntheticLegacy.danglingTrackId,
        SyntheticLegacy.netease,
      ]
      ..createdAt = base
      ..sortOrder = 2,
    Playlist()
      ..id = 2
      ..name = 'Synthetic Imported'
      ..sourceUrl = 'https://example.invalid/favlist?fid=1'
      ..importSourceType = 'bilibili'
      ..refreshIntervalHours = 24
      ..lastRefreshed = base
      ..notifyOnUpdate = false
      ..ownerName = 'Synthetic Owner'
      ..ownerUserId = '555'
      ..useAuthForRefresh = true
      ..trackIds = [SyntheticLegacy.singleWithCid, SyntheticLegacy.youtube]
      ..createdAt = base
      ..updatedAt = base
      ..sortOrder = 1,
    Playlist()
      ..id = 3
      ..name = 'Synthetic Mix'
      ..isMix = true
      ..mixPlaylistId = 'RDsynthetic'
      ..mixSeedVideoId = 'ytsynthetic01'
      ..createdAt = base
      ..sortOrder = 0,
  ];
}

PlayQueue _queue() => PlayQueue()
  ..id = 1
  ..trackIds = [
    SyntheticLegacy.youtube,
    SyntheticLegacy.multiPartOne,
    SyntheticLegacy.singleNoCid,
    SyntheticLegacy.danglingTrackId,
  ]
  ..currentIndex = 1
  ..lastPositionMs = 42000
  ..isShuffleEnabled = true
  ..loopMode = LoopMode.all
  // 隨機開啟時舊版仍可能存空 list，不是 null。
  ..originalOrder = []
  ..lastVolume = 0.5
  ..lastUpdated = SyntheticLegacy.baseTime
  ..isMixMode = true
  ..mixPlaylistId = 'RDsynthetic'
  ..mixSeedVideoId = 'ytsynthetic01'
  ..mixTitle = 'Synthetic Mix';

List<PlayHistory> _history() {
  final base = SyntheticLegacy.baseTime;
  return [
    // 三段鍵，對得上曲目。
    PlayHistory()
      ..id = 1
      ..sourceId = 'BV1synthetic0001'
      ..sourceType = 'bilibili'
      ..cid = 1001
      ..title = 'Synthetic Multi P1'
      ..artist = 'Synthetic Uploader'
      ..durationMs = 180000
      ..thumbnailUrl = 'https://example.invalid/cover1.jpg'
      ..playedAt = base,
    // 兩段鍵，曲目後來有了 cid。
    PlayHistory()
      ..id = 2
      ..sourceId = 'BV1synthetic0001'
      ..sourceType = 'bilibili'
      ..title = 'Synthetic Multi P1 (before cid)'
      ..playedAt = base.add(const Duration(hours: 1)),
    // 曲目表裡沒有這首。
    PlayHistory()
      ..id = 3
      ..sourceId = 'BV9gone000009'
      ..sourceType = 'bilibili'
      ..cid = 9009
      ..title = 'Synthetic Gone Track'
      ..playedAt = base.add(const Duration(hours: 2)),
    PlayHistory()
      ..id = 4
      ..sourceId = 'ytsynthetic01'
      ..sourceType = 'youtube'
      ..title = 'Synthetic YouTube'
      ..playedAt = base.add(const Duration(hours: 3)),
  ];
}

Settings _settings(int schemaVersion) => Settings()
  ..schemaVersion = schemaVersion
  ..themeModeIndex = 2
  ..primaryColor = 0xFF336699
  ..customDownloadDir = '/synthetic/downloads'
  ..locale = 'zh_TW'
  ..restartRewindSeconds = 5
  // 缺欄的型別預設值（Isar 對舊列補的值）。
  ..playHistoryLimit = legacyNullLong
  ..detailPanelWidth = double.nan
  ..sourceSettings = [
    SourceSettingsEntry()
      ..sourceId = 'bilibili'
      ..streamPriority = 'audioOnly,muxed'
      ..useAuthForPlay = true,
    SourceSettingsEntry()
      ..sourceId = 'youtube'
      ..streamPriority = 'audioOnly,muxed,hls'
      ..useAuthForPlay = false,
    SourceSettingsEntry()
      ..sourceId = 'netease'
      ..streamPriority = 'audioOnly'
      ..useAuthForPlay = true,
  ]
  ..lyricsAiEndpoint = 'https://example.invalid/v1'
  ..lyricsWindowOutlineEnabled = true
  ..lyricsWindowShadowBlurRadius = 3.5;

List<DownloadTask> _downloads() {
  final base = SyntheticLegacy.baseTime;
  return [
    DownloadTask()
      ..id = 1
      ..trackId = SyntheticLegacy.netease
      ..playlistId = 1
      ..playlistName = 'Synthetic Local'
      ..savePath = '/synthetic/music/Synthetic Local/10001_x/audio.m4a'
      ..status = DownloadStatus.completed
      ..progress = 1.0
      ..downloadedBytes = 1024
      ..totalBytes = 1024
      ..createdAt = base
      ..completedAt = base.add(const Duration(minutes: 1)),
    DownloadTask()
      ..id = 2
      ..trackId = SyntheticLegacy.youtube
      ..status = DownloadStatus.failed
      ..errorMessage = 'synthetic error'
      ..tempFilePath = '/synthetic/tmp/x.downloading'
      ..priority = 3
      ..createdAt = base,
  ];
}

List<RadioStation> _radio() {
  final base = SyntheticLegacy.baseTime;
  return [
    RadioStation()
      ..id = 1
      ..url = 'https://example.invalid/live/123'
      ..title = 'Synthetic Live Room'
      ..hostName = 'Synthetic Host'
      ..hostUid = 321
      ..sourceType = 'bilibili'
      ..sourceId = '123'
      ..sortOrder = 1
      ..isFavorite = true
      ..createdAt = base
      ..lastPlayedAt = base,
    RadioStation()
      ..id = 2
      ..url = 'https://example.invalid/watch?v=ytlive'
      ..title = 'Synthetic YouTube Live'
      ..sourceType = 'youtube'
      ..sourceId = 'ytlive'
      ..createdAt = base,
  ];
}

List<Account> _accounts() {
  final base = SyntheticLegacy.baseTime;
  return [
    Account()
      ..id = 1
      ..platform = 'bilibili'
      ..userId = '555'
      ..userName = 'Synthetic User'
      ..avatarUrl = 'https://example.invalid/avatar.jpg'
      ..isLoggedIn = true
      ..lastRefreshed = base
      ..loginAt = base,
    Account()
      ..id = 2
      ..platform = 'netease'
      ..isLoggedIn = false
      ..sessionExpired = true
      ..isVip = true,
  ];
}
