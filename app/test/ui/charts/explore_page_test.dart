import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/charts/chart_jobs.dart';
import 'package:fmp/core/network/network_status.dart';
import 'package:fmp/data/providers.dart';
import 'package:fmp/ui/charts/explore_page.dart';
import 'package:fmp/ui/charts/home_charts.dart';
import 'package:fmp/ui/home/home_page.dart';
import 'package:fmp/ui/library/remote_write_state.dart';
import 'package:fmp/ui/player/player_bar.dart';
import 'package:material_ui/material_ui.dart';

import 'chart_harness.dart';

// 探索頁（M4 PR 21，design §9.3、§10.7）：首頁「查看全部」在首頁的巢狀導覽裡開、分頁照設定的順序、
// 完整清單、多選的動作、工具列的「刷新」（runNow；離線提示）。

/// 首頁榜單 [title] 子區塊的「查看全部」。
Finder _viewAll(String title) => find.descendant(
  of: find
      .ancestor(
        of: find.descendant(
          of: find.byType(HomeCharts),
          matching: find.text(title),
        ),
        matching: find.byType(Row),
      )
      .first,
  matching: find.text('View all'),
);

/// 從首頁的 [title]「查看全部」開探索頁。
Future<void> _open(WidgetTester tester, ChartHarness c, String title) async {
  await tester.tap(_viewAll(title));
  await tester.pumpAndSettle();
  expect(find.byType(ExplorePage), findsOneWidget);
}

/// 探索頁的分頁文字，依順序。
List<String> _tabs(WidgetTester tester) => [
  for (final tab in tester.widgetList<Tab>(find.byType(Tab))) tab.text!,
];

int _selectedTab(WidgetTester tester) =>
    tester.widget<TabBar>(find.byType(TabBar)).controller!.index;

/// 探索頁裡曲目 [title] 那一列。
Finder _row(String title) => find.ancestor(
  of: find.descendant(of: find.byType(ExplorePage), matching: find.text(title)),
  matching: find.byType(ListTile),
);

