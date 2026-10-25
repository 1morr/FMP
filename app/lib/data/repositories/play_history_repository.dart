import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';

import 'package:fmp/data/database/app_database.dart';
import 'package:fmp/data/database/converters.dart';
import 'package:fmp/data/repositories/tracks_repository.dart';
import 'package:fmp/domain/track_info.dart';

/// 播放歷史的一筆：哪一首、什麼時候開始聽的。[id] 給「從歷史移除」用。
@immutable
final class PlayHistoryEntry {
  const PlayHistoryEntry({
    required this.id,
    required this.playedAt,
    required this.track,
    this.playCount = 1,
  });

  final int id;

  /// UTC。
  final DateTime playedAt;
  final TrackInfo track;

  /// 這首（在目前的篩選條件下）播過幾次。只有 [HistorySort.mostPlayed] 會大於 1：那時一首
  /// 曲目一列，[id] 與 [playedAt] 是它最後一次播放。
  final int playCount;

  @override
  bool operator ==(Object other) =>
      other is PlayHistoryEntry &&
      other.id == id &&
      other.playedAt == playedAt &&
      other.track == track &&
      other.playCount == playCount;

  @override
  int get hashCode => Object.hash(id, playedAt, track, playCount);

  @override
  String toString() => 'PlayHistoryEntry(id: $id, playedAt: $playedAt)';
}

/// 歷史清單的排序。
enum HistorySort {
  /// 最近播放的在前。
  newest,

  /// 最早播放的在前。
  oldest,

  /// 依曲目分組，播放次數多的在前（同次數時最近播放的在前）。
  mostPlayed,
}

/// 一段期間的統計：播放次數與總時長（沒有時長的曲目算 0）。
@immutable
final class HistoryPeriodStats {
  const HistoryPeriodStats({required this.count, required this.duration});

  final int count;
  final Duration duration;

  @override
  bool operator ==(Object other) =>
      other is HistoryPeriodStats &&
      other.count == count &&
      other.duration == duration;

  @override
  int get hashCode => Object.hash(count, duration);

  @override
  String toString() => 'HistoryPeriodStats($count, $duration)';
}

/// 歷史頁頂端的統計：今天、本週（週一起算）與全部，日界與週界依裝置的本地時間。
@immutable
final class HistoryStats {
  const HistoryStats({
    required this.today,
    required this.week,
    required this.all,
  });

  final HistoryPeriodStats today;
  final HistoryPeriodStats week;
  final HistoryPeriodStats all;

  @override
  bool operator ==(Object other) =>
      other is HistoryStats &&
      other.today == today &&
      other.week == week &&
      other.all == all;

  @override
  int get hashCode => Object.hash(today, week, all);

  @override
  String toString() => 'HistoryStats($today, $week, $all)';
}

/// `play_history` 的存取（design §3.2、§7.8）：一次播放一列，曲目的顯示資料在
/// `tracks`。
final class PlayHistoryRepository {
  PlayHistoryRepository(this._database) : _tracks = TracksRepository(_database);

  final AppDatabase _database;
  final TracksRepository _tracks;

  /// 記一次播放：一個 transaction 先 upsert [track]，再插入一列，然後裁掉超過
  /// [limit] 筆的最舊列（每寫一筆就裁，design §7.8）。
  Future<void> record(
    TrackInfo track, {
    required DateTime playedAt,
    required int limit,
  }) => _database.transaction(() async {
    await _tracks.upsert([track]);
    await _database
        .into(_database.playHistoryTable)
        .insert(
          PlayHistoryTableCompanion.insert(
            trackKey: '${track.key}',
            playedAt: playedAt.toUtc(),
          ),
        );
    await _trim(limit);
  });

