import 'package:clock/clock.dart';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';

import 'package:fmp/data/database/app_database.dart';
import 'package:fmp/data/repositories/tracks_repository.dart';
import 'package:fmp/domain/loop_mode.dart';
import 'package:fmp/domain/track_info.dart';

/// `player_state` 那一列（design §3.2）。音量與靜音隨佇列存在這裡，不是設定；
/// 速度不持久化。
@immutable
final class PlayerState {
  const PlayerState({
    required this.currentPosition,
    required this.position,
    required this.loopMode,
    required this.shuffleEnabled,
    required this.volume,
    required this.muted,
  });

  /// 佇列目前這首的位置；佇列是空的時為 `null`。
  final int? currentPosition;

  /// 目前這首播到哪裡。
  final Duration position;
  final LoopMode loopMode;
  final bool shuffleEnabled;

  /// 0–1；靜音時是取消靜音後回到的值。
  final double volume;
  final bool muted;

  @override
  bool operator ==(Object other) =>
      other is PlayerState &&
      other.currentPosition == currentPosition &&
      other.position == position &&
      other.loopMode == loopMode &&
      other.shuffleEnabled == shuffleEnabled &&
      other.volume == volume &&
      other.muted == muted;

  @override
  int get hashCode => Object.hash(
    currentPosition,
    position,
    loopMode,
    shuffleEnabled,
    volume,
    muted,
  );

  @override
  String toString() =>
      'PlayerState(currentPosition: $currentPosition, position: $position, '
      'loopMode: $loopMode, shuffleEnabled: $shuffleEnabled, '
      'volume: $volume, muted: $muted)';
}

/// 佇列的每個位置與它的隨機名次（沒開隨機時全是 `null`）；兩個清單等長，依位置
/// 排好。
@immutable
final class StoredQueue {
  const StoredQueue({required this.entries, required this.shuffleRanks});

  static const empty = StoredQueue(entries: [], shuffleRanks: []);

  final List<TrackInfo> entries;
  final List<int?> shuffleRanks;
}

/// 佇列結構的一次編輯：把位置 `[from, from + removed)` 的列換成 [inserted]，其後
/// 的列平移 `inserted.length - removed`。插入、移除、移動、整份取代都可以寫成它。
@immutable
final class QueueRangeEdit {
  const QueueRangeEdit({
    required this.from,
    required this.removed,
    required this.inserted,
  });

  final int from;
  final int removed;
  final List<TrackInfo> inserted;
}

/// `queue_entries` 與 `player_state` 的存取（design §3.2）。
///
/// 佇列以差量寫入：一個 transaction 只動受影響的列。主鍵是位置，位移時先把受影響
/// 的列改成負值再改回，避開逐列檢查主鍵造成的衝突。
final class QueueRepository {
  QueueRepository(this._database) : _tracks = TracksRepository(_database);

  final AppDatabase _database;
  final TracksRepository _tracks;

  /// 單列的主鍵；表上的 CHECK 只允許這個值。
  static const _rowId = 1;

  /// 讀回整份佇列。位置不是 0..n-1 連續（資料壞了）時拋 [FormatException]。
  Future<StoredQueue> readQueue() async {
    final entries = _database.queueEntriesTable;
    final tracks = _database.tracksTable;
    final rows = await (_database.select(entries).join([
      innerJoin(tracks, tracks.trackKey.equalsExp(entries.trackKey)),
    ])..orderBy([OrderingTerm.asc(entries.position)])).get();
    final infos = <TrackInfo>[];
    final ranks = <int?>[];
    for (final (index, joined) in rows.indexed) {
      final entry = joined.readTable(entries);
      if (entry.position != index) {
        throw FormatException(
          'Queue positions are not contiguous in the database',
          '${entry.position} at $index',
        );
      }
      infos.add(_toTrackInfo(joined.readTable(tracks)));
      ranks.add(entry.shuffleRank);
    }
    return StoredQueue(entries: infos, shuffleRanks: ranks);
  }

  /// 讀播放狀態；還沒存過時為 `null`。
  Future<PlayerState?> readPlayerState() async {
    final row = await (_database.select(
      _database.playerStateTable,
    )..where((t) => t.id.equals(_rowId))).getSingleOrNull();
    if (row == null) return null;
    return PlayerState(
      currentPosition: row.currentPosition,
      position: Duration(milliseconds: row.positionMs),
      loopMode: row.loopMode,
      shuffleEnabled: row.shuffleEnabled,
      volume: row.volume,
      muted: row.muted,
    );
  }

  /// 一個 transaction：套用 [edit]（有的話；被插入的曲目先 upsert 進 `tracks`，
  /// 新列沒有隨機名次）、改 [shuffleRanks]（位置 → 名次，`null` 清掉，位置是套用
  /// [edit] 之後的）、寫 [player]。
  Future<void> write({
    QueueRangeEdit? edit,
    Map<int, int?> shuffleRanks = const {},
    required PlayerState player,
  }) => _database.transaction(() async {
    if (edit != null) await _applyEdit(edit);
    if (shuffleRanks.isNotEmpty) await _writeRanks(shuffleRanks);
    await _database
        .into(_database.playerStateTable)
        .insertOnConflictUpdate(
          PlayerStateTableCompanion(
            id: const Value(_rowId),
            currentPosition: Value(player.currentPosition),
            positionMs: Value(player.position.inMilliseconds),
            loopMode: Value(player.loopMode),
            shuffleEnabled: Value(player.shuffleEnabled),
            volume: Value(player.volume),
            muted: Value(player.muted),
            updatedAt: Value(clock.now().toUtc()),
          ),
        );
  });

  /// 清掉佇列與播放狀態（讀回來的資料壞了、不能恢復時）。
  Future<void> reset() => _database.transaction(() async {
    await _database.delete(_database.queueEntriesTable).go();
    await _database.delete(_database.playerStateTable).go();
  });

  Future<void> _applyEdit(QueueRangeEdit edit) async {
    final entries = _database.queueEntriesTable;
    await _tracks.upsert(edit.inserted);
    if (edit.removed > 0) {
      await (_database.delete(entries)..where(
            (t) =>
                t.position.isBiggerOrEqualValue(edit.from) &
                t.position.isSmallerThanValue(edit.from + edit.removed),
          ))
          .go();
    }
    final delta = edit.inserted.length - edit.removed;
    if (delta != 0) {
      // 平移其後的列：先改成負值（彼此不撞、也不撞既有的），再改回來。
      await _database.customUpdate(
        'UPDATE queue_entries SET position = -(position + ?) - 1 '
        'WHERE position >= ?',
        variables: [
          Variable.withInt(delta),
          Variable.withInt(edit.from + edit.removed),
        ],
        updates: {entries},
        updateKind: UpdateKind.update,
      );
      await _database.customUpdate(
        'UPDATE queue_entries SET position = -position - 1 WHERE position < 0',
        updates: {entries},
        updateKind: UpdateKind.update,
      );
    }
    if (edit.inserted.isNotEmpty) {
      await _database.batch(
        (batch) => batch.insertAll(entries, [
          for (final (index, track) in edit.inserted.indexed)
            QueueEntriesTableCompanion.insert(
              position: Value(edit.from + index),
              trackKey: '${track.key}',
            ),
        ]),
      );
    }
  }

  Future<void> _writeRanks(Map<int, int?> ranks) => _database.batch(
    (batch) => ranks.forEach((position, rank) {
      batch.update(
        _database.queueEntriesTable,
        QueueEntriesTableCompanion(shuffleRank: Value(rank)),
        where: (t) => t.position.equals(position),
      );
    }),
  );

  static TrackInfo _toTrackInfo(TrackRow row) => TrackInfo(
    sourceTypeId: row.sourceTypeId,
    sourceId: row.sourceId,
    cid: row.cid,
    title: row.title,
    uploader: row.uploader,
    duration: switch (row.durationMs) {
      final ms? => Duration(milliseconds: ms),
      null => null,
    },
    artwork: TracksRepository.decodeArtwork(row.artworkJson),
  );
}
