import 'dart:async';

import 'package:clock/clock.dart';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';

import 'package:fmp/data/database/app_database.dart';

/// 搜尋歷史的一列（`search_history`，ADR 0035 §決定 9）。
@immutable
final class SearchHistoryEntry {
  const SearchHistoryEntry({required this.query, required this.searchedAt});

  final String query;
  final DateTime searchedAt;

  @override
  bool operator ==(Object other) =>
      other is SearchHistoryEntry &&
      other.query == query &&
      other.searchedAt == searchedAt;

  @override
  int get hashCode => Object.hash(query, searchedAt);
}

/// 搜尋歷史：一個關鍵字一列，只留最新的 [limit] 筆。
final class SearchHistoryRepository {
  SearchHistoryRepository(this._database);

  /// 舊版留 100 筆、列出 20 筆；新版兩者合一（ADR 0035 §決定 9）。
  static const limit = 50;

  final AppDatabase _database;

  /// 記下一次送出的搜尋：[query] 去掉前後空白，空的不記；同一個關鍵字只更新時間。
  /// 超出 [limit] 的舊列在同一個 transaction 裡刪掉。
  Future<void> record(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return;
    await _database.transaction(() async {
      await _database
          .into(_database.searchHistoryTable)
          .insertOnConflictUpdate(
            SearchHistoryTableCompanion.insert(
              query: trimmed,
              searchedAt: clock.now(),
            ),
          );
      await _database.customStatement(
        'DELETE FROM search_history WHERE query NOT IN ('
        'SELECT query FROM search_history '
        'ORDER BY searched_at DESC, query ASC LIMIT $limit)',
      );
    });
    // customStatement 不通知串流。
    _database.markTablesUpdated([_database.searchHistoryTable]);
  }

  /// 最新的在前。
  Future<List<SearchHistoryEntry>> list() async {
    final rows =
        await (_database.select(_database.searchHistoryTable)
              ..orderBy([
                (t) => OrderingTerm.desc(t.searchedAt),
                (t) => OrderingTerm.asc(t.query),
              ])
              ..limit(limit))
            .get();
    return [
      for (final row in rows)
        SearchHistoryEntry(query: row.query, searchedAt: row.searchedAt),
    ];
  }

  /// 表變動就發出一次，不帶內容。
  ///
  /// drift 的 `tableUpdates`、不是 `watch()` 查詢：後者在最後一個 listener 離開時排計時器，
  /// widget 測試結束時算成沒跑完的計時器（同 `PlayHistoryRepository.changes`）。
  Stream<void> changes() => _database
      .tableUpdates(TableUpdateQuery.onTable(_database.searchHistoryTable))
      .map((_) {});

  /// 目前的清單，之後每次變動再發一份（最新的在前）。先訂閱再讀，讀的期間的變動不會漏掉；
  /// 兩次重讀重疊時只發最後開始的那一次。
  Stream<List<SearchHistoryEntry>> watch() {
    late final StreamController<List<SearchHistoryEntry>> controller;
    StreamSubscription<void>? updates;
    var generation = 0;

    void read() {
      final mine = ++generation;
      unawaited(
        list().then(
          (entries) {
            if (mine == generation && !controller.isClosed) {
              controller.add(entries);
            }
          },
          onError: (Object error, StackTrace stackTrace) {
            if (mine == generation && !controller.isClosed) {
              controller.addError(error, stackTrace);
            }
          },
        ),
      );
    }

    controller = StreamController(
      onListen: () {
        updates = changes().listen((_) => read());
        read();
      },
      onCancel: () async {
        await updates?.cancel();
        await controller.close();
      },
    );
    return controller.stream;
  }

  /// 刪掉一個關鍵字；沒有就什麼都不做。
  Future<void> delete(String query) => (_database.delete(
    _database.searchHistoryTable,
  )..where((t) => t.query.equals(query))).go();

  Future<void> clear() => _database.delete(_database.searchHistoryTable).go();
}