  /// 讀 [limit] 筆，從第 [offset] 筆起，附曲目的顯示資料。條件可以疊加：[source]（插件
  /// id）、[day]（本地時間的那一天）、[query]（曲名、作者或分 P 的影片標題含這段文字；
  /// SQLite 的 `LIKE`，只有 ASCII 不分大小寫）。
  ///
  /// [sort] 是 [HistorySort.newest]（預設，同一毫秒的新的在前）時走 `played_at` 的索引掃
  /// 描；[HistorySort.mostPlayed] 依曲目分組、每首一列（最後一次播放加次數），整份歷史
  /// 掃一遍再排序（上限 5 萬筆）。
  Future<List<PlayHistoryEntry>> page({
    required int limit,
    int offset = 0,
    String? source,
    DateTime? day,
    String? query,
    HistorySort sort = HistorySort.newest,
  }) async {
    final (where, variables) = _where(source: source, day: day, query: query);
    const from =
        'FROM play_history h JOIN tracks t ON t.track_key = h.track_key';
    final sql = switch (sort) {
      HistorySort.newest =>
        'SELECT h.id AS id, h.played_at AS played_at, '
            'h.track_key AS track_key, 1 AS cnt $from $where '
            'ORDER BY h.played_at DESC, h.id DESC LIMIT ? OFFSET ?',
      HistorySort.oldest =>
        'SELECT h.id AS id, h.played_at AS played_at, '
            'h.track_key AS track_key, 1 AS cnt $from $where '
            'ORDER BY h.played_at ASC, h.id ASC LIMIT ? OFFSET ?',
      HistorySort.mostPlayed =>
        'WITH ranked AS (SELECT h.id AS id, h.played_at AS played_at, '
            'h.track_key AS track_key, '
            'ROW_NUMBER() OVER (PARTITION BY h.track_key '
            'ORDER BY h.played_at DESC, h.id DESC) AS rn, '
            'COUNT(*) OVER (PARTITION BY h.track_key) AS cnt '
            '$from $where) '
            'SELECT id, played_at, track_key, cnt FROM ranked WHERE rn = 1 '
            'ORDER BY cnt DESC, played_at DESC, id DESC LIMIT ? OFFSET ?',
    };
    final rows = await _database
        .customSelect(
          sql,
          variables: [
            ...variables,
            Variable.withInt(limit),
            Variable.withInt(offset),
          ],
        )
        .get();
    if (rows.isEmpty) return const [];
    final keys = {for (final row in rows) row.read<String>('track_key')};
    final byKey = {
      for (final row in await (_database.select(
        _database.tracksTable,
      )..where((t) => t.trackKey.isIn(keys))).get())
        row.trackKey: TracksRepository.toTrackInfo(row),
    };
    return [
      for (final row in rows)
        PlayHistoryEntry(
          id: row.read<int>('id'),
          playedAt: const EpochMillisecondsConverter().fromSql(
            row.read<int>('played_at'),
          ),
          track: byKey[row.read<String>('track_key')]!,
          playCount: row.read<int>('cnt'),
        ),
    ];
  }

  /// 今天、本週、全部的播放次數與總時長，一個查詢。[now] 依裝置的本地時間定日界；週從週一
  /// 起算。正好在午夜的播放算新的一天。
  Future<HistoryStats> stats(DateTime now) async {
    final local = now.toLocal();
    final today = DateTime(local.year, local.month, local.day);
    final week = DateTime(
      today.year,
      today.month,
      today.day - (today.weekday - DateTime.monday),
    );
    final row = await _database
        .customSelect(
          'SELECT COUNT(*) AS all_count, '
          'COALESCE(SUM(COALESCE(t.duration_ms, 0)), 0) AS all_ms, '
          'COALESCE(SUM(h.played_at >= ?1), 0) AS week_count, '
          'COALESCE(SUM(CASE WHEN h.played_at >= ?1 '
          'THEN COALESCE(t.duration_ms, 0) ELSE 0 END), 0) AS week_ms, '
          'COALESCE(SUM(h.played_at >= ?2), 0) AS today_count, '
          'COALESCE(SUM(CASE WHEN h.played_at >= ?2 '
          'THEN COALESCE(t.duration_ms, 0) ELSE 0 END), 0) AS today_ms '
          'FROM play_history h JOIN tracks t ON t.track_key = h.track_key',
          variables: [
            Variable.withInt(week.millisecondsSinceEpoch),
            Variable.withInt(today.millisecondsSinceEpoch),
          ],
        )
        .getSingle();
    HistoryPeriodStats period(String prefix) => HistoryPeriodStats(
      count: row.read<int>('${prefix}_count'),
      duration: Duration(milliseconds: row.read<int>('${prefix}_ms')),
    );
    return HistoryStats(
      today: period('today'),
      week: period('week'),
      all: period('all'),
    );
  }

