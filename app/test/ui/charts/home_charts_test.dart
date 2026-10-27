import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/charts/chart_jobs.dart';
import 'package:fmp/core/network/network_status.dart';
import 'package:fmp/data/providers.dart';
import 'package:fmp/domain/appearance.dart';
import 'package:fmp/domain/track_info.dart';
import 'package:fmp/playback/queue_model.dart';
import 'package:fmp/ui/charts/home_charts.dart';
import 'package:fmp/ui/empty_state/empty_state.dart';
import 'package:fmp/ui/format/date_text.dart';
import 'package:fmp/ui/home/home_page.dart';
import 'package:fmp/ui/offline/offline.dart';
import 'package:fmp/ui/tracks/now_playing_overlay.dart';
import 'package:material_ui/material_ui.dart';

import '../tracks/marker_support.dart';
import 'chart_harness.dart';

// 首頁的排行區塊（M4 PR 21，design §9.2、§10.2，ADR 0016 §決定 7）：第一個區塊、每個啟用的榜單一個
// 子區塊（順序照設定）、前 5 首與「更新於」、更新失敗、沒有快取時的載入中與離線、全部停用時沒有區塊。

/// 首頁上的榜單子區塊標題，依畫面上的順序（由上而下、同一列由左而右）。
List<String> _chartTitles(WidgetTester tester) {
  final titles = [
    for (final title in ['HOT', 'NEW'])
      if (find
          .descendant(of: find.byType(HomeCharts), matching: find.text(title))
          .evaluate()
          .isNotEmpty)
        title,
  ];
  int compare(Offset a, Offset b) =>
      a.dy != b.dy ? a.dy.compareTo(b.dy) : a.dx.compareTo(b.dx);
  return titles..sort(
    (a, b) => compare(
      tester.getTopLeft(find.text(a)),
      tester.getTopLeft(find.text(b)),
    ),
  );
}

/// 榜單 [title] 的子區塊：標題往上第二個 `Column`（第一個是標題與狀態行那一欄）。
Finder _section(String title) => find
    .ancestor(
      of: find.descendant(
        of: find.byType(HomeCharts),
        matching: find.text(title),
      ),
      matching: find.byType(Column),
    )
    .at(1);

