import 'package:isar/isar.dart';

import '../models/play_history.dart';
import '../models/track.dart';

/// 播放历史仓库
class PlayHistoryRepository {
  final Isar _isar;

  PlayHistoryRepository(this._isar);

  /// 最大历史记录数量
  static const int maxHistoryCount = 1000;

  /// 记录播放历史
  /// 每次播放都会新增一条记录（用于统计播放次数）
  Future<void> addHistory(Track track) async {
    final history = PlayHistory.fromTrack(track);
    await _isar.writeTxn(() async {
      await _isar.playHistorys.put(history);

      // 清理超出限制的旧记录
      final count = await _isar.playHistorys.count();
      if (count > maxHistoryCount) {
        final toDelete = count - maxHistoryCount;
        final oldRecords = await _isar.playHistorys
            .where()
            .sortByPlayedAt()
            .limit(toDelete)
            .findAll();
        await _isar.playHistorys
            .deleteAll(oldRecords.map((e) => e.id).toList());
      }
    });
  }

  /// 获取歌曲播放次数
  Future<int> getPlayCount(String sourceId, SourceType sourceType, {int? cid}) async {
    final trackKey = cid != null
        ? '${sourceType.name}:$sourceId:$cid'
        : '${sourceType.name}:$sourceId';
    
    final all = await _isar.playHistorys.where().findAll();
    return all.where((h) => h.trackKey == trackKey).length;
  }

  /// 获取播放次数最多的歌曲（去重）
  Future<List<({PlayHistory history, int count})>> getMostPlayed({int limit = 10}) async {
    final all = await _isar.playHistorys.where().findAll();
    
    // 按 trackKey 分组统计
    final countMap = <String, ({PlayHistory history, int count})>{};
    for (final h in all) {
      final key = h.trackKey;
      if (countMap.containsKey(key)) {
        countMap[key] = (history: countMap[key]!.history, count: countMap[key]!.count + 1);
      } else {
        countMap[key] = (history: h, count: 1);
      }
    }
    
    // 按播放次数排序
    final sorted = countMap.values.toList()
      ..sort((a, b) => b.count.compareTo(a.count));
    
    return sorted.take(limit).toList();
  }

  /// 获取最近播放历史（包含重复）
  Future<List<PlayHistory>> getRecentHistory({int limit = 20}) async {
    return _isar.playHistorys
        .where()
        .sortByPlayedAtDesc()
        .limit(limit)
        .findAll();
  }

  /// 获取最近播放历史（去重，每首歌只显示最新一条）
  Future<List<PlayHistory>> getRecentHistoryDistinct({int limit = 10}) async {
    final all = await _isar.playHistorys
        .where()
        .sortByPlayedAtDesc()
        .findAll();
    
    // 按 trackKey 去重，保留最新的记录
    final seen = <String>{};
    final result = <PlayHistory>[];
    
    for (final h in all) {
      if (!seen.contains(h.trackKey)) {
        seen.add(h.trackKey);
        result.add(h);
        if (result.length >= limit) break;
      }
    }
    
    return result;
  }

  /// 获取所有播放历史（分页）
  Future<List<PlayHistory>> getAllHistory({
    int offset = 0,
    int limit = 50,
  }) async {
    return _isar.playHistorys
        .where()
        .sortByPlayedAtDesc()
        .offset(offset)
        .limit(limit)
        .findAll();
  }

  /// 获取播放历史总数
  Future<int> getHistoryCount() async {
    return _isar.playHistorys.count();
  }

  /// 删除单条历史记录
  Future<void> deleteHistory(int id) async {
    await _isar.writeTxn(() async {
      await _isar.playHistorys.delete(id);
    });
  }

  /// 清空所有播放历史
  Future<void> clearAllHistory() async {
    await _isar.writeTxn(() async {
      await _isar.playHistorys.clear();
    });
  }

  /// 监听播放历史变化
  Stream<void> watchHistory() {
    return _isar.playHistorys.watchLazy();
  }
}
