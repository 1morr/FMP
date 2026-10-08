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
    this.enabled = true,
    this.sourceIndexUrl,
    this.checksJson,
  });

  /// 音源 id。
  final String id;
  final String version;

  /// manifest 原文；解析是插件層的事。
  final String manifestJson;
  final String script;

  /// 存成 UTC epoch 毫秒；讀回來是 UTC、精度到毫秒。
  final DateTime installedAt;

  /// 停用的插件不載入（ADR 0030 §決定 7）。
  final bool enabled;

  /// 來自哪個 index 網址；`null`＝從檔案或網址安裝（ADR 0030 §決定 6）。
  final String? sourceIndexUrl;

  /// 從 index 安裝時一併存的 `checks.json` 原文，給健康檢查用。
  final String? checksJson;

  @override
  bool operator ==(Object other) =>
      other is InstalledPlugin &&
      other.id == id &&
      other.version == version &&
      other.manifestJson == manifestJson &&
      other.script == script &&
      other.installedAt == installedAt &&
      other.enabled == enabled &&
      other.sourceIndexUrl == sourceIndexUrl &&
      other.checksJson == checksJson;

  @override
  int get hashCode => Object.hash(
    id,
    version,
    manifestJson,
    script,
    installedAt,
    enabled,
    sourceIndexUrl,
    checksJson,
  );

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
  /// 外鍵的 cascade 清掉它的 storage。更新不動 `enabled`：停用的插件更新後
  /// 仍是停用（新裝的列是預設的啟用）。[InstalledPlugin.enabled] 只在讀回時有意義。
  Future<void> install(InstalledPlugin plugin) => _database
      .into(_database.installedPluginsTable)
      .insertOnConflictUpdate(
        InstalledPluginsTableCompanion.insert(
          id: plugin.id,
          version: plugin.version,
          manifestJson: plugin.manifestJson,
          script: plugin.script,
          installedAt: plugin.installedAt,
          sourceIndexUrl: Value(plugin.sourceIndexUrl),
          checksJson: Value(plugin.checksJson),
        ),
      );

  /// 啟用或停用；沒有這個插件時什麼都不做。
  Future<void> setEnabled(String id, {required bool enabled}) =>
      (_database.update(_database.installedPluginsTable)
            ..where((t) => t.id.equals(id)))
          .write(InstalledPluginsTableCompanion(enabled: Value(enabled)));

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
    enabled: row.enabled,
    sourceIndexUrl: row.sourceIndexUrl,
    checksJson: row.checksJson,
  );
}

/// 使用者加的自訂插件 index（`plugin_indexes`，ADR 0030 §決定 6）。
@immutable
final class PluginIndexRecord {
  const PluginIndexRecord({required this.url, required this.addedAt});

  final String url;

  /// 存成 UTC epoch 毫秒；讀回來是 UTC、精度到毫秒。
  final DateTime addedAt;

  @override
  bool operator ==(Object other) =>
      other is PluginIndexRecord &&
      other.url == url &&
      other.addedAt == addedAt;

  @override
  int get hashCode => Object.hash(url, addedAt);

  @override
  String toString() => 'PluginIndexRecord(url: $url, addedAt: $addedAt)';
}

/// `plugin_indexes` 的存取。
final class PluginIndexRepository {
  PluginIndexRepository(this._database);

  final AppDatabase _database;

  /// 加入；網址已存在時什麼都不做（保留最早的加入時間）。
  Future<void> add(String url, DateTime addedAt) => _database
      .into(_database.pluginIndexesTable)
      .insert(
        PluginIndexesTableCompanion.insert(url: url, addedAt: addedAt),
        mode: InsertMode.insertOrIgnore,
      );

  /// 依加入時間由舊到新，同刻依網址。
  Future<List<PluginIndexRecord>> list() async {
    final rows =
        await (_database.select(_database.pluginIndexesTable)..orderBy([
              (t) => OrderingTerm.asc(t.addedAt),
              (t) => OrderingTerm.asc(t.url),
            ]))
            .get();
    return [
      for (final row in rows)
        PluginIndexRecord(url: row.url, addedAt: row.addedAt),
    ];
  }

  Future<void> remove(String url) => (_database.delete(
    _database.pluginIndexesTable,
  )..where((t) => t.url.equals(url))).go();
}
