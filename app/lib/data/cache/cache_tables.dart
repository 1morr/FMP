import 'package:drift/drift.dart';

import 'package:fmp/data/database/converters.dart';

// cache.db 的 schema（ADR 0016 §決定 2）。改這個檔案就是改 schema：bump
// `CacheDatabase.schemaVersion`、存新快照（drift_schemas/cache_database/）。
// 快取可以隨時丟，所以不寫逐步 migration：版本不同就清空重建
// （`CacheDatabase.migration`）。

/// 快取的類別（ADR 0016 §決定 4）。設定頁依類別顯示用量（PR 5）。
enum CacheCategory {
  /// 封面與其他圖片。
  image,
}

/// [CacheCategory] ↔ `image`。字串寫死，理由同主資料庫的 `converters.dart`。
final class CacheCategoryConverter
    extends TypeConverter<CacheCategory, String> {
  const CacheCategoryConverter();

  @override
  CacheCategory fromSql(String fromDb) => switch (fromDb) {
    'image' => CacheCategory.image,
    _ => throw FormatException(
      'Unknown cache category in the database',
      fromDb,
    ),
  };

  @override
  String toSql(CacheCategory value) => switch (value) {
    CacheCategory.image => 'image',
  };
}

/// 快取庫的索引：一列一個檔案（`fmp_cache/files/` 底下）。
///
/// 鍵在同一個類別、同一個插件裡唯一：兩個插件給同一個網址時各存一份，各自經
/// 自己的允許網域下載，移除插件也只刪自己的（design §4.2 寫的是 `key` 唯一，
/// 這裡加上類別與插件）。`plugin_id` 為空的列不受唯一限制（SQLite 的 NULL
/// 互不相等），M2 的圖片一定有插件。
@DataClassName('CacheEntryRow')
@TableIndex(name: 'cache_entries_last_access', columns: {#lastAccess})
@TableIndex(name: 'cache_entries_plugin_id', columns: {#pluginId})
class CacheEntriesTable extends Table {
  @override
  String get tableName => 'cache_entries';

  /// `flutter_cache_manager` 的 `CacheObject.id` 是 int。
  late final id = integer().autoIncrement()();
  late final key = text()();
  late final category = text().map(const CacheCategoryConverter())();
  late final pluginId = text().nullable()();

  /// 相對 `fmp_cache/files/` 的檔名。
  late final relativePath = text()();
  late final sizeBytes = integer()();

  /// 最後一次讀或寫（UTC epoch 毫秒）；淘汰依它由舊到新。
  late final lastAccess = integer().map(const EpochMillisecondsConverter())();

  /// 伺服器說這份內容有效到何時（UTC epoch 毫秒）；過了就重新下載。
  late final validUntil = integer().map(const EpochMillisecondsConverter())();
  late final etag = text().nullable()();

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {category, pluginId, key},
  ];
}
