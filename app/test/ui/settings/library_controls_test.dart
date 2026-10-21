import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/charts/chart_jobs.dart';
import 'package:fmp/data/providers.dart';
import 'package:fmp/data/repositories/account_repository.dart';
import 'package:fmp/data/repositories/chart_settings_repository.dart';
import 'package:fmp/plugins/source_dto.dart';
import 'package:fmp/plugins/source_plugin.dart';
import 'package:fmp/ui/charts/home_charts.dart';
import 'package:fmp/ui/settings/library_controls.dart';
import 'package:fmp/ui/shell/app_shell.dart';
import 'package:material_ui/material_ui.dart';

import '../../library/fake_import_plugin.dart';
import '../../playback/fake_source_plugin.dart';
import '../charts/chart_harness.dart';
import '../support/shell_harness.dart';

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

  // 「匹配目標音源」（M4 PR 19，design §8.3、§10.10）：已啟用、能搜能播的插件；取消勾選寫
  // `match_target = false`、拖曳整批寫 `match_rank`，寫入失敗退回並提示（同「首頁排行」）。
  group('match targets', () {
    FakeSourcePlugin source(String id, String name) => FakeSourcePlugin(
      (_) => const [],
      id: id,
      name: name,
      onSearch: (_) => const SearchPage(items: [], hasMore: false),
    );

    /// 開設定頁的「音樂庫」，插件清單是 [sources]。
    Future<ShellHarness> openTargets(
      WidgetTester tester, {
      List<SourcePlugin>? sources,
    }) async {
      final h = ShellHarness(
        registryOfSources: true,
        sources:
            sources ??
            [
              source('alpha', 'Alpha'),
              source('beta', 'Beta'),
              source('gamma', 'Gamma'),
              // 不能播的（Spotify 這種）不是目標。
              FakeImportPlugin(id: 'meta', resolveStream: false),
            ],
      );
      await h.pumpShell(tester, size: const Size(1000, 1400));
      await h.open(tester, ShellDestination.settings);
      await h.loadSettings(tester);
      await tester.tap(find.widgetWithText(ListTile, 'Library'));
      await settle(tester, h);
      expect(find.byType(MatchTargetSettings), findsOneWidget);
      return h;
    }

    Finder targetTile(String name) => find.descendant(
      of: find.byType(MatchTargetSettings),
      matching: find.widgetWithText(CheckboxListTile, name),
    );

    List<String> shownTargets(WidgetTester tester) {
      final tiles = find.descendant(
        of: find.byType(MatchTargetSettings),
        matching: find.byType(CheckboxListTile),
      );
      final names = [
        for (final tile in tester.widgetList<CheckboxListTile>(tiles))
          (tile.title! as Text).data!,
      ];
      return names..sort(
        (a, b) => tester
            .getTopLeft(targetTile(a))
            .dy
            .compareTo(tester.getTopLeft(targetTile(b)).dy),
      );
    }

    Future<List<MatchTargetSetting>> stored(
      WidgetTester tester,
      ShellHarness h,
    ) async => (await tester.runAsync(
      () => h
          .container(tester)
          .read(sourceSettingsRepositoryProvider)
          .watchMatchTargets()
          .first,
    ))!;

    Future<void> drag(WidgetTester tester, String name, int rows) async {
      final height = tester.getSize(targetTile(name)).height;
      final handle = find.descendant(
        of: targetTile(name),
        matching: find.byIcon(Icons.drag_handle),
      );
      final gesture = await tester.startGesture(tester.getCenter(handle));
      for (var step = 0; step < 8; step++) {
        await gesture.moveBy(Offset(0, rows * height / 8));
        await tester.pump(const Duration(milliseconds: 30));
      }
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 500));
    }

    testWidgets('every enabled plugin that searches and plays is listed and '
        'checked', (tester) async {
      await openTargets(tester);

      expect(shownTargets(tester), ['Alpha', 'Beta', 'Gamma']);
      for (final name in ['Alpha', 'Beta', 'Gamma']) {
        expect(tester.widget<CheckboxListTile>(targetTile(name)).value, isTrue);
      }
    });

    testWidgets('unchecking writes match_target = false; checking again '
        'writes true', (tester) async {
      final h = await openTargets(tester);

      await tester.tap(targetTile('Beta'));
      await settle(tester, h);

      expect(await stored(tester, h), const [
        MatchTargetSetting(pluginId: 'beta', target: false),
      ]);
      expect(
        tester.widget<CheckboxListTile>(targetTile('Beta')).value,
        isFalse,
      );
      expect(shownTargets(tester), ['Alpha', 'Beta', 'Gamma']);

      await tester.tap(targetTile('Beta'));
      await settle(tester, h);
      expect(await stored(tester, h), const [
        MatchTargetSetting(pluginId: 'beta', target: true),
      ]);
    });

    testWidgets('dragging the handle writes match_rank for every plugin', (
      tester,
    ) async {
      final h = await openTargets(tester);

      await drag(tester, 'Alpha', 2);
      await settleUntil(
        tester,
        h,
        () async => (await stored(tester, h)).length == 3,
      );

      expect(shownTargets(tester), ['Beta', 'Gamma', 'Alpha']);
      expect(
        {
          for (final setting in await stored(tester, h))
            setting.pluginId: (setting.rank, setting.target),
        },
        {'beta': (0, null), 'gamma': (1, null), 'alpha': (2, null)},
      );
    });

    /// 之後對 `source_settings` 的寫入一律中止。
    Future<void> failWrites(WidgetTester tester, ShellHarness h) async {
      final database = h.container(tester).read(appDatabaseProvider);
      await tester.runAsync(() async {
        for (final event in ['INSERT', 'UPDATE']) {
          await database.customStatement(
            'CREATE TRIGGER fail_source_${event.toLowerCase()} BEFORE $event '
            "ON source_settings BEGIN SELECT RAISE(ABORT, 'test'); END",
          );
        }
      });
    }

    testWidgets('a reorder that fails to save goes back to the stored order', (
      tester,
    ) async {
      final h = await openTargets(tester);
      await failWrites(tester, h);

      await drag(tester, 'Alpha', 2);
      await settleUntil(
        tester,
        h,
        () async => find
            .textContaining("Couldn't reorder the match targets:")
            .evaluate()
            .isNotEmpty,
      );

      expect(shownTargets(tester), ['Alpha', 'Beta', 'Gamma']);
      expect(await stored(tester, h), isEmpty);
    });

    testWidgets('a check that fails to save says so and stays checked', (
      tester,
    ) async {
      final h = await openTargets(tester);
      await failWrites(tester, h);

      await tester.tap(targetTile('Alpha'));
      await settleUntil(
        tester,
        h,
        () async => find
            .textContaining("Couldn't change the match targets:")
            .evaluate()
            .isNotEmpty,
      );

      expect(
        tester.widget<CheckboxListTile>(targetTile('Alpha')).value,
        isTrue,
      );
      expect(await stored(tester, h), isEmpty);
    });

    testWidgets('without a plugin that searches and plays it explains', (
      tester,
    ) async {
      await openTargets(
        tester,
        sources: [FakeImportPlugin(id: 'meta', resolveStream: false)],
      );

      expect(find.text('No source to match against'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(MatchTargetSettings),
          matching: find.byType(CheckboxListTile),
        ),
        findsNothing,
      );
    });
  });
}

/// 資料庫的串流與重讀跑完（drift 要真的事件迴圈）。
Future<void> settle(WidgetTester tester, ShellHarness h) async {
  for (var i = 0; i < 3; i++) {
    await h.loadSettings(tester);
  }
  await tester.pump(const Duration(milliseconds: 50));
}

/// 等到 [done] 成立：真的事件迴圈與假時間輪流推進，最多約一秒。
Future<void> settleUntil(
  WidgetTester tester,
  ShellHarness h,
  Future<bool> Function() done,
) async {
  for (var i = 0; i < 50; i++) {
    if (await done()) return;
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 20));
  }
  fail('the condition never held');
}
