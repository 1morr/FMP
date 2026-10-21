import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';

import 'package:fmp/data/database/app_database.dart';

/// 一個榜單的設定（M4 design §3.1、§3.3）。欄位為 `null` 表示使用者沒設定過，由上層套用預設
/// （啟用；順序依插件清單與 `chartList`）。
@immutable
final class ChartSetting {
  const ChartSetting({
    required this.pluginId,
    required this.chartId,
    this.enabled,
    this.sortOrder,
  });

  final String pluginId;
  final String chartId;
  final bool? enabled;
  final int? sortOrder;

  @override
  bool operator ==(Object other) =>
      other is ChartSetting &&
      other.pluginId == pluginId &&
      other.chartId == chartId &&
      other.enabled == enabled &&
      other.sortOrder == sortOrder;

  @override
  int get hashCode => Object.hash(pluginId, chartId, enabled, sortOrder);

  @override
  String toString() =>
      'ChartSetting($pluginId/$chartId, enabled: $enabled, '
      'sortOrder: $sortOrder)';
}

/// `chart_settings` 的存取。沒有外鍵到 `installed_plugins`：移除插件時由
/// `PluginInstaller.remove` 刪（[removePlugin]），插件拿掉的榜單的列留著無害。
final class ChartSettingsRepository {
  ChartSettingsRepository(this._database);

  final AppDatabase _database;

  /// 所有榜單的設定，之後每次寫入再發一次。
  Stream<List<ChartSetting>> watch() => _database
      .select(_database.chartSettingsTable)
      .watch()
      .map((rows) => [for (final row in rows) _fromRow(row)]);

  /// 啟用或停用 [chartId]；這一列的排序不動，沒有這一列就建一列。
  Future<void> setEnabled(
    String pluginId,
    String chartId, {
    required bool enabled,
  }) => _database
      .into(_database.chartSettingsTable)
      .insertOnConflictUpdate(
        ChartSettingsTableCompanion(
          pluginId: Value(pluginId),
          chartId: Value(chartId),
          enabled: Value(enabled),
        ),
      );

  /// 依 [charts] 的順序整批寫 `sort_order`（0、1、2…），一個 transaction（設定頁拖曳後）。
  /// 每一列的 `enabled` 不動，沒有那一列就建一列。
  Future<void> setOrder(List<({String pluginId, String chartId})> charts) =>
      _database.batch((batch) {
        batch.insertAllOnConflictUpdate(_database.chartSettingsTable, [
          for (final (index, chart) in charts.indexed)
            ChartSettingsTableCompanion(
              pluginId: Value(chart.pluginId),
              chartId: Value(chart.chartId),
              sortOrder: Value(index),
            ),
        ]);
      });

  /// 刪 [pluginId] 的全部榜單設定。沒有時什麼都不做。
  Future<void> removePlugin(String pluginId) => (_database.delete(
    _database.chartSettingsTable,
  )..where((t) => t.pluginId.equals(pluginId))).go();

  static ChartSetting _fromRow(ChartSettingsRow row) => ChartSetting(
    pluginId: row.pluginId,
    chartId: row.chartId,
    enabled: row.enabled,
    sortOrder: row.sortOrder,
  );
}
