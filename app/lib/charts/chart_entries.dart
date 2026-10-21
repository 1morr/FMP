import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fmp/charts/chart_cache.dart';
import 'package:fmp/charts/chart_jobs.dart';
import 'package:fmp/data/repositories/chart_settings_repository.dart';
import 'package:fmp/plugins/source_dto.dart';

/// 一個榜單在介面上的樣子（M4 design §9.2、§9.3、§10.10）：插件的 `chartList` 給的身分與名稱，
/// 加上 `chart_settings` 的啟用。
@immutable
final class ChartEntry {
  const ChartEntry({
    required this.pluginId,
    required this.chartId,
    required this.title,
    required this.sourceName,
    required this.enabled,
  });

  final String pluginId;
  final String chartId;

  /// 插件給的榜單名稱。
  final String title;

  /// 插件的顯示名稱（manifest 的 `name`）。
  final String sourceName;

  /// `chart_settings.enabled` 不是假（沒有那一列＝啟用）。
  final bool enabled;

  ChartKey get key => (pluginId: pluginId, chartId: chartId);

  @override
  bool operator ==(Object other) =>
      other is ChartEntry &&
      other.pluginId == pluginId &&
      other.chartId == chartId &&
      other.title == title &&
      other.sourceName == sourceName &&
      other.enabled == enabled;

  @override
  int get hashCode =>
      Object.hash(pluginId, chartId, title, sourceName, enabled);

  @override
  String toString() =>
      'ChartEntry($pluginId/$chartId "$title", enabled: $enabled)';
}

/// 插件清單上（已啟用）宣告 `charts` 的插件的全部榜單，含停用的（設定頁要列出來重新勾選），
/// 依使用者的順序：`sort_order` 由小到大，沒有的排在後面、依插件清單的順序再依 `chartList`
/// 的順序（M4 design §3.3，同 §8.3 的目標音源排序）。插件新增的榜單預設啟用；插件拿掉的榜單
/// （`chart_settings` 裡留著的列）不出現。
///
/// 榜單清單是 [chartCatalogProvider]（[ChartJobs] 已經取到的），不另外問插件，也不讀插件清單
/// （為什麼見 [chartCatalogProvider]：測試裡會把插件清單與排行工作拉起來）。排行工作還沒對齊過、
/// 或沒有任何提供排行的插件時是空的，這時也不監看 `chart_settings`。`null`＝`chart_settings`
/// 還沒讀出來；讀失敗（已由 provider 記下）當成沒有設定。取不到 `chartList` 的插件沒有榜單。
final chartEntriesProvider = Provider<List<ChartEntry>?>((ref) {
  final catalog = ref.watch(chartCatalogProvider);
  if (catalog == null || catalog.isEmpty) return const [];
  final settings = switch (ref.watch(chartSettingsProvider)) {
    AsyncValue(:final value?) => value,
    AsyncError() => const <ChartSetting>[],
    _ => null,
  };
  if (settings == null) return null;
  final stored = {
    for (final setting in settings)
      (pluginId: setting.pluginId, chartId: setting.chartId): setting,
  };
  final entries = <({ChartEntry entry, int? sortOrder})>[];
  for (final MapEntry(key: id, value: plugin) in catalog.entries) {
    for (final chart in plugin.charts ?? const <ChartRef>[]) {
      final setting = stored[(pluginId: id, chartId: chart.chartId)];
      entries.add((
        entry: ChartEntry(
          pluginId: id,
          chartId: chart.chartId,
          title: chart.title,
          sourceName: plugin.name,
          enabled: setting?.enabled != false,
        ),
        sortOrder: setting?.sortOrder,
      ));
    }
  }
  // List.sort 不保證穩定：同分（或都沒有 sort_order）時以預設順序的位置比。
  final indexed = entries.indexed.toList()
    ..sort((a, b) {
      final (ai, (entry: _, sortOrder: ao)) = a;
      final (bi, (entry: _, sortOrder: bo)) = b;
      if (ao != null && bo != null && ao != bo) return ao.compareTo(bo);
      if (ao != null && bo == null) return -1;
      if (ao == null && bo != null) return 1;
      return ai.compareTo(bi);
    });
  return List.unmodifiable([for (final (_, item) in indexed) item.entry]);
});

/// 啟用的榜單（首頁的排行區塊與探索頁的分頁），順序同 [chartEntriesProvider]；`null`＝還在讀。
final enabledChartsProvider = Provider<List<ChartEntry>?>(
  (ref) => switch (ref.watch(chartEntriesProvider)) {
    null => null,
    final entries => List.unmodifiable([
      for (final entry in entries)
        if (entry.enabled) entry,
    ]),
  },
);
