import 'dart:async';

import 'package:fmp/charts/chart_cache.dart';
import 'package:fmp/plugins/manifest/plugin_manifest.dart';
import 'package:fmp/plugins/source_dto.dart';
import 'package:fmp/plugins/source_plugin.dart';

/// 假的 `charts` 插件：榜單清單是 [charts]，每個榜單的內容由 [onChart] 決定（預設兩首）。記下每次
/// 呼叫。其他能力一律拋 [UnimplementedError]。
final class FakeChartPlugin implements SourcePlugin {
  FakeChartPlugin({
    String id = 'fmp-test',
    List<String> charts = const ['hot', 'new'],
    bool declaresCharts = true,
  }) : charts = [
         for (final chartId in charts)
           ChartRef(chartId: chartId, title: chartId.toUpperCase()),
       ],
       manifest = PluginManifest(
         id: id,
         name: 'Fake $id',
         version: '1.0.0',
         author: 'FMP tests',
         capabilities: {
           PluginCapability.search,
           if (declaresCharts) PluginCapability.charts,
         },
         allowedHosts: const ['fmp.test'],
       );

  final List<ChartRef> charts;

  /// 給了就讓 `chartList` 丟它。
  Object? listError;

  /// 一個榜單的內容；丟錯就是這個榜單更新失敗。
  FutureOr<ChartPage> Function(String chartId) onChart = (chartId) => ChartPage(
    tracks: [
      for (final n in [1, 2])
        TrackSummary(
          sourceTypeId: 'fmp-test',
          sourceId: '$chartId-$n',
          title: 'Track $n of $chartId',
        ),
    ],
  );

  var chartListCalls = 0;

  /// 被問過的榜單 id，依順序。
  final chartQueries = <String>[];

  @override
  final PluginManifest manifest;

  @override
  PluginHealth get health => PluginHealth.ready;

  @override
  Future<void> get whenUnresponsive => Completer<void>().future;

  /// 給了就讓 `chartList` 等它完成才回來（還沒問完的插件）。
  Future<void>? listGate;

  @override
  Future<ChartList> chartList() async {
    chartListCalls++;
    if (listGate case final gate?) await gate;
    if (listError case final error?) throw error;
    return ChartList(charts: List.of(charts));
  }

  @override
  Future<ChartPage> chart(ChartQuery query) async {
    chartQueries.add(query.chartId);
    return onChart(query.chartId);
  }

  @override
  void close() {}

  // 其他能力沒有人呼叫：一律拋，不寫空殼。
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

/// 記憶體裡的榜單快取：排程的測試在假時鐘裡跑，真的快取庫（檔案與資料庫）在假時鐘裡不會完成。
/// 真的快取庫的行為在 `chart_cache_test.dart`。
final class FakeChartCache implements ChartCache {
  final entries = <ChartKey, ChartCacheEntry>{};

  /// 依順序記下刪除的呼叫。
  final removedCharts = <ChartKey>[];
  final removedPlugins = <String>[];

  @override
  Future<void> write(ChartKey key, ChartCacheEntry entry) async {
    entries[key] = entry;
  }

  @override
  Future<ChartCacheEntry?> read(ChartKey key) async => entries[key];

  @override
  Future<void> remove(ChartKey key) async {
    removedCharts.add(key);
    entries.remove(key);
  }

  @override
  Future<void> removePlugin(String pluginId) async {
    removedPlugins.add(pluginId);
    entries.removeWhere((key, _) => key.pluginId == pluginId);
  }
}
