import 'package:isar_community/isar.dart';

import '../models/lyrics_match.dart';
import '../models/play_history.dart';
import '../models/playlist.dart';
import '../models/radio_station.dart';
import '../models/search_history.dart';
import '../models/settings.dart';
import '../models/track.dart';
import 'playlist_mutation_repository.dart';

/// 一首待寫入的新歌曲，連同它在備份裡的 key。
///
/// key 要留到寫入階段才用得上：歌單記的是 key，而 id 是 `put` 之後才有的。
class BackupImportTrack {
  const BackupImportTrack({required this.uniqueKey, required this.track});

  final String uniqueKey;
  final Track track;
}

/// 一個待寫入的歌單。成員用 key 表示，寫入時才解析成 id。
class BackupImportPlaylist {
  const BackupImportPlaylist({
    required this.playlist,
    required this.trackKeys,
    required this.coverUrl,
    required this.hasCustomCover,
    required this.updatedAt,
  });

  final Playlist playlist;
  final List<String> trackKeys;

  /// `addTracksInTxn` 會依政策改寫封面與 `updatedAt`，這三個欄位是備份裡的
  /// 原值，寫完成員之後要蓋回去。
  final String? coverUrl;
  final bool hasCustomCover;
  final DateTime? updatedAt;
}

/// 匯入時要一次寫完的東西。
///
/// 解析、驗證與跳過判斷都已經在 `BackupService` 做完，這裡拿到的每一筆都是
/// 確定要寫的。
class BackupImportBatch {
  const BackupImportBatch({
    required this.existingTrackIdsByKey,
    required this.tracks,
    required this.playlists,
    required this.playHistory,
    required this.searchHistory,
    required this.radioStations,
    required this.lyricsMatches,
    required this.settings,
  });

  /// 資料庫裡已經有的歌曲，歌單成員可能指到這些。
  final Map<String, int> existingTrackIdsByKey;

  final List<BackupImportTrack> tracks;
  final List<BackupImportPlaylist> playlists;
  final List<PlayHistory> playHistory;
  final List<SearchHistory> searchHistory;
  final List<RadioStation> radioStations;
  final List<LyricsMatch> lyricsMatches;
  final Settings? settings;
}

/// 備份子系統的 Isar 存取。
///
/// `BackupService` 負責備份格式的解析與組裝，資料庫進出走這裡 —— 跟其他
/// service 一樣，它不該自己拿著 `Isar` 實例（見 `lib/data/AGENTS.md`）。
class BackupRepository {
  BackupRepository(this._isar, {PlaylistMutationRepository? mutations})
      : _mutations = mutations ?? PlaylistMutationRepository(isar: _isar);

  final Isar _isar;
  final PlaylistMutationRepository _mutations;

  // ==================== 匯出：整表讀取 ====================

  Future<List<Playlist>> allPlaylists() => _isar.playlists.where().findAll();

  Future<List<Track>> allTracks() => _isar.tracks.where().findAll();

  Future<List<PlayHistory>> allPlayHistory() =>
      _isar.playHistorys.where().findAll();

  Future<List<SearchHistory>> allSearchHistory() =>
      _isar.searchHistorys.where().findAll();

  Future<List<RadioStation>> allRadioStations() =>
      _isar.radioStations.where().findAll();

  Future<List<LyricsMatch>> allLyricsMatches() =>
      _isar.lyricsMatchs.where().findAll();

  /// 設定是單例列，id 固定為 0。
  Future<Settings?> settings() => _isar.settings.get(0);

  // ==================== 匯入：一筆交易 ====================

  /// 把整批倖存者寫進去，全部成功或一列都不留。
  ///
  /// 任何一步拋出，Isar 都會 abort 整筆交易（`isar_common.dart` 的
  /// `catch (e) { await txn.abort(); rethrow; }`），所以呼叫端不會看到半套資料。
  Future<void> writeImport(BackupImportBatch batch) {
    return _isar.writeTxn(() async {
      final trackIdsByKey = Map<String, int>.from(batch.existingTrackIdsByKey);
      // 只有這次新建的歌曲需要把備份裡的 updatedAt 蓋回去；既有歌曲不動。
      final importedUpdatedAt = <String, DateTime?>{};

      for (final entry in batch.tracks) {
        trackIdsByKey[entry.uniqueKey] = await _isar.tracks.put(entry.track);
        importedUpdatedAt[entry.uniqueKey] = entry.track.updatedAt;
      }

      for (final prepared in batch.playlists) {
        await _isar.playlists.put(prepared.playlist);

        final trackIds = [
          for (final key in prepared.trackKeys)
            if (trackIdsByKey[key] != null) trackIdsByKey[key]!,
        ];
        final tracks =
            (await _isar.tracks.getAll(trackIds)).whereType<Track>().toList();
        await _mutations.addTracksInTxn(prepared.playlist.id, tracks);

        await _restoreImportedTrackTimestamps(
          prepared.trackKeys,
          trackIdsByKey,
          importedUpdatedAt,
        );
        await _restorePlaylistPresentation(prepared);
      }

      if (batch.playHistory.isNotEmpty) {
        await _isar.playHistorys.putAll(batch.playHistory);
      }
      if (batch.searchHistory.isNotEmpty) {
        await _isar.searchHistorys.putAll(batch.searchHistory);
      }
      if (batch.radioStations.isNotEmpty) {
        await _isar.radioStations.putAll(batch.radioStations);
      }
      if (batch.lyricsMatches.isNotEmpty) {
        await _isar.lyricsMatchs.putAll(batch.lyricsMatches);
      }
      if (batch.settings != null) {
        await _isar.settings.put(batch.settings!);
      }
    });
  }

  /// 加歌會把 `updatedAt` 換成當下時間，備份裡的原值要補回去。
  Future<void> _restoreImportedTrackTimestamps(
    List<String> trackKeys,
    Map<String, int> trackIdsByKey,
    Map<String, DateTime?> importedUpdatedAt,
  ) async {
    final restored = <Track>[];
    for (final key in trackKeys) {
      final wanted = importedUpdatedAt[key];
      if (wanted == null) continue;
      final id = trackIdsByKey[key];
      if (id == null) continue;
      final track = await _isar.tracks.get(id);
      if (track == null || track.updatedAt == wanted) continue;
      track.updatedAt = wanted;
      restored.add(track);
    }
    if (restored.isNotEmpty) {
      await _isar.tracks.putAll(restored);
    }
  }

  /// 加歌也會依封面政策改寫歌單的封面與 `updatedAt`，同樣蓋回備份裡的值。
  Future<void> _restorePlaylistPresentation(
    BackupImportPlaylist prepared,
  ) async {
    final saved = await _isar.playlists.get(prepared.playlist.id);
    if (saved == null) return;

    final needsRestore = saved.coverUrl != prepared.coverUrl ||
        saved.hasCustomCover != prepared.hasCustomCover ||
        (prepared.updatedAt != null && saved.updatedAt != prepared.updatedAt);
    if (!needsRestore) return;

    saved
      ..coverUrl = prepared.coverUrl
      ..hasCustomCover = prepared.hasCustomCover;
    if (prepared.updatedAt != null) {
      saved.updatedAt = prepared.updatedAt!;
    }
    await _isar.playlists.put(saved);
  }
}
