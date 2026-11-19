import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fmp/data/database.dart';
import 'package:fmp/domain/chart.dart';
import 'package:fmp/domain/track.dart';

/// 保存排行榜的地方；沒有資料庫時是 null，不保存。
final chartStoreProvider = Provider<ChartStore?>(
  (ref) => switch (ref.watch(appDatabaseProvider)) {
    final database? => ChartStore(database),
    null => null,
  },
);

/// 每個音源最後一份排行榜存進資料庫（ARCHITECTURE〈快取〉）。
class ChartStore {
  ChartStore(this._database);

  final AppDatabase _database;

  /// 存著的每一份榜，插件 id 對榜。
  Future<Map<String, Chart>> load() async {
    final snapshots = await _database.select(_database.chartSnapshots).get();
    final rows = await (_database.select(
      _database.chartEntries,
    )..orderBy([(e) => OrderingTerm.asc(e.rank)])).get();
    return {
      for (final snapshot in snapshots)
        snapshot.pluginId: Chart(
          fetchedAt: DateTime.fromMillisecondsSinceEpoch(snapshot.fetchedAt),
          tracks: [
            for (final row in rows)
              if (row.pluginId == snapshot.pluginId) _track(row),
          ],
        ),
    };
  }

  /// 把 [pluginId] 的榜換成 [chart]，同一個交易裡刪掉舊的。
  Future<void> save(String pluginId, Chart chart) =>
      _database.transaction(() async {
        await (_database.delete(
          _database.chartEntries,
        )..where((e) => e.pluginId.equals(pluginId))).go();
        await _database
            .into(_database.chartSnapshots)
            .insertOnConflictUpdate(
              ChartSnapshotsCompanion.insert(
                pluginId: pluginId,
                fetchedAt: chart.fetchedAt.millisecondsSinceEpoch,
              ),
            );
        await _database.batch(
          (batch) => batch.insertAll(_database.chartEntries, [
            for (final (rank, track) in chart.tracks.indexed)
              ChartEntriesCompanion.insert(
                pluginId: pluginId,
                rank: rank,
                trackId: track.ref.trackId,
                title: track.title,
                author: track.author,
                durationMs: Value(track.duration?.inMilliseconds),
                coverUrl: Value(track.coverUrl),
                coverLargeUrl: Value(track.coverLargeUrl),
                playCount: Value(track.playCount),
                partCount: Value(track.partCount),
                url: Value(track.url),
              ),
          ]),
        );
      });

  static Track _track(ChartEntryRow row) => Track(
    ref: TrackRef(pluginId: row.pluginId, trackId: row.trackId),
    title: row.title,
    author: row.author,
    duration: switch (row.durationMs) {
      final ms? => Duration(milliseconds: ms),
      null => null,
    },
    coverUrl: row.coverUrl,
    coverLargeUrl: row.coverLargeUrl,
    playCount: row.playCount,
    partCount: row.partCount,
    url: row.url,
  );
}
