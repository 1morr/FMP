import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/charts/chart_jobs.dart';
import 'package:fmp/data/providers.dart';
import 'package:fmp/data/repositories/chart_settings_repository.dart';
import 'package:fmp/ui/charts/home_charts.dart';
import 'package:fmp/ui/settings/library_controls.dart';
import 'package:fmp/ui/shell/app_shell.dart';
import 'package:material_ui/material_ui.dart';

import '../charts/chart_harness.dart';

// 設定頁的「音樂庫」區（M4 PR 21，design §10.10）：「首頁排行」的清單、取消勾選寫 `enabled`、拖曳整批寫
// `sort_order`，之後 `chartSettingsProvider` 跟著變（停用時刪快取與重新登記工作由 chart_jobs_test.dart
// 守，這裡只驗寫入）。

/// 開設定頁的「音樂庫」（寬版：左邊清單、右邊內容）。
Future<ChartHarness> _open(
  WidgetTester tester, {
  List<String> charts = const ['hot', 'new'],
}) async {
  final c = ChartHarness(charts: charts);
  await c.pumpShell(tester, at: ShellDestination.settings);
  await tester.tap(find.widgetWithText(ListTile, 'Library'));
  await c.settle(tester);
  expect(find.byType(HomeChartsSettings), findsOneWidget);
  return c;
}

Finder _tile(String title) => find.widgetWithText(CheckboxListTile, title);

/// 清單上的榜單名稱，由上而下。
List<String> _shown(WidgetTester tester) {
  final tiles = tester
      .widgetList<CheckboxListTile>(find.byType(CheckboxListTile))
      .toList();
  final titles = [for (final tile in tiles) (tile.title! as Text).data!];
  return titles..sort(
    (a, b) => tester
        .getTopLeft(_tile(a))
        .dy
        .compareTo(tester.getTopLeft(_tile(b)).dy),
  );
}

List<ChartSetting> _settings(WidgetTester tester, ChartHarness c) =>
    c.shell.container(tester).read(chartSettingsProvider).value!;

