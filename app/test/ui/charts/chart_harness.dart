import 'dart:async';

import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/charts/chart_cache.dart';
import 'package:fmp/charts/chart_jobs.dart';
import 'package:fmp/data/providers.dart';
import 'package:fmp/plugins/source_dto.dart';
import 'package:fmp/scheduler/background_scheduler.dart';
import 'package:fmp/ui/shell/app_shell.dart';
import 'package:material_ui/material_ui.dart';

import '../../charts/fake_chart_plugin.dart';
import '../support/shell_harness.dart';

/// 首頁排行、探索頁與設定頁「音樂庫」的測試環境：外殼的 [ShellHarness]，插件清單上只有一個
/// 宣告 `charts` 的假插件（[plugin]，id `fmp-test`，榜單 `HOT`、`NEW`），排行快取是記憶體裡的
/// [cache]（`declaresCharts: false` 時插件沒有宣告 `charts`）。排程器與排行工作照 App 常駐（`FmpApp` 聽著的那兩個）：沒有快取時工作一開始就跑，
/// 每個榜單 [tracks] 首（`Track n of <榜單>`）。
final class ChartHarness {
  ChartHarness({
    List<String> charts = const ['hot', 'new'],
    this.tracks = 7,
    bool declaresCharts = true,
    List<Override> extraOverrides = const [],
  }) : plugin = FakeChartPlugin(
         charts: charts,
         declaresCharts: declaresCharts,
       ) {
    plugin.onChart = (chartId) => ChartPage(
      tracks: [
        for (var n = 1; n <= tracks; n++)
          TrackSummary(
            sourceTypeId: 'fmp-test',
            sourceId: '$chartId-$n',
            title: 'Track $n of $chartId',
            uploader: 'Artist $n',
          ),
      ],
    );
    shell = ShellHarness(
      registryOfSources: true,
      sources: [plugin],
      extraOverrides: [
        chartCacheProvider.overrideWith((ref) => cache),
        ...extraOverrides,
      ],
    );
  }

  final FakeChartPlugin plugin;
  final int tracks;
  final cache = FakeChartCache();
  late final ShellHarness shell;

  /// 開外殼（預設在首頁），讓排程器與排行工作常駐，等第一次的排行工作寫進快取。
  Future<void> pumpShell(
    WidgetTester tester, {
    Size size = const Size(1000, 1400),
    Brightness brightness = Brightness.light,
    ShellDestination at = ShellDestination.home,
  }) async {
    await shell.pumpShell(
      tester,
      size: size,
      brightness: brightness,
      collapsePanel: true,
      at: at,
    );
    shell.container(tester)
      ..listen(backgroundSchedulerProvider, (_, _) {})
      ..listen(chartJobsProvider, (_, _) {});
    await settle(tester);
  }

  /// 資料庫的串流（榜單設定、網路設定）、排行工作與快取的重讀都跑完。載入中的進度圈一直在
  /// 轉，所以不用 `pumpAndSettle`。
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 3; i++) {
      await shell.loadSettings(tester);
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  /// 等到 [done] 成立：真的事件迴圈與假時間輪流推進（drift 兩邊都要），最多約一秒。
  Future<void> settleUntil(WidgetTester tester, bool Function() done) async {
    for (var i = 0; i < 50 && !done(); i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(done(), isTrue, reason: 'the condition never held');
  }

  /// 寫榜單的順序（資料庫在假時間裡寫：首頁已經在監看 `chart_settings`）。
  Future<void> setOrder(WidgetTester tester, List<String> chartIds) async {
    await shell
        .container(tester)
        .read(chartSettingsRepositoryProvider)
        .setOrder([
          for (final chartId in chartIds)
            (pluginId: plugin.manifest.id, chartId: chartId),
        ]);
    await settle(tester);
  }

  Future<void> setEnabled(
    WidgetTester tester,
    String chartId, {
    required bool enabled,
  }) async {
    await shell
        .container(tester)
        .read(chartSettingsRepositoryProvider)
        .setEnabled(plugin.manifest.id, chartId, enabled: enabled);
    await settle(tester);
  }

  ChartKey key(String chartId) =>
      (pluginId: plugin.manifest.id, chartId: chartId);
}

/// 讓 [plugin] 的榜單一直抓不回來（工作卡在那裡，快取一直是空的）。
void hangCharts(FakeChartPlugin plugin) =>
    plugin.onChart = (_) => Completer<ChartPage>().future;
