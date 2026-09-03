import 'package:isar_community/isar.dart';

import '../models/lyrics_match.dart';
import '../models/play_history.dart';
import '../models/playlist.dart';
import '../models/radio_station.dart';
import '../models/search_history.dart';
import '../models/settings.dart';
import '../models/track.dart';

/// 備份子系統的 Isar 存取。
///
/// `BackupService` 負責備份格式的解析與組裝，資料庫進出走這裡 —— 跟其他
/// service 一樣，它不該自己拿著 `Isar` 實例（見 `lib/data/AGENTS.md`）。
class BackupRepository {
  BackupRepository(this._isar);

  final Isar _isar;

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
}
