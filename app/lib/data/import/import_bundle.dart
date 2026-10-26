import 'package:flutter/foundation.dart';

import 'package:fmp/data/import/import_summary.dart';
import 'package:fmp/data/repositories/account_repository.dart';
import 'package:fmp/data/repositories/appearance_settings_repository.dart';
import 'package:fmp/data/repositories/layout_state_repository.dart';
import 'package:fmp/data/repositories/network_settings_repository.dart';
import 'package:fmp/data/repositories/playback_settings_repository.dart';
import 'package:fmp/data/repositories/queue_repository.dart';
import 'package:fmp/domain/legacy_import.dart';
import 'package:fmp/domain/playlist.dart';
import 'package:fmp/domain/track_info.dart';
import 'package:fmp/domain/track_key.dart';

// 匯入包（M5 design §2.1、§5）：轉換器的輸出、`StagingImport` 的輸入。以新版的語彙寫，沒有
// 舊版的概念（舊歌單 id 除外，給 `legacy_playlist_ids`）。純值：沒有憑證（只在記憶體，另走
// `CredentialStore`），也沒有 id——新版的 id 由暫存庫產生，順序就是這裡的清單順序。

/// 一次匯入要寫進暫存庫的全部內容。
///
/// 清單的順序就是結果的順序：歌單與電台的 `sort_order` 是它們在清單裡的位置，佇列的位置
/// 與歌單項目的 `position` 也是，播放歷史依清單順序寫入（`played_at` 相同時後寫的算新的）。
/// 時間是原始值，寫入時取到毫秒。
///
/// 曲目只放被歌單、佇列、播放歷史參照的（沒人參照的曲目寫了會被驗證擋下，也會被啟動維護
/// 當孤兒刪掉）；參照它們的地方用曲目鍵，鍵必須在 [tracks] 裡。
@immutable
final class ImportBundle {
  const ImportBundle({
    required this.record,
    this.tracks = const [],
    this.playlists = const [],
    this.queue = const [],
    this.playerState,
    this.history = const [],
    this.searchHistory = const [],
    this.radioStations = const [],
    this.trackOrigins = const [],
    this.accounts = const [],
    this.appearance = AppearanceSettings.empty,
    this.network = NetworkSettings.empty,
    this.playback = PlaybackSettings.empty,
    this.browseAsLoggedIn = const {},
    this.layout = LayoutState.empty,
  });

  /// `legacy_imports` 的那一列。
  final ImportRecord record;

  final List<TrackInfo> tracks;
  final List<ImportPlaylist> playlists;

  /// 佇列的每個位置，依位置。
  final List<ImportQueueEntry> queue;

  /// `player_state` 那一列；空＝不寫。佇列是空的時也可以有（音量、循環模式照樣恢復，
  /// `currentPosition` 為空）。
  final PlayerState? playerState;
  final List<ImportHistoryEntry> history;

  /// 搜尋歷史（ADR 0035 §決定 12）：已經去重（trim 後的關鍵字不重複）、最多 50 筆，順序不拘。
  final List<ImportSearchHistoryEntry> searchHistory;
  final List<ImportRadioStation> radioStations;
  final List<ImportTrackOrigin> trackOrigins;

  /// 帳號顯示資訊（`accounts`）。憑證不在這裡：帳號列與憑證要成對，由 PR 4 的流程一起處理。
  final List<Account> accounts;

  // 設定：每個欄位都是可空的，空＝不寫，新版的預設生效（ADR 0011 §決定 7）。整組都是空的
  // 就不建那一列。
  final AppearanceSettings appearance;
  final NetworkSettings network;
  final PlaybackSettings playback;

  /// `source_settings.browse_as_logged_in`：插件 id → 值。每個音源照舊值寫（M5 design §5.9）。
  final Map<String, bool> browseAsLoggedIn;
  final LayoutState layout;
}

/// `legacy_imports` 的內容（M5 design §6.4）。
@immutable
final class ImportRecord {
  const ImportRecord({
    required this.source,
    required this.summary,
    this.legacySchemaVersion,
    this.backupVersion,
  });

