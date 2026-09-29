import 'package:drift/drift.dart';

import 'package:fmp/data/database/converters.dart';
import 'package:fmp/data/database/tables.dart';
import 'package:fmp/domain/appearance.dart';

part 'app_database.g.dart';

/// App 唯一的資料庫（ADR 0010）。只有 `lib/data/` 使用它（lint
/// `fmp_layer_imports` 擋其他目錄 import drift）；上層透過
/// `lib/data/repositories/` 存取。
///
/// 執行器從建構子注入：App 用 `openAppDatabase` 開資料目錄裡的檔案，測試用
/// `NativeDatabase.memory()`。
@DriftDatabase(
  tables: [AppearanceSettingsTable, InstalledPluginsTable, PluginStorageTable],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.executor);

  /// 改了 `tables.dart` 就要加一，並存新快照（drift_schemas/）。
  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    // SQLite 預設不檢查外鍵，而且這個設定只對目前連線有效，每次開啟都要設
    // （ADR 0019 §決定 1）。放在 beforeOpen：migration 跑完之後、第一個查詢之前。
    beforeOpen: (_) => customStatement('PRAGMA foreign_keys = ON'),
  );
}
