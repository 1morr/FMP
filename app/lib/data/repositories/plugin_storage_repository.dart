import 'package:drift/drift.dart';

import 'package:fmp/data/database/app_database.dart';

/// `plugin_storage` 的存取：每個插件自己的 key／value（ADR 0014 §決定 5）。
///
/// 插件必須已經安裝（外鍵）；對沒安裝的 id 寫入會拋錯。移除插件時它的資料由
/// `PluginRepository.remove` 經外鍵一起清掉。
final class PluginStorageRepository {
  PluginStorageRepository(this._database);

  final AppDatabase _database;

  /// 讀 [key]；沒有時回傳 `null`。
  Future<String?> read(String pluginId, String key) async {
    final row =
        await (_database.select(_database.pluginStorageTable)
              ..where((t) => t.pluginId.equals(pluginId) & t.key.equals(key)))
            .getSingleOrNull();
    return row?.value;
  }

  /// 寫入 [key]；已存在就覆蓋。
  Future<void> write(String pluginId, String key, String value) => _database
      .into(_database.pluginStorageTable)
      .insertOnConflictUpdate(
        PluginStorageTableCompanion.insert(
          pluginId: pluginId,
          key: key,
          value: value,
        ),
      );

  /// 刪除 [key]；本來就沒有也不算錯。
  Future<void> delete(String pluginId, String key) => (_database.delete(
    _database.pluginStorageTable,
  )..where((t) => t.pluginId.equals(pluginId) & t.key.equals(key))).go();
}