  final LegacyImportSource source;

  /// 舊 `Settings.schemaVersion`（資料庫來源）。
  final int? legacySchemaVersion;

  /// 備份檔的 `version`（備份來源）。
  final int? backupVersion;
  final ImportSummary summary;
}

/// 一張要匯入的歌單。
@immutable
final class ImportPlaylist {
  const ImportPlaylist({
    required this.kind,
    required this.name,
    required this.createdAt,
    required this.updatedAt,
    this.legacyPlaylistId,
    this.description,
    this.artwork = const [],
    this.mixPluginId,
    this.mixSeedSourceId,
    this.mixSeedCid,
    this.remote,
    this.entries = const [],
  });

  /// 舊 `Playlist.id`，給 `legacy_playlist_ids`；備份檔來源的歌單沒有。
  final int? legacyPlaylistId;
  final PlaylistKind kind;
  final String name;
  final String? description;
  final List<TrackArtwork> artwork;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// 只有 `mix` 歌單有（資料庫的 CHECK 擋其他組合）。
  final String? mixPluginId;
  final String? mixSeedSourceId;
  final int? mixSeedCid;

  /// 只有 `imported` 歌單有。
  final ImportPlaylistRemote? remote;

  /// 依順序；`mix` 歌單沒有項目。
  final List<ImportPlaylistEntry> entries;
}

/// `playlist_remote` 要寫的欄位；其餘欄位用預設（`last_result` 空、`status` 為 `active`、
/// 名稱與說明的 overridden 旗標為假、`refresh_generation` 為 0）。
@immutable
final class ImportPlaylistRemote {
  const ImportPlaylistRemote({
    required this.pluginId,
    required this.remoteId,
    this.ownerName,
    this.writable = false,
    this.artworkOverridden = false,
    this.refreshIntervalHours,
    this.lastRefreshedAt,
  });

  final String pluginId;
  final String remoteId;
  final String? ownerName;
  final bool writable;
  final bool artworkOverridden;

  /// 空＝不啟用自動刷新。
  final int? refreshIntervalHours;
  final DateTime? lastRefreshedAt;
}

/// 歌單裡的一首。`remote_item_id` 空、`seen_generation` 為 0（下一次完整刷新以曲目鍵比對）。
@immutable
final class ImportPlaylistEntry {
  const ImportPlaylistEntry({required this.track, this.unavailable = false});

  final TrackKeyParts track;

  /// 遠端說這一項已失效（只有匯入歌單會是真）。
  final bool unavailable;
}

/// 佇列的一個位置。
@immutable
final class ImportQueueEntry {
  const ImportQueueEntry({required this.track, this.shuffleRank});

  final TrackKeyParts track;

  /// 隨機開啟時這個位置的名次；沒開隨機為空。
  final int? shuffleRank;
}

/// 播放歷史的一筆。
@immutable
final class ImportHistoryEntry {
  const ImportHistoryEntry({required this.track, required this.playedAt});

  final TrackKeyParts track;
  final DateTime playedAt;
}

/// 搜尋歷史的一筆。
@immutable
final class ImportSearchHistoryEntry {
  const ImportSearchHistoryEntry({
    required this.query,
    required this.searchedAt,
  });

  final String query;
  final DateTime searchedAt;
}

/// 電台的一筆；`sort_order` 是它在清單裡的位置，直播狀態不匯入（之後由排程查）。
@immutable
final class ImportRadioStation {
  const ImportRadioStation({
    required this.pluginId,
    required this.roomId,
    required this.title,
    required this.addedAt,
    this.hostName,
    this.artwork = const [],
  });

  final String pluginId;
  final String roomId;
  final String title;
  final String? hostName;
  final List<TrackArtwork> artwork;
  final DateTime addedAt;
}

/// `track_origins` 的一列：外部匯入的曲目的原始平台與 id。
@immutable
final class ImportTrackOrigin {
  const ImportTrackOrigin({
    required this.track,
    required this.originPluginId,
    required this.originId,
  });

  final TrackKeyParts track;
  final String originPluginId;
  final String originId;
}