  /// `page` 的 WHERE 子句與它的變數（`h` 是歷史、`t` 是曲目）。
  (String, List<Variable<Object>>) _where({
    String? source,
    DateTime? day,
    String? query,
  }) {
    final clauses = <String>[];
    final variables = <Variable<Object>>[];
    if (source != null) {
      clauses.add('t.source_type_id = ?');
      variables.add(Variable.withString(source));
    }
    if (day != null) {
      final local = day.toLocal();
      final start = DateTime(local.year, local.month, local.day);
      final end = DateTime(local.year, local.month, local.day + 1);
      clauses.add('h.played_at >= ? AND h.played_at < ?');
      variables
        ..add(Variable.withInt(start.millisecondsSinceEpoch))
        ..add(Variable.withInt(end.millisecondsSinceEpoch));
    }
    final text = query?.trim();
    if (text != null && text.isNotEmpty) {
      // 使用者打的 `%`、`_` 是字面，不是萬用字元。
      final escaped = text.replaceAllMapped(
        RegExp(r'[\\%_]'),
        (match) => '\\${match[0]}',
      );
      clauses.add(
        r"(t.title LIKE ? ESCAPE '\' OR t.uploader LIKE ? ESCAPE '\' "
        r"OR t.parent_title LIKE ? ESCAPE '\')",
      );
      for (var i = 0; i < 3; i++) {
        variables.add(Variable.withString('%$escaped%'));
      }
    }
    return (clauses.isEmpty ? '' : 'WHERE ${clauses.join(' AND ')}', variables);
  }

  /// 歷史表有任何變動（新增、刪除、清除、裁切）時發出，給歷史頁重讀。聽的是
  /// drift 的 `tableUpdates`、不是 `watch()` 查詢：後者在最後一個 listener 離開時排
  /// 計時器，widget 測試結束時算成沒跑完的計時器。
  Stream<void> changes() => _database
      .tableUpdates(TableUpdateQuery.onTable(_database.playHistoryTable))
      .map((_) {});

  /// 刪掉一筆（依 [id]）；其他筆與同一首曲目的其他紀錄不動。
  Future<void> delete(int id) => (_database.delete(
    _database.playHistoryTable,
  )..where((t) => t.id.equals(id))).go();

  /// 刪掉同一首曲目（[trackKey] 是 `TrackKey.format` 的輸出）的所有紀錄，回傳刪了幾筆。
  Future<int> deleteAllForTrack(String trackKey) => (_database.delete(
    _database.playHistoryTable,
  )..where((t) => t.trackKey.equals(trackKey))).go();

  /// 刪掉 [ids] 這幾筆，回傳刪了幾筆。
  Future<int> deleteMany(Iterable<int> ids) => _database.transaction(() async {
    final all = ids.toList();
    var deleted = 0;
    // 分批：SQLite 的變數個數有上限。
    for (var i = 0; i < all.length; i += 500) {
      final chunk = all.sublist(i, (i + 500).clamp(0, all.length));
      deleted += await (_database.delete(
        _database.playHistoryTable,
      )..where((t) => t.id.isIn(chunk))).go();
    }
    return deleted;
  });

  /// 清除全部歷史。曲目的顯示資料留給孤兒清理。
  Future<void> clear() => _database.delete(_database.playHistoryTable).go();

  /// 只留最新的 [limit] 筆（改小保留筆數時呼叫）。
  Future<void> trimTo(int limit) => _trim(limit);

  Future<void> _trim(int limit) => _database.customUpdate(
    'DELETE FROM play_history WHERE id NOT IN '
    '(SELECT id FROM play_history ORDER BY played_at DESC, id DESC LIMIT ?)',
    variables: [Variable.withInt(limit)],
    updates: {_database.playHistoryTable},
    updateKind: UpdateKind.delete,
  );
}
