import 'package:isar/isar.dart';

import '../models/lyrics_match.dart';

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
