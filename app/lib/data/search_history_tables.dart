import 'package:drift/drift.dart';

/// 搜尋紀錄，一個查詢字串一列（trim 後完全相同的算同一個）。
@DataClassName('SearchHistoryRow')
class SearchHistoryEntries extends Table {
  /// 查詢字串，trim 後的樣子。
  TextColumn get query => text()();

  /// 最後一次搜它的時間（unix 毫秒）；越大越新。
  IntColumn get searchedAt => integer()();

  @override
  Set<Column<Object>> get primaryKey => {query};
}