void main() {
  testWidgets('every chart is listed with its source, checked when enabled', (
    tester,
  ) async {
    final c = await _open(tester);
    await c.setEnabled(tester, 'new', enabled: false);

    expect(_shown(tester), ['HOT', 'NEW']);
    expect(tester.widget<CheckboxListTile>(_tile('HOT')).value, isTrue);
    expect(tester.widget<CheckboxListTile>(_tile('NEW')).value, isFalse);
    expect(
      find.descendant(of: _tile('HOT'), matching: find.text('Fake fmp-test')),
      findsOneWidget,
    );
  });

  testWidgets('unchecking writes enabled = false; checking it again writes '
      'true', (tester) async {
    final c = await _open(tester);

    await tester.tap(_tile('HOT'));
    await c.settle(tester);

    expect(_settings(tester, c), const [
      ChartSetting(pluginId: 'fmp-test', chartId: 'hot', enabled: false),
    ]);
    expect(tester.widget<CheckboxListTile>(_tile('HOT')).value, isFalse);
    // 停用的榜單留在清單上，可以再勾回來。
    expect(_shown(tester), ['HOT', 'NEW']);

    await tester.tap(_tile('HOT'));
    await c.settle(tester);
    expect(_settings(tester, c), const [
      ChartSetting(pluginId: 'fmp-test', chartId: 'hot', enabled: true),
    ]);
  });

  testWidgets('unchecking every chart is allowed', (tester) async {
    final c = await _open(tester);

    await tester.tap(_tile('HOT'));
    await c.settle(tester);
    await tester.tap(_tile('NEW'));
    await c.settle(tester);

    expect(
      {
        for (final setting in _settings(tester, c))
          setting.chartId: setting.enabled,
      },
      {'hot': false, 'new': false},
    );
  });

  testWidgets('dragging the handle writes sort_order for every chart', (
    tester,
  ) async {
    final c = await _open(tester, charts: const ['hot', 'new', 'old']);
    await c.setEnabled(tester, 'new', enabled: false);
    expect(_shown(tester), ['HOT', 'NEW', 'OLD']);
    final height = tester.getSize(_tile('HOT')).height;

    final handle = find.descendant(
      of: _tile('HOT'),
      matching: find.byIcon(Icons.drag_handle),
    );
    final gesture = await tester.startGesture(tester.getCenter(handle));
    for (var step = 0; step < 8; step++) {
      await gesture.moveBy(Offset(0, 2 * height / 8));
      await tester.pump(const Duration(milliseconds: 30));
    }
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 500));
    await c.settle(tester);

    // 整批寫入是一個 transaction：等它真的寫完（drift 要真的事件迴圈）。
    await c.settleUntil(
      tester,
      () => _settings(tester, c).every((setting) => setting.sortOrder != null),
    );

    expect(_shown(tester), ['NEW', 'OLD', 'HOT']);
    expect(
      {
        for (final setting in _settings(tester, c))
          setting.chartId: (setting.sortOrder, setting.enabled),
      },
      {'new': (0, false), 'old': (1, null), 'hot': (2, null)},
      reason: 'the order of all three, enabled untouched',
    );
  });

  /// 之後對 `chart_settings` 的寫入一律中止（插入與更新都擋）。
  Future<void> failWrites(WidgetTester tester, ChartHarness c) async {
    final database = c.shell.container(tester).read(appDatabaseProvider);
    for (final event in ['INSERT', 'UPDATE']) {
      await database.customStatement(
        'CREATE TRIGGER fail_chart_${event.toLowerCase()} BEFORE $event '
        "ON chart_settings BEGIN SELECT RAISE(ABORT, 'test'); END",
      );
    }
  }

  // 拖曳後先照新順序畫（樂觀更新）；寫入失敗時回到資料庫的順序並提示（同電台頁）。
  testWidgets('a reorder that fails to save goes back to the stored order', (
    tester,
  ) async {
    final c = await _open(tester, charts: const ['hot', 'new', 'old']);
    await failWrites(tester, c);
    final height = tester.getSize(_tile('HOT')).height;

    final handle = find.descendant(
      of: _tile('HOT'),
      matching: find.byIcon(Icons.drag_handle),
    );
    final gesture = await tester.startGesture(tester.getCenter(handle));
    for (var step = 0; step < 8; step++) {
      await gesture.moveBy(Offset(0, 2 * height / 8));
      await tester.pump(const Duration(milliseconds: 30));
    }
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 500));
    await c.settleUntil(
      tester,
      () => find
          .textContaining("Couldn't reorder the charts:")
          .evaluate()
          .isNotEmpty,
    );

    expect(_shown(tester), ['HOT', 'NEW', 'OLD'], reason: 'shown as stored');
    expect(_settings(tester, c), isEmpty);
  });

  testWidgets('a check that fails to save says so', (tester) async {
    final c = await _open(tester);
    await failWrites(tester, c);

    await tester.tap(_tile('HOT'));
    await c.settleUntil(
      tester,
      () => find
          .textContaining("Couldn't change the charts on Home:")
          .evaluate()
          .isNotEmpty,
    );

    expect(tester.widget<CheckboxListTile>(_tile('HOT')).value, isTrue);
    expect(_settings(tester, c), isEmpty);
  });

  testWidgets('the home section follows the settings', (tester) async {
    final c = await _open(tester);

    await tester.tap(_tile('HOT'));
    await c.settle(tester);
    await c.shell.open(tester, ShellDestination.home);
    await c.settle(tester);

    expect(
      find.descendant(of: find.byType(HomeCharts), matching: find.text('NEW')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: find.byType(HomeCharts), matching: find.text('HOT')),
      findsNothing,
    );
  });

  testWidgets('without a plugin that offers charts it explains', (
    tester,
  ) async {
    // 排行工作真的跑過（catalog 不是 null），只是插件沒有宣告 `charts`。
    final c = ChartHarness(declaresCharts: false);
    await c.pumpShell(tester, at: ShellDestination.settings);
    await tester.tap(find.widgetWithText(ListTile, 'Library'));
    await c.settle(tester);
    await tester.pumpAndSettle();

    expect(c.shell.container(tester).read(chartCatalogProvider), isEmpty);
    expect(find.byType(LibraryControls), findsOneWidget);
    expect(find.text('No source offers charts'), findsOneWidget);
    expect(find.byType(CheckboxListTile), findsNothing);
    // 沒有寫任何東西。
    expect(_settings(tester, c), isEmpty);
  });
}
