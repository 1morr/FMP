import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fmp/data/database.dart';

/// 保存搜尋紀錄的地方；沒有資料庫時是 null，不保存。
final searchHistoryStoreProvider = Provider<SearchHistoryStore?>(
  (ref) => switch (ref.watch(appDatabaseProvider)) {
    final database? => SearchHistoryStore(database),
    null => null,
  },
);

/// 搜尋紀錄存進資料庫、啟動時讀回（brief〈搜尋〉）。
class SearchHistoryStore {
  SearchHistoryStore(this._database);

  final AppDatabase _database;

  /// 最多保留幾筆，超過刪最舊的（沿用舊版）。
  static const limit = 100;

  /// 所有紀錄，新到舊。
  Future<List<String>> load() async {
    final rows = await (_database.select(
      _database.searchHistoryEntries,
    )..orderBy([(e) => OrderingTerm.desc(e.searchedAt)])).get();
    return [for (final row in rows) row.query];
  }

  /// 記下 [query]（已 trim）在 [at] 搜過；已有就更新時間。超過 [limit] 筆時
  /// 刪最舊的，與寫入同一個交易。
  Future<void> record(String query, DateTime at) =>
      _database.transaction(() async {
        await _database
            .into(_database.searchHistoryEntries)
            .insertOnConflictUpdate(
              SearchHistoryEntriesCompanion.insert(
                query: query,
                searchedAt: at.millisecondsSinceEpoch,
              ),
            );
        await _database.customStatement(
          'DELETE FROM search_history_entries WHERE "query" NOT IN ('
          'SELECT "query" FROM search_history_entries '
          'ORDER BY searched_at DESC LIMIT $limit)',
        );
      });

  Future<void> remove(String query) => (_database.delete(
    _database.searchHistoryEntries,
  )..where((e) => e.query.equals(query))).go();

  Future<void> clear() => _database.delete(_database.searchHistoryEntries).go();
}
