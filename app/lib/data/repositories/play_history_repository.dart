import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';

import 'package:fmp/data/database/app_database.dart';
import 'package:fmp/data/repositories/tracks_repository.dart';
import 'package:fmp/domain/track_info.dart';

/// 播放歷史的一筆：哪一首、什麼時候開始聽的。[id] 給「從歷史移除」用。
@immutable
final class PlayHistoryEntry {
  const PlayHistoryEntry({
    required this.id,
    required this.playedAt,
    required this.track,
  });

  final int id;

  /// UTC。
  final DateTime playedAt;
  final TrackInfo track;

  @override
  bool operator ==(Object other) =>
      other is PlayHistoryEntry &&
      other.id == id &&
      other.playedAt == playedAt &&
      other.track == track;

  @override
  int get hashCode => Object.hash(id, playedAt, track);

  @override
  String toString() => 'PlayHistoryEntry(id: $id, playedAt: $playedAt)';
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

  /// 依時間倒序（同一毫秒的新的在前）讀 [limit] 筆，從第 [offset] 筆起，附曲目的
  /// 顯示資料。`played_at` 的索引讓這是索引掃描，不讀整張表。
  Future<List<PlayHistoryEntry>> page({
    required int limit,
    int offset = 0,
  }) async {
    final history = _database.playHistoryTable;
    final tracks = _database.tracksTable;
    final query =
        _database.select(history).join([
            innerJoin(tracks, tracks.trackKey.equalsExp(history.trackKey)),
          ])
          ..orderBy([
            OrderingTerm.desc(history.playedAt),
            OrderingTerm.desc(history.id),
          ])
          ..limit(limit, offset: offset);
    return [
      for (final row in await query.get())
        PlayHistoryEntry(
          id: row.readTable(history).id,
          playedAt: row.readTable(history).playedAt,
          track: TracksRepository.toTrackInfo(row.readTable(tracks)),
        ),
    ];
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