void main() {
  testWidgets('the charts are the first section, one sub-section per '
      'enabled chart', (tester) async {
    final c = ChartHarness();
    await c.pumpShell(tester);
    // 假時間裡寫：首頁在監看 `chart_settings`，包 runAsync 的寫入等不到它放開的鎖（同電台）。
    await c.shell
        .container(tester)
        .read(playHistoryRepositoryProvider)
        .record(
          const TrackInfo(
            sourceTypeId: 'fmp-test',
            sourceId: 'x',
            title: 'Song x',
          ),
          playedAt: DateTime(2026, 10, 21, 8),
          limit: 100,
        );
    await c.settle(tester);

    expect(find.text('Charts'), findsOneWidget);
    expect(_chartTitles(tester), ['HOT', 'NEW']);
    expect(
      tester.getTopLeft(find.text('Charts')).dy,
      lessThan(tester.getTopLeft(find.text('Recently played')).dy),
    );
    expect(find.text('Nothing here yet'), findsNothing);
  });

  testWidgets('the playing song is marked in its chart on Home', (
    tester,
  ) async {
    reduceMotion(tester);
    final c = ChartHarness();
    await c.pumpShell(tester);
    await c.settle(tester);
    Finder row(String title) => find.ancestor(
      of: find.descendant(
        of: find.byType(HomeCharts),
        matching: find.text(title),
      ),
      matching: find.byType(ListTile),
    );
    expect(find.byKey(NowPlayingOverlay.overlayKey), findsNothing);

    await tester.tap(row('Track 2 of hot'));
    await c.settle(tester);

    expect(overlayIn(row('Track 2 of hot')), findsOneWidget);
    expect(overlayIn(row('Track 1 of hot')), findsNothing);
    expect(
      isPlayingTitle(
        tester,
        find.descendant(
          of: row('Track 2 of hot'),
          matching: find.text('Track 2 of hot'),
        ),
      ),
      isTrue,
    );
  });

  testWidgets('the sub-sections follow the order in the settings', (
    tester,
  ) async {
    final c = ChartHarness();
    await c.pumpShell(tester);
    expect(_chartTitles(tester), ['HOT', 'NEW']);

    await c.setOrder(tester, ['new', 'hot']);

    expect(_chartTitles(tester), ['NEW', 'HOT']);
  });

  testWidgets('a cached chart shows its top 5 and when it was updated', (
    tester,
  ) async {
    final c = ChartHarness(tracks: 7);
    await c.pumpShell(tester);

    for (var n = 1; n <= 5; n++) {
      expect(find.text('Track $n of hot'), findsOneWidget);
    }
    expect(find.text('Track 6 of hot'), findsNothing);
    expect(find.text('1'), findsNWidgets(2), reason: 'ranks of both charts');
    final fetchedAt = c.cache.entries[c.key('hot')]!.fetchedAt;
    expect(
      find.descendant(
        of: _section('HOT'),
        matching: find.text(
          'Fake fmp-test · Updated '
          '${formatDateTime(LocaleSetting.en, fetchedAt)}',
        ),
      ),
      findsOneWidget,
    );
    expect(find.text('Update failed'), findsNothing);
  });

  testWidgets('a failed update keeps the cached chart and says so', (
    tester,
  ) async {
    final c = ChartHarness();
    await c.pumpShell(tester);

    c.shell
        .container(tester)
        .read(chartFailuresProvider.notifier)
        .mark(c.key('new'));
    await tester.pump();

    expect(
      find.descendant(
        of: _section('NEW'),
        matching: find.text('Update failed'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: _section('HOT'),
        matching: find.text('Update failed'),
      ),
      findsNothing,
    );
    expect(find.text('Track 1 of new'), findsOneWidget);
  });

  testWidgets('without a cache: loading while online, the offline message '
      'while offline', (tester) async {
    final c = ChartHarness();
    hangCharts(c.plugin);
    await c.pumpShell(tester);

    expect(
      find.descendant(
        of: find.byType(HomeCharts),
        matching: find.byType(CircularProgressIndicator),
      ),
      findsNWidgets(2),
    );
    expect(find.byType(OfflineMessage), findsNothing);

    await c.shell.setNetwork(tester, NetworkStatus.noInterface);

    expect(find.byType(OfflineMessage), findsNWidgets(2));
    expect(
      find.descendant(
        of: find.byType(OfflineMessage),
        matching: find.text('No network connection'),
      ),
      findsNWidgets(2),
    );
    expect(
      find.descendant(
        of: find.byType(HomeCharts),
        matching: find.byType(CircularProgressIndicator),
      ),
      findsNothing,
    );

    await c.shell.setNetwork(tester, NetworkStatus.online);
    expect(find.byType(OfflineMessage), findsNothing);
    expect(
      find.descendant(
        of: find.byType(HomeCharts),
        matching: find.byType(CircularProgressIndicator),
      ),
      findsNWidgets(2),
    );
  });

  testWidgets('a chart that failed without a cache says it failed', (
    tester,
  ) async {
    final c = ChartHarness();
    final tracks = c.plugin.onChart;
    c.plugin.onChart = (chartId) =>
        chartId == 'new' ? throw StateError('broken chart') : tracks(chartId);
    await c.pumpShell(tester);

    expect(find.text('Track 1 of hot'), findsOneWidget);
    expect(
      find.descendant(
        of: _section('NEW'),
        matching: find.text("Couldn't update the chart"),
      ),
      findsOneWidget,
    );
  });

  // 區塊級的失敗是緊湊橫條（ADR 0035，R6.10），error 色圖示；探索頁的整頁版不是。
  testWidgets('a failed chart on Home is a compact error banner', (
    tester,
  ) async {
    final c = ChartHarness();
    final tracks = c.plugin.onChart;
    c.plugin.onChart = (chartId) =>
        chartId == 'new' ? throw StateError('broken chart') : tracks(chartId);
    await c.pumpShell(tester);

    final banner = tester.widget<EmptyState>(
      find.descendant(of: _section('NEW'), matching: find.byType(EmptyState)),
    );
    expect(banner.compact, isTrue);
    expect(banner.error, isTrue);
  });

  // 快取讀不出來時沒有工作能讓它變成有內容：說失敗，不一直轉圈。
  testWidgets('a chart whose cache cannot be read says it failed instead of '
      'loading', (tester) async {
    final c = ChartHarness();
    c.cache.readError = StateError('cache unavailable');
    await c.pumpShell(tester);

    expect(
      find.descendant(
        of: find.byType(HomeCharts),
        matching: find.byType(CircularProgressIndicator),
      ),
      findsNothing,
    );
    expect(find.text("Couldn't update the chart"), findsNWidgets(2));
  });

  // 間隔關閉時工作不會自己跑：說明怎麼手動載入，不轉圈；探索頁刷新之後就有內容。
  testWidgets('with automatic updates off and no cache: says so instead of '
      'loading, until a refresh fills it', (tester) async {
    final c = ChartHarness(database: await chartsOffDatabase(tester));
    await c.pumpShell(tester);

    expect(c.plugin.chartQueries, isEmpty);
    expect(
      find.descendant(
        of: find.byType(HomeCharts),
        matching: find.byType(CircularProgressIndicator),
      ),
      findsNothing,
    );
    expect(find.text('Automatic updates are off'), findsNWidgets(2));
    expect(
      find.text(
        'Refresh it in Explore, or set Charts refresh under '
        'Settings › Network.',
      ),
      findsNWidgets(2),
    );

    await c.shell.setNetwork(tester, NetworkStatus.noInterface);
    expect(find.byType(OfflineMessage), findsNWidgets(2));
    await c.shell.setNetwork(tester, NetworkStatus.online);

    unawaited(
      c.shell
          .container(tester)
          .read(chartJobsProvider.notifier)
          .runNow('fmp-test'),
    );
    await c.settleUntil(
      tester,
      () => find.text('Track 1 of hot').evaluate().isNotEmpty,
    );
    expect(find.text('Automatic updates are off'), findsNothing);
  });

  testWidgets('an empty chart says it is empty', (tester) async {
    final c = ChartHarness(tracks: 0);
    await c.pumpShell(tester);

    expect(find.text('This chart is empty'), findsNWidgets(2));
  });

  testWidgets('every chart turned off: no section, and the explanation is '
      'back', (tester) async {
    final c = ChartHarness();
    await c.pumpShell(tester);
    expect(find.text('Nothing here yet'), findsNothing);

    await c.setEnabled(tester, 'hot', enabled: false);
    expect(_chartTitles(tester), ['NEW']);

    await c.setEnabled(tester, 'new', enabled: false);
    expect(find.byType(HomeCharts), findsNothing);
    expect(find.text('Charts'), findsNothing);
    expect(find.text('Nothing here yet'), findsOneWidget);
  });

  testWidgets('without a plugin that offers charts there is no section', (
    tester,
  ) async {
    // 排行工作真的跑過（catalog 不是 null），只是插件沒有宣告 `charts`。
    final c = ChartHarness(declaresCharts: false);
    await c.pumpShell(tester);
    await tester.pumpAndSettle();

    expect(c.shell.container(tester).read(chartCatalogProvider), isEmpty);
    expect(c.plugin.chartListCalls, 0);
    expect(find.byType(HomeCharts), findsNothing);
    expect(find.text('Charts'), findsNothing);
    expect(find.text('Nothing here yet'), findsOneWidget);
  });

  testWidgets('tapping a chart track plays it temporarily; its menu is the '
      'track menu', (tester) async {
    final c = ChartHarness();
    await c.pumpShell(tester);

    await tester.tap(find.text('Track 2 of hot'));
    await tester.pump();

    final queue = c.shell.controller.queue;
    expect(queue.mode, QueueMode.temporary);
    expect(queue.current?.sourceId, 'hot-2');
    expect(queue.entries, isEmpty);

    await tester.tap(
      find
          .descendant(
            of: find.ancestor(
              of: find.text('Track 3 of hot'),
              matching: find.byType(ListTile),
            ),
            matching: find.byTooltip('More options'),
          )
          .first,
    );
    await tester.pumpAndSettle();
    for (final item in [
      'Play',
      'Play next',
      'Add to queue',
      'Add to playlist…',
    ]) {
      expect(
        find.widgetWithText(MenuItemButton, item),
        findsOneWidget,
        reason: item,
      );
    }
    // 首頁沒有多選。
    expect(find.widgetWithText(MenuItemButton, 'Select'), findsNothing);
  });

  // 排行工作取到 chartList 之前首頁不知道有榜單（它不讀插件清單，見 chartCatalogProvider）：
  // 其他區塊都沒有內容時先是說明，取到之後換成排行。
  testWidgets('the section shows up once the chart lists are known', (
    tester,
  ) async {
    final c = ChartHarness();
    final gate = Completer<void>();
    c.plugin.listGate = gate.future;
    await c.pumpShell(tester);

    expect(find.byType(HomeCharts), findsNothing);

    gate.complete();
    await c.settle(tester);
    expect(find.byType(HomeCharts), findsOneWidget);
    expect(find.text('Nothing here yet'), findsNothing);
    expect(find.byType(HomePage), findsOneWidget);
  });
}