void main() {
  testWidgets('"View all" opens Explore inside Home on that chart; back '
      'returns to Home', (tester) async {
    final c = ChartHarness();
    await c.pumpShell(tester);

    await _open(tester, c, 'NEW');

    expect(_tabs(tester), ['HOT · Fake fmp-test', 'NEW · Fake fmp-test']);
    expect(_selectedTab(tester), 1);
    expect(find.text('Track 1 of new'), findsOneWidget);
    // 在內容區裡開：導覽留著。
    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(HomePage).hitTestable(), findsNothing);

    await tester.tap(find.byTooltip('Back (Esc)'));
    await tester.pumpAndSettle();
    expect(find.byType(ExplorePage), findsNothing);
    expect(find.byType(HomePage).hitTestable(), findsOneWidget);
  });

  testWidgets('the tabs follow the order in the settings and only enabled '
      'charts have one', (tester) async {
    final c = ChartHarness(charts: const ['hot', 'new', 'old']);
    await c.pumpShell(tester);
    await c.setOrder(tester, ['old', 'hot', 'new']);
    await c.setEnabled(tester, 'new', enabled: false);

    await _open(tester, c, 'HOT');

    expect(_tabs(tester), ['OLD · Fake fmp-test', 'HOT · Fake fmp-test']);
    expect(_selectedTab(tester), 1);

    // 頁面開著時停用目前的榜單：分頁跟著變，回到第一個。
    await c.setEnabled(tester, 'hot', enabled: false);
    await tester.pumpAndSettle();
    expect(_tabs(tester), ['OLD · Fake fmp-test']);
    expect(find.text('Track 1 of old'), findsOneWidget);
  });

  testWidgets('every chart turned off says where to turn them on; no plugin '
      'with charts says so', (tester) async {
    final c = ChartHarness();
    await c.pumpShell(tester);
    await _open(tester, c, 'HOT');
    await c.setEnabled(tester, 'hot', enabled: false);
    await c.setEnabled(tester, 'new', enabled: false);
    await tester.pumpAndSettle();

    expect(find.text('No charts turned on'), findsOneWidget);
    expect(find.text('No plugin offers charts'), findsNothing);
    expect(find.byType(TabBar), findsNothing);
  });

  testWidgets('without a plugin that offers charts Explore says so', (
    tester,
  ) async {
    final c = ChartHarness(declaresCharts: false);
    await c.pumpShell(tester);
    unawaited(openExplore(tester.element(find.byType(HomePage)), c.key('hot')));
    await tester.pumpAndSettle();

    expect(find.text('No plugin offers charts'), findsOneWidget);
    expect(find.text('No charts turned on'), findsNothing);
  });

  testWidgets('a tab lists the whole chart with ranks', (tester) async {
    final c = ChartHarness(tracks: 12);
    await c.pumpShell(tester);
    await _open(tester, c, 'HOT');

    for (var n = 1; n <= 12; n++) {
      await tester.scrollUntilVisible(
        _row('Track $n of hot'),
        200,
        scrollable: find
            .descendant(
              of: find.byType(ExplorePage),
              matching: find.byType(Scrollable),
            )
            .last,
      );
      expect(
        find.descendant(of: _row('Track $n of hot'), matching: find.text('$n')),
        findsOneWidget,
      );
    }
  });

  testWidgets('switching tabs shows the other chart', (tester) async {
    final c = ChartHarness();
    await c.pumpShell(tester);
    await _open(tester, c, 'HOT');

    await tester.tap(find.text('NEW · Fake fmp-test'));
    await tester.pumpAndSettle();

    expect(_selectedTab(tester), 1);
    expect(find.text('Track 1 of new').hitTestable(), findsOneWidget);
  });

  group('selecting', () {
    testWidgets('long press selects; add to queue adds the selected songs '
        'in order and leaves selection', (tester) async {
      final c = ChartHarness();
      await c.pumpShell(tester);
      await _open(tester, c, 'HOT');

      await tester.longPress(_row('Track 3 of hot'));
      await tester.pump();
      await tester.tap(_row('Track 1 of hot'));
      await tester.pump();
      expect(find.text('2 selected'), findsOneWidget);

      await tester.tap(find.byTooltip('Add to queue'));
      await tester.pumpAndSettle();

      expect(
        [
          for (final entry in c.shell.controller.queue.entries)
            entry.track.sourceId,
        ],
        ['hot-1', 'hot-3'],
      );
      expect(find.text('2 selected'), findsNothing);
      expect(find.byType(PlayerBar), findsOneWidget);
    });

    testWidgets('select all, then "Add to playlist…" adds the whole chart', (
      tester,
    ) async {
      final c = ChartHarness(tracks: 4);
      await c.pumpShell(tester);
      // 假時間裡寫：首頁在監看 `chart_settings`（見 chart_harness.dart）。
      final playlists = c.shell
          .container(tester)
          .read(playlistRepositoryProvider);
      final id = await playlists.create(name: 'Road');
      await c.settle(tester);
      await _open(tester, c, 'HOT');

      await tester.longPress(_row('Track 2 of hot'));
      await tester.pump();
      await tester.tap(find.byTooltip('Select all (Ctrl+A)'));
      await tester.pump();
      expect(find.text('4 selected'), findsOneWidget);

      await tester.tap(find.byTooltip('Add to playlist…'));
      await tester.pumpAndSettle();
      expect(find.text('Add to playlist'), findsOneWidget);
      await tester.tap(find.widgetWithText(CheckboxListTile, 'Road'));
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Add'));
      await c.settle(tester);
      await tester.pumpAndSettle();

      expect(
        [for (final entry in await playlists.entries(id)) entry.track.sourceId],
        ['hot-1', 'hot-2', 'hot-3', 'hot-4'],
      );
      expect(find.text('4 selected'), findsNothing);
    });

    testWidgets('new content from a refresh leaves selection', (tester) async {
      final c = ChartHarness();
      await c.pumpShell(tester);
      await _open(tester, c, 'HOT');
      await tester.longPress(_row('Track 1 of hot'));
      await tester.pump();
      expect(find.text('1 selected'), findsOneWidget);

      // 選取列取代了標題列（沒有「刷新」）：排程到期的那一次也一樣寫進快取。
      final before = c.cache.entries[c.key('hot')]!.fetchedAt;
      await tester.pump(const Duration(seconds: 1));
      unawaited(
        c.shell
            .container(tester)
            .read(chartJobsProvider.notifier)
            .runNow(c.plugin.manifest.id),
      );
      await c.settle(tester);

      expect(c.cache.entries[c.key('hot')]!.fetchedAt, isNot(before));
      expect(find.text('1 selected'), findsNothing);
    });

    testWidgets('switching tabs drops the selection of the other chart', (
      tester,
    ) async {
      final c = ChartHarness();
      await c.pumpShell(tester);
      await _open(tester, c, 'HOT');
      await tester.longPress(_row('Track 1 of hot'));
      await tester.pump();
      expect(find.text('1 selected'), findsOneWidget);

      await tester.tap(find.text('NEW · Fake fmp-test'));
      await tester.pumpAndSettle();

      expect(_selectedTab(tester), 1);
      expect(find.text('1 selected'), findsNothing);
    });

    testWidgets('the selection bar offers "Add to remote playlist…" for a '
        'writable source', (tester) async {
      final c = ChartHarness(
        extraOverrides: [
          remoteWritablePluginsProvider.overrideWithValue(const {'fmp-test'}),
        ],
      );
      await c.pumpShell(tester);
      await _open(tester, c, 'HOT');

      await tester.longPress(_row('Track 1 of hot'));
      await tester.pump();

      final button = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.cloud_upload_outlined),
      );
      expect(button.tooltip, 'Add to remote playlist…');
      expect(button.onPressed, isNotNull);
    });

    testWidgets('Esc leaves selection before leaving the page', (tester) async {
      final c = ChartHarness();
      await c.pumpShell(tester);
      await _open(tester, c, 'HOT');

      await tester.longPress(_row('Track 1 of hot'));
      await tester.pump();
      expect(find.text('1 selected'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('1 selected'), findsNothing);
      expect(find.byType(ExplorePage), findsOneWidget);
    });
  });

  group('refreshing', () {
    testWidgets('Refresh runs the job of the shown chart\'s plugin now', (
      tester,
    ) async {
      final c = ChartHarness();
      await c.pumpShell(tester);
      await _open(tester, c, 'HOT');
      final before = c.plugin.chartQueries.length;

      await tester.tap(find.byTooltip('Refresh'));
      await c.settle(tester);

      expect(c.plugin.chartQueries.sublist(before), ['hot', 'new']);
      expect(find.text('Charts updated'), findsOneWidget);
    });

    testWidgets('with automatic updates off and no cache the tab points at '
        'Refresh, which loads it', (tester) async {
      final c = ChartHarness(database: await chartsOffDatabase(tester));
      await c.pumpShell(tester);
      await _open(tester, c, 'HOT');

      final explore = find.byType(ExplorePage);
      expect(
        find.descendant(
          of: explore,
          matching: find.text('Use Refresh at the top to load it.'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: explore,
          matching: find.byType(CircularProgressIndicator),
        ),
        findsNothing,
      );

      // 刷新進行中：轉圈，不再說自動更新已關閉。
      final gate = Completer<void>();
      final tracks = c.plugin.onChart;
      c.plugin.onChart = (chartId) async {
        await gate.future;
        return tracks(chartId);
      };
      await tester.tap(find.byTooltip('Refresh'));
      await c.settle(tester);
      expect(
        find.descendant(
          of: explore,
          matching: find.byType(CircularProgressIndicator),
        ),
        findsOneWidget,
      );
      expect(find.text('Use Refresh at the top to load it.'), findsNothing);

      gate.complete();
      await c.settle(tester);
      expect(c.plugin.chartQueries, ['hot', 'new']);
      expect(_row('Track 1 of hot'), findsOneWidget);
    });

    testWidgets('offline: nothing is sent and a toast says so', (tester) async {
      final c = ChartHarness();
      await c.pumpShell(tester);
      await _open(tester, c, 'HOT');
      final before = c.plugin.chartQueries.length;

      await c.shell.setNetwork(tester, NetworkStatus.noInterface);
      await tester.tap(find.byTooltip('Refresh'));
      await c.settle(tester);

      expect(c.plugin.chartQueries.length, before);
      expect(
        find.text('Offline, not refreshed: showing the last charts'),
        findsOneWidget,
      );
      // 有快取：離線照常顯示上次的內容。
      expect(find.text('Track 1 of hot'), findsOneWidget);
    });

    testWidgets('every chart failing is an error toast; the tab says the '
        'chart failed', (tester) async {
      final c = ChartHarness();
      final tracks = c.plugin.onChart;
      await c.pumpShell(tester);
      await _open(tester, c, 'HOT');

      c.plugin.onChart = (_) => throw StateError('broken');
      await tester.tap(find.byTooltip('Refresh'));
      await c.settle(tester);

      expect(
        find.textContaining("Couldn't refresh the charts:"),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byType(ExplorePage),
          matching: find.text('Update failed'),
        ),
        findsOneWidget,
      );
      // 上次的內容留著。
      expect(find.text('Track 1 of hot'), findsOneWidget);
      c.plugin.onChart = tracks;
    });
  });
}
