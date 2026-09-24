import 'package:isar_community/isar.dart';

import 'package:fmp/data/models/lyrics_match.dart';
import 'package:fmp/data/models/track.dart';
import 'package:fmp/data/models/track_key.dart';

/// 歌词匹配仓库
class LyricsRepository {
  final Isar _isar;

  LyricsRepository(this._isar);

  /// 根据 trackUniqueKey 获取匹配记录
  Future<LyricsMatch?> getByTrackKey(String trackUniqueKey) async {
    return _isar.lyricsMatchs
        .where()
        .trackUniqueKeyEqualTo(trackUniqueKey)
        .findFirst();
  }

  /// 监听 trackUniqueKey 的匹配记录变化
  Stream<LyricsMatch?> watchByTrackKey(String trackUniqueKey) {
    return _isar.lyricsMatchs
        .where()
        .trackUniqueKeyEqualTo(trackUniqueKey)
        .watch(fireImmediately: true)
        .map((matches) => matches.isEmpty ? null : matches.first);
  }

  /// 保存匹配记录（replace: true 自动覆盖同 trackUniqueKey 的旧记录）
  Future<void> save(LyricsMatch match) async {
    await _isar.writeTxn(() async {
      await _isar.lyricsMatchs.put(match);
    });
  }

  /// 删除匹配记录
  Future<void> delete(String trackUniqueKey) async {
    await _isar.writeTxn(() async {
      await _isar.lyricsMatchs
          .where()
          .trackUniqueKeyEqualTo(trackUniqueKey)
          .deleteAll();
    });
  }

  /// 更新偏移量
  Future<void> updateOffset(String trackUniqueKey, int offsetMs) async {
    final match = await getByTrackKey(trackUniqueKey);
    if (match == null) return;

    match.offsetMs = offsetMs;
    await _isar.writeTxn(() async {
      await _isar.lyricsMatchs.put(match);
    });
  }
}

/// 曲目補上 cid 之後，把兩段式鍵下的歌詞匹配改到三段式鍵。必須在寫入交易裡
/// 呼叫。
///
/// cid 是 [Track.uniqueKey] 的一段。搜尋與排行榜來的 Bilibili 曲目一開始沒有
/// cid，v1.10.0 起第一次播放才回填，鍵從兩段變三段；在那之前存的匹配（手動選
/// 的歌詞、調過的 offset）就再也讀不到（ADR 0005）。
///
/// 只在兩段式鍵確定已經沒人用、而且只指向一個 cid 時才改：
/// - 同一支影片還有沒補 cid 的列，那一列讀的就是兩段式鍵；
/// - 對應到好幾個 cid 是分 P，分不出匹配屬於哪一 P。
///
/// 三段式鍵已經有匹配時不動：那是補上 cid 之後才存的，比舊的新。
/// `trackUniqueKey` 是 `replace: true` 的唯一索引，直接寫過去會把它蓋掉。
Future<void> relinkLyricsMatchToCidKeyInTxn(
  Isar isar, {
  required String sourceType,
  required String sourceId,
}) async {
  final groupKey = TrackKey.formatGroup(sourceType, sourceId);
  final match = await isar.lyricsMatchs
      .where()
      .trackUniqueKeyEqualTo(groupKey)
      .findFirst();
  if (match == null) return;

  final rows = await isar.tracks
      .where()
      .sourceIdEqualTo(sourceId)
      .filter()
      .sourceTypeEqualTo(sourceType)
      .findAll();
  if (rows.isEmpty || rows.any((track) => track.cid == null)) return;
  final cids = rows.map((track) => track.cid!).toSet();
  if (cids.length != 1) return;

  final cidKey = TrackKey.format(sourceType, sourceId, cid: cids.single);
  final existing = await isar.lyricsMatchs
      .where()
      .trackUniqueKeyEqualTo(cidKey)
      .count();
  if (existing > 0) return;

  match.trackUniqueKey = cidKey;
  await isar.lyricsMatchs.put(match);
}
