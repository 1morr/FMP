import 'package:drift/drift.dart';

import 'package:fmp/data/cache/cache_tables.dart';
import 'package:fmp/data/database/converters.dart';

part 'cache_database.g.dart';

/// 快取庫的索引 `cache.db`（ADR 0016 §決定 2），與主資料庫分開：主資料庫開不
/// 起來就停在錯誤頁（ADR 0010 §決定 3），這個開不起來就整個丟掉重建
/// （`openCacheStore`）。只有 `lib/data/cache/` 使用它。
@DriftDatabase(tables: [CacheEntriesTable])
class CacheDatabase extends _$CacheDatabase {
  CacheDatabase(super.executor);

  /// 改了 `cache_tables.dart` 就要加一，並存新快照（drift_schemas/cache_database/）。
  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    // 快取可以隨時丟（ADR 0016 §決定 1）：版本不同（升級，或 revert 之後的
    // 降級；drift 兩種都走 onUpgrade）就刪掉所有表、照目前的 schema 重建，不寫
    // 逐步 migration。索引空了，`openCacheStore` 的對帳會刪掉所有檔案。
    onUpgrade: (m, from, to) async {
      final tables = await customSelect(
        "SELECT name FROM sqlite_master WHERE type = 'table' "
        "AND name NOT LIKE 'sqlite_%'",
      ).get();
      for (final table in tables) {
        final name = table.read<String>('name').replaceAll('"', '""');
        await customStatement('DROP TABLE "$name"');
      }
      await m.createAll();
    },
  );
}
