import 'package:drift/drift.dart';

/// 每個音源最後一份排行榜的抓取時間（ARCHITECTURE〈快取〉），一個插件一列。
@DataClassName('ChartSnapshotRow')
class ChartSnapshots extends Table {
  TextColumn get pluginId => text()();

  /// 抓到這份榜的時間（unix 毫秒）。
  IntColumn get fetchedAt => integer()();

  @override
  Set<Column<Object>> get primaryKey => {pluginId};
}

/// 最後一份排行榜的每一名，一名一列。曲目 id 存在這裡，改插件的 id 格式時
/// 要寫資料 migration（brief〈插件〉）。
@DataClassName('ChartEntryRow')
class ChartEntries extends Table {
  TextColumn get pluginId => text()();

  /// 名次，從 0 起（第 1 名是 0）。
  IntColumn get rank => integer()();

  TextColumn get trackId => text()();
  TextColumn get title => text()();
  TextColumn get author => text()();
  IntColumn get durationMs => integer().nullable()();
  TextColumn get coverUrl => text().nullable()();
  TextColumn get coverLargeUrl => text().nullable()();
  IntColumn get playCount => integer().nullable()();
  IntColumn get partCount => integer().nullable()();
  TextColumn get url => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {pluginId, rank};
}
