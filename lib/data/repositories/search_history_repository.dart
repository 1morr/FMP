import 'package:isar/isar.dart';

import '../../core/constants/app_constants.dart';
import '../models/search_history.dart';

/// 搜尋歷史 Repository。
///
/// 封裝 `SearchHistory` 的讀寫、去重與上限邏輯，讓 `SearchService` 不再直接
/// 碰 Isar——與其他 collection（Track/Playlist/PlayHistory…）一致走 repository
/// 模式（C10 / 01-action-plan.md）。
class SearchHistoryRepository {
  SearchHistoryRepository(this._isar);

  final Isar _isar;

  /// 取最近 [limit] 筆（query 非空），按時間倒序。
  Future<List<SearchHistory>> getRecent({int limit = 20}) {
    return _isar.searchHistorys
        .filter()
        .queryIsNotEmpty()
        .sortByTimestampDesc()
        .limit(limit)
        .findAll();
  }

  /// 刪除單筆。
  Future<void> deleteById(int id) async {
    await _isar.writeTxn(() => _isar.searchHistorys.delete(id));
  }

  /// 清空全部。
  Future<void> clear() async {
    await _isar.writeTxn(() => _isar.searchHistorys.clear());
  }

  /// 儲存查詢——先刪同 query 舊記錄（去重），再新增，並保留最近
  /// [AppConstants.maxSearchHistoryCount] 筆。
  Future<void> saveQuery(String query) async {
    final trimmedQuery = query.trim();
    if (trimmedQuery.isEmpty) return;

    final existing = await _isar.searchHistorys
        .filter()
        .queryEqualTo(trimmedQuery)
        .findAll();

    await _isar.writeTxn(() async {
      for (final history in existing) {
        await _isar.searchHistorys.delete(history.id);
      }

      final newHistory = SearchHistory()
        ..query = trimmedQuery
        ..timestamp = DateTime.now();
      await _isar.searchHistorys.put(newHistory);

      final allHistory = await _isar.searchHistorys
          .filter()
          .queryIsNotEmpty()
          .sortByTimestampDesc()
          .findAll();

      if (allHistory.length > AppConstants.maxSearchHistoryCount) {
        final toDelete = allHistory.sublist(AppConstants.maxSearchHistoryCount);
        for (final history in toDelete) {
          await _isar.searchHistorys.delete(history.id);
        }
      }
    });
  }

  /// 前綴搜尋建議：[prefix] 為空時回最近 5 筆查詢；否則 case-insensitive
  /// contains 比對，取最近 10 筆的 query。
  Future<List<String>> searchByPrefix(String prefix) async {
    if (prefix.trim().isEmpty) {
      final history = await getRecent(limit: 5);
      return history.map((h) => h.query).toList();
    }

    final history = await _isar.searchHistorys
        .filter()
        .queryContains(prefix, caseSensitive: false)
        .sortByTimestampDesc()
        .limit(10)
        .findAll();

    return history.map((h) => h.query).toList();
  }
}
