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

  /// 按日期范围获取历史记录
  Future<List<PlayHistory>> getHistoryByDateRange(
    DateTime start,
    DateTime end, {
    Set<SourceType>? sourceTypes,
  }) async {
    var query = _isar.playHistorys
        .where()
        .filter()
        .playedAtBetween(start, end);

    if (sourceTypes != null && sourceTypes.isNotEmpty) {
      query = query.anyOf(
        sourceTypes.toList(),
        (q, type) => q.sourceTypeEqualTo(type),
      );
    }

    return query.sortByPlayedAtDesc().findAll();
  }

  /// 按音源类型获取历史记录
  Future<List<PlayHistory>> getHistoryBySource(
    SourceType sourceType, {
    int offset = 0,
    int limit = 50,
  }) async {
    return _isar.playHistorys
        .where()
        .filter()
        .sourceTypeEqualTo(sourceType)
        .sortByPlayedAtDesc()
        .offset(offset)
        .limit(limit)
        .findAll();
  }

  /// 搜索历史记录（标题或艺术家）
  Future<List<PlayHistory>> searchHistory(
    String keyword, {
    Set<SourceType>? sourceTypes,
    int limit = 50,
  }) async {
    var query = _isar.playHistorys
        .where()
        .filter()
        .group((q) => q
            .titleContains(keyword, caseSensitive: false)
            .or()
            .artistContains(keyword, caseSensitive: false));

    if (sourceTypes != null && sourceTypes.isNotEmpty) {
      query = query.anyOf(
        sourceTypes.toList(),
        (q, type) => q.sourceTypeEqualTo(type),
      );
    }

    return query.sortByPlayedAtDesc().limit(limit).findAll();
  }

  /// 删除某首歌的所有播放记录
  Future<int> deleteAllForTrack(String trackKey) async {
    final all = await _isar.playHistorys.where().findAll();
    final toDelete = all.where((h) => h.trackKey == trackKey).map((h) => h.id).toList();
    
    await _isar.writeTxn(() async {
      await _isar.playHistorys.deleteAll(toDelete);
    });
    
    return toDelete.length;
  }

  /// 获取某首歌的播放次数（通过 trackKey）
  Future<int> getPlayCountByKey(String trackKey) async {
    final all = await _isar.playHistorys.where().findAll();
    return all.where((h) => h.trackKey == trackKey).length;
  }

  /// 获取播放历史统计
  Future<PlayHistoryStats> getHistoryStats() async {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final weekStart = todayStart.subtract(Duration(days: now.weekday - 1));
    
    final all = await _isar.playHistorys.where().findAll();
    
    int todayCount = 0;
    int todayDurationMs = 0;
    int weekCount = 0;
    int weekDurationMs = 0;
    int totalDurationMs = 0;
    
    for (final h in all) {
      final duration = h.durationMs ?? 0;
      totalDurationMs += duration;
      
      if (h.playedAt.isAfter(todayStart)) {
        todayCount++;
        todayDurationMs += duration;
      }
      if (h.playedAt.isAfter(weekStart)) {
        weekCount++;
        weekDurationMs += duration;
      }
    }
    
    return PlayHistoryStats(
      totalCount: all.length,
      todayCount: todayCount,
      weekCount: weekCount,
      totalDurationMs: totalDurationMs,
      todayDurationMs: todayDurationMs,
      weekDurationMs: weekDurationMs,
    );
  }

  /// 综合查询历史记录
  Future<List<PlayHistory>> queryHistory({
    Set<SourceType>? sourceTypes,
    DateTime? startDate,
    DateTime? endDate,
    String? searchKeyword,
    HistorySortOrder sortOrder = HistorySortOrder.timeDesc,
    int offset = 0,
    int limit = 50,
  }) async {
    // 基础查询
    var records = await _isar.playHistorys.where().findAll();
    
    // 筛选音源
    if (sourceTypes != null && sourceTypes.isNotEmpty) {
      records = records.where((h) => sourceTypes.contains(h.sourceType)).toList();
    }
    
    // 筛选日期范围
    if (startDate != null) {
      records = records.where((h) => h.playedAt.isAfter(startDate) || h.playedAt.isAtSameMomentAs(startDate)).toList();
    }
    if (endDate != null) {
      final endOfDay = DateTime(endDate.year, endDate.month, endDate.day, 23, 59, 59);
      records = records.where((h) => h.playedAt.isBefore(endOfDay)).toList();
    }
    
    // 搜索关键词
    if (searchKeyword != null && searchKeyword.isNotEmpty) {
      final lower = searchKeyword.toLowerCase();
      records = records.where((h) =>
          h.title.toLowerCase().contains(lower) ||
          (h.artist?.toLowerCase().contains(lower) ?? false)).toList();
    }
    
    // 排序
    switch (sortOrder) {
      case HistorySortOrder.timeDesc:
        records.sort((a, b) => b.playedAt.compareTo(a.playedAt));
        break;
      case HistorySortOrder.timeAsc:
        records.sort((a, b) => a.playedAt.compareTo(b.playedAt));
        break;
      case HistorySortOrder.playCount:
        // 需要计算每首歌的播放次数
        final countMap = <String, int>{};
        for (final h in records) {
          countMap[h.trackKey] = (countMap[h.trackKey] ?? 0) + 1;
        }
        records.sort((a, b) => (countMap[b.trackKey] ?? 0).compareTo(countMap[a.trackKey] ?? 0));
        break;
      case HistorySortOrder.duration:
        records.sort((a, b) => (b.durationMs ?? 0).compareTo(a.durationMs ?? 0));
        break;
    }
    
    // 分页
    if (offset >= records.length) return [];
    final end = (offset + limit).clamp(0, records.length);
    return records.sublist(offset, end);
  }

  /// 按日期分组获取历史记录
  Future<Map<DateTime, List<PlayHistory>>> getHistoryGroupedByDate({
    Set<SourceType>? sourceTypes,
    String? searchKeyword,
    HistorySortOrder sortOrder = HistorySortOrder.timeDesc,
  }) async {
    final records = await queryHistory(
      sourceTypes: sourceTypes,
      searchKeyword: searchKeyword,
      sortOrder: sortOrder,
      limit: 1000, // 获取所有记录用于分组
    );
    
    final grouped = <DateTime, List<PlayHistory>>{};
    for (final h in records) {
      final date = DateTime(h.playedAt.year, h.playedAt.month, h.playedAt.day);
      grouped.putIfAbsent(date, () => []).add(h);
    }
    
    return grouped;
  }
}

/// 播放历史统计数据
class PlayHistoryStats {
  final int totalCount;
  final int todayCount;
  final int weekCount;
  final int totalDurationMs;
  final int todayDurationMs;
  final int weekDurationMs;

  const PlayHistoryStats({
    required this.totalCount,
    required this.todayCount,
    required this.weekCount,
    required this.totalDurationMs,
    required this.todayDurationMs,
    required this.weekDurationMs,
  });

  String get formattedTotalDuration => _formatDuration(totalDurationMs);
  String get formattedTodayDuration => _formatDuration(todayDurationMs);
  String get formattedWeekDuration => _formatDuration(weekDurationMs);

  String _formatDuration(int ms) {
    final duration = Duration(milliseconds: ms);
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    
    if (hours > 0) {
      return '$hours 小時 $minutes 分鐘';
    }
    return '$minutes 分鐘';
  }
}

/// 历史记录排序方式
enum HistorySortOrder {
  timeDesc,   // 时间倒序（最新优先）
  timeAsc,    // 时间正序（最早优先）
  playCount,  // 播放次数
  duration,   // 歌曲时长
}