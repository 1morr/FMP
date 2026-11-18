import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fmp/data/database.dart';
import 'package:fmp/domain/queue.dart';
import 'package:fmp/domain/track.dart';

/// 保存佇列的地方；沒有資料庫時是 null，不保存。
final queueStoreProvider = Provider<QueueStore?>(
  (ref) => switch (ref.watch(appDatabaseProvider)) {
    final database? => QueueStore(database),
    null => null,
  },
);

/// 上次關 App 時的佇列與目前那首播到哪裡。
class SavedQueue {
  const SavedQueue(this.queue, this.position);

  final Queue queue;

  /// 目前那首（[Queue.current]）播到哪裡；沒有目前那首時是零。
  final Duration position;
}

/// 佇列與進度存進資料庫、啟動時讀回（brief〈播放〉）。臨時播放不經這裡，
/// 存的是佇列本身。
class QueueStore {
  QueueStore(this._database);

  final AppDatabase _database;

  static const _stateId = 0;

  /// 讀回上次的佇列；沒存過時是 null。存的資料對不起來（例如檔案被改壞）
  /// 時丟例外，由呼叫的人另存一份再清掉（`app/storage.dart`）。
  Future<SavedQueue?> load() async {
    final state = await (_database.select(
      _database.queueStates,
    )..where((s) => s.id.equals(_stateId))).getSingleOrNull();
    if (state == null) return null;
    final rows = await (_database.select(
      _database.queueEntries,
    )..orderBy([(e) => OrderingTerm.asc(e.playOrder)])).get();
    final original = state.shuffled
        ? ([
            for (final row in rows)
              if (row.originalOrder != null) row,
          ]..sort((a, b) => a.originalOrder!.compareTo(b.originalOrder!)))
        : null;
    final queue = Queue.restore(
      entries: [
        for (final row in rows)
          QueueEntry(
            row.entryId,
            Track(
              ref: TrackRef(pluginId: row.pluginId, trackId: row.trackId),
              title: row.title,
              author: row.author,
              duration: switch (row.durationMs) {
                final ms? => Duration(milliseconds: ms),
                null => null,
              },
              coverUrl: row.coverUrl,
            ),
          ),
      ],
      currentEntryId: state.currentEntryId,
      nextEntryId: state.nextEntryId,
      repeat: state.repeat,
      original: original == null
          ? null
          : [for (final row in original) row.entryId],
    );
    return SavedQueue(
      queue,
      queue.current == null
          ? Duration.zero
          : Duration(milliseconds: state.positionMs),
    );
  }

  /// 清掉存的佇列（讀不回來、已另存一份之後）。
  Future<void> clear() => _database.transaction(() async {
    await _database.delete(_database.queueEntries).go();
    await _database.delete(_database.queueStates).go();
  });

  /// 存整個佇列與 [position]。[entriesChanged] 是 false 時只存目前那首、
  /// 播放模式與進度，不重寫每個位置。
  Future<void> save(
    Queue queue,
    Duration position, {
    bool entriesChanged = true,
  }) => _database.transaction(() async {
    if (entriesChanged) {
      await _database.delete(_database.queueEntries).go();
      final original = {
        for (final (i, id) in (queue.originalOrder ?? const <int>[]).indexed)
          id: i,
      };
      await _database.batch(
        (batch) => batch.insertAll(_database.queueEntries, [
          for (final (i, entry) in queue.entries.indexed)
            QueueEntriesCompanion.insert(
              entryId: Value(entry.id),
              playOrder: i,
              originalOrder: Value(original[entry.id]),
              pluginId: entry.track.ref.pluginId,
              trackId: entry.track.ref.trackId,
              title: entry.track.title,
              author: entry.track.author,
              durationMs: Value(entry.track.duration?.inMilliseconds),
              coverUrl: Value(entry.track.coverUrl),
            ),
        ]),
      );
    }
    await _database
        .into(_database.queueStates)
        .insertOnConflictUpdate(
          QueueStatesCompanion.insert(
            id: const Value(_stateId),
            currentEntryId: Value(queue.current?.id),
            nextEntryId: queue.nextEntryId,
            shuffled: queue.shuffled,
            repeat: queue.repeat,
            positionMs: position.inMilliseconds,
          ),
        );
  });

  /// 只存目前那首播到哪裡；還沒存過佇列時什麼都不做。
  Future<void> savePosition(Duration position) =>
      (_database.update(
        _database.queueStates,
      )..where((s) => s.id.equals(_stateId))).write(
        QueueStatesCompanion(positionMs: Value(position.inMilliseconds)),
      );
}
