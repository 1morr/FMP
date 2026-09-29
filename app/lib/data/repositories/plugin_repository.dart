import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';

import 'package:fmp/data/database/app_database.dart';

/// 一個從檔案安裝的插件（ADR 0014）。
@immutable
final class InstalledPlugin {
  const InstalledPlugin({
    required this.id,
    required this.version,
    required this.manifestJson,
    required this.script,
    required this.installedAt,
  });

  /// 音源 id。
  final String id;
  final String version;

  /// manifest 原文；解析是插件層的事。
  final String manifestJson;
  final String script;

  /// 存成 UTC epoch 毫秒；讀回來是 UTC、精度到毫秒。
  final DateTime installedAt;

  @override
  bool operator ==(Object other) =>
      other is InstalledPlugin &&
      other.id == id &&
      other.version == version &&
      other.manifestJson == manifestJson &&
      other.script == script &&
      other.installedAt == installedAt;

  @override
  int get hashCode =>
      Object.hash(id, version, manifestJson, script, installedAt);

  @override
  String toString() =>
      'InstalledPlugin(id: $id, version: $version, installedAt: $installedAt)';
}

/// `installed_plugins` 的存取。
final class PluginRepository {
  PluginRepository(this._database);

  final AppDatabase _database;

  /// 安裝；同 id 已存在就覆蓋成 [plugin]（更新）。
  ///
  /// 用 upsert（`ON CONFLICT DO UPDATE`）而不是先刪再插：更新插件不能經由
  /// 外鍵的 cascade 清掉它的 storage。
  Future<void> install(InstalledPlugin plugin) => _database
      .into(_database.installedPluginsTable)
      .insertOnConflictUpdate(
        InstalledPluginsTableCompanion.insert(
          id: plugin.id,
          version: plugin.version,
          manifestJson: plugin.manifestJson,
          script: plugin.script,
          installedAt: plugin.installedAt,
        ),
      );

  /// 依 id 讀；沒有安裝時回傳 `null`。
  Future<InstalledPlugin?> byId(String id) async {
    final row = await (_database.select(
      _database.installedPluginsTable,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    return row == null ? null : _fromRow(row);
  }

  /// 所有已安裝的插件，依 id 排序。
  Future<List<InstalledPlugin>> list() async {
    final rows = await (_database.select(
      _database.installedPluginsTable,
    )..orderBy([(t) => OrderingTerm.asc(t.id)])).get();
    return [for (final row in rows) _fromRow(row)];
  }

  /// 移除；它的 storage 由外鍵的 `ON DELETE CASCADE` 一起清掉。
  Future<void> remove(String id) => (_database.delete(
    _database.installedPluginsTable,
  )..where((t) => t.id.equals(id))).go();

  static InstalledPlugin _fromRow(InstalledPluginRow row) => InstalledPlugin(
    id: row.id,
    version: row.version,
    manifestJson: row.manifestJson,
    script: row.script,
    installedAt: row.installedAt,
  );
}
