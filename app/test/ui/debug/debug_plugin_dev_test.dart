import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/plugins/dev/dev_case_runs.dart';
import 'package:fmp/plugins/dev/plugin_development.dart';
import 'package:fmp/ui/debug/debug_log.dart';
import 'package:fmp/ui/debug/debug_plugin_dev.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;

import '../../plugins/dev/dev_support.dart'
    show copyPlugin, setVersion, tempFolder;
import '../support/plugin_dev_page.dart';
import '../support/plugin_page_harness.dart';

// Debug 頁的「插件開發」區塊（M3 PR 16b，design §3.6）。載入與跑案例的規則在
// test/plugins/dev/，這裡看呈現與按鈕狀態。

Finder _card(String name) =>
    find.ancestor(of: find.text(name), matching: find.byType(Card));

Finder _inCard(String name, Finder finder) =>
    find.descendant(of: _card(name), matching: finder);

/// [capability] 那一列的執行鈕。
Finder _run(String card, String capability) => find.descendant(
  of: find.ancestor(
    of: _inCard(card, find.text(capability)),
    matching: find.byType(ListTile),
  ),
  matching: find.byType(IconButton),
);

void main() {
  testWidgets('without a chosen folder it says so and only offers choosing', (
    tester,
  ) async {
    final h = await openPluginDev(tester);

    expect(find.byType(DebugPluginDev), findsOneWidget);
    expect(find.text('No folder selected'), findsOneWidget);
    expect(
      tester
          .widget<ButtonStyleButton>(
            find.ancestor(
              of: find.text('Choose folder'),
              matching: find.bySubtype<ButtonStyleButton>(),
            ),
          )
          .onPressed,
      isNotNull,
    );
    for (final label in ['Rescan', 'Unload']) {
      expect(
        tester
            .widget<ButtonStyleButton>(
              find.ancestor(
                of: find.text(label),
                matching: find.bySubtype<ButtonStyleButton>(),
              ),
            )
            .onPressed,
        isNull,
        reason: label,
      );
    }
    expect(h.dialogs!.directoryPicks, 0);
  });

  testWidgets('choosing a folder loads its plugins', (tester) async {
    final folder = buildDevFolder();
    final dialogs = FakeFileDialogs()..directory = folder.path;
    final h = await openPluginDev(tester, dialogs: dialogs);

    await tester.tap(find.text('Choose folder'));
    await h.shell.loadSettings(tester);
    await settleDev(tester, h);

    expect(dialogs.directoryPicks, 1);
    expect(find.text('Plugin fmp-test-http'), findsNothing);
    expect(find.text('FMP HTTP Test Plugin'), findsOneWidget);
  });

  testWidgets('shows the three kinds of cards and the folder', (tester) async {
    final folder = buildDevFolder();
    final page = await openPluginDev(tester, folder: folder);
    expect(find.text('In development'), findsNWidgets(2));
    expect(find.text('Failed to load'), findsOneWidget);
    expect(find.text('fmp-test-http · 1.0.0'), findsOneWidget);
    expect(find.text('FMP Test Plugin'), findsOneWidget);
    // 壞掉的腳本：載入失敗，原因（已遮蔽）顯示在卡片上。
    expect(
      _inCard('fmp-dev-broken', find.text('Failed to load')),
      findsOneWidget,
    );
    expect(
      _inCard(
        'fmp-dev-broken',
        find.byWidgetPredicate(
          (widget) =>
              widget is SelectableText &&
              (widget.data ?? '').startsWith('ParseError'),
        ),
      ),
      findsOneWidget,
    );
    expect(page.container(tester).read(pluginDevelopmentProvider), isNotNull);
  });

  testWidgets('folder problems are shown translated', (tester) async {
    final folder = buildDevFolder(withBroken: false);
    // 同 id 的第二個目錄：只載入第一個，資料夾層級的問題。
    copyPlugin(Directory(p.join(folder.path, 'a-http')), folder, 'z-http-copy');

    await openPluginDev(tester, folder: folder);

    expect(
      find.text(
        'a-http and z-http-copy have the same plugin id "fmp-test-http"; '
        'only a-http is loaded',
      ),
      findsOneWidget,
    );
  });

  testWidgets('a missing folder says so', (tester) async {
    final folder = Directory(p.join(tempFolder().path, 'gone'));

    await openPluginDev(tester, folder: folder);

    expect(find.text('The folder does not exist'), findsOneWidget);
  });

  testWidgets('a plugin that replaces an installed one says which version', (
    tester,
  ) async {
    final folder = buildDevFolder(withBroken: false);
    final installed = File(p.join(folder.path, 'a-http', 'http_test_plugin.js'))
        .readAsStringSync()
        .replaceFirst('"version": "1.0.0"', '"version": "0.5.0"');

    await openPluginDev(tester, folder: folder, installed: [installed]);

    expect(find.text('Replaces installed 0.5.0'), findsOneWidget);
  });

  testWidgets('replay runs show passed and failed rows that expand', (
    tester,
  ) async {
    final folder = buildDevFolder(withBroken: false);
    final h = await openPluginDev(tester, folder: folder);

    await tester.tap(_inCard('FMP HTTP Test Plugin', find.text('Run all')));
    await settleCases(tester, h);

    expect(find.textContaining('Passed · '), findsOneWidget);
    expect(find.textContaining('Failed · '), findsOneWidget);
    expect(find.textContaining('Replay'), findsWidgets);
    // 通過的列展開：回傳值。
    await tester.tap(_inCard('FMP HTTP Test Plugin', find.text('search')));
    await tester.pumpAndSettle();
    expect(find.text('Return value'), findsOneWidget);
    expect(find.textContaining('Tone A'), findsOneWidget);
    // 失敗的列展開：重播對不上的說明。
    await tester.tap(
      _inCard('FMP HTTP Test Plugin', find.text('resolveStream')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is SelectableText &&
            (widget.data ?? '').contains(
              'does not match fixtures/resolveStream',
            ),
      ),
      findsOneWidget,
    );
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is SelectableText &&
            (widget.data ?? '').contains('Error type: '),
      ),
      findsOneWidget,
    );
  });

  testWidgets('choosing record shows the warning', (tester) async {
    final h = await openPluginDev(
      tester,
      folder: buildDevFolder(withBroken: false),
    );
    expect(
      find.textContaining('Recording uses the real network'),
      findsNothing,
    );

    await tester.tap(_inCard('FMP HTTP Test Plugin', find.text('Record')));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Recording uses the real network'),
      findsOneWidget,
    );
    expect(
      h.container(tester).read(devCaseRunsProvider).modeOf('fmp-test-http'),
      CaseMode.record,
    );
  });

  testWidgets('a case that needs a login says so when not logged in', (
    tester,
  ) async {
    final h = await openPluginDev(
      tester,
      folder: buildDevFolder(withBroken: false),
    );
    await tester.tap(_inCard('FMP Test Plugin', find.text('Real')));
    await tester.pumpAndSettle();

    await tester.tap(_run('FMP Test Plugin', 'login'));
    await settleCases(tester, h);

    expect(find.text('Skipped: needs a login, not logged in'), findsOneWidget);
  });

  testWidgets('while a case runs every run button is disabled', (tester) async {
    final release = Completer<void>();
    final h = await openPluginDev(
      tester,
      folder: buildDevFolder(withBroken: false),
      upstream: (options) async {
        await release.future;
        return devUpstream(options);
      },
    );
    await tester.tap(_inCard('FMP HTTP Test Plugin', find.text('Real')));
    await tester.pumpAndSettle();

    await tester.tap(_run('FMP HTTP Test Plugin', 'search'));
    for (var i = 0; i < 200; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 10));
      if (find.byType(CircularProgressIndicator).evaluate().isNotEmpty) break;
    }

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    final runAll = find.ancestor(
      of: find.text('Run all'),
      matching: find.bySubtype<ButtonStyleButton>(),
    );
    for (final button in runAll.evaluate()) {
      expect((button.widget as ButtonStyleButton).onPressed, isNull);
    }
    expect(
      tester.widget<IconButton>(_run('FMP Test Plugin', 'search')).onPressed,
      isNull,
    );
    // 模式切換也停用（那個插件在跑）。
    final segment = tester.widget<SegmentedButton<CaseMode>>(
      find.descendant(
        of: _card('FMP HTTP Test Plugin'),
        matching: find.byType(SegmentedButton<CaseMode>),
      ),
    );
    expect(segment.onSelectionChanged, isNull);

    release.complete();
    await settleCases(tester, h);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('View log opens the Log section filtered to the plugin', (
    tester,
  ) async {
    await openPluginDev(tester, folder: buildDevFolder(withBroken: false));

    await tester.tap(_inCard('FMP HTTP Test Plugin', find.text('View log')));
    await tester.pumpAndSettle();

    final log = tester.widget<DebugLog>(find.byType(DebugLog));
    expect(log.initialTag, 'fmp-test-http');
    // 篩選下拉選單顯示該 tag。
    expect(
      find.descendant(
        of: find.byType(DropdownButton<String?>),
        matching: find.text('fmp-test-http'),
      ),
      findsWidgets,
    );

    // 之後從清單點 Log 不帶篩選。
    await tester.tap(find.widgetWithText(ListTile, 'Plugin development'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, 'Log & errors'));
    await tester.pumpAndSettle();
    expect(tester.widget<DebugLog>(find.byType(DebugLog)).initialTag, isNull);
  });

  testWidgets('Reload reports the new version', (tester) async {
    final folder = buildDevFolder(withBroken: false);
    final h = await openPluginDev(tester, folder: folder);
    setVersion(Directory(p.join(folder.path, 'a-http')), '1.0.1');

    await tester.tap(_inCard('FMP HTTP Test Plugin', find.text('Reload')));
    await settleDev(tester, h);

    expect(find.text('Reloaded FMP HTTP Test Plugin 1.0.1'), findsOneWidget);
    expect(find.text('fmp-test-http · 1.0.1'), findsOneWidget);
  });
}
