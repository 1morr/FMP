import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/network/fixture/fixture_adapters.dart';
import 'package:fmp/data/repositories/developer_settings_repository.dart';
import 'package:fmp/plugins/dev/dev_case_runs.dart';
import 'package:fmp/plugins/dev/plugin_development.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;

import '../../plugins/dev/dev_support.dart';
import '../../support/fake_http_adapter.dart';
import 'plugin_page_harness.dart';

// Debug 頁「插件開發」區塊與插件頁「開發中」標記的測試環境（M3 PR 16b）：一個開發資料夾，
// 裡面有 `fmp-test-http`（search 重播通過、resolveStream 重播不符）、`fmp-dev-login`
// （要登入的案例）與一個壞掉的插件目錄。

/// 上游：`fmp-test-http` 的 search，其餘 404。
ResponseBody devUpstream(RequestOptions options) =>
    options.uri.path == '/search'
    ? reply(
        200,
        body: jsonEncode({
          'list': [
            {'id': 'a1', 'name': 'Tone A', 'owner': 'FMP', 'ms': 2000},
            {'id': 'a2', 'name': 'Tone B', 'owner': 'FMP', 'ms': 3000},
          ],
          'more': false,
        }),
        headers: {'Content-Type': 'application/json'},
      )
    : reply(404);

/// 建好開發資料夾。[withBroken] 加一個載入失敗的插件目錄。
Directory buildDevFolder({bool withBroken = true}) {
  final root = tempFolder();
  final http = copyPlugin(fixturePlugin('http_test_plugin'), root, 'a-http');
  // resolveStream 的 fixture 對不上請求：重播不符。
  final fixture = File(
    p.join(http.path, 'fixtures', 'resolveStream', '001.json'),
  );
  fixture.writeAsStringSync(
    fixture.readAsStringSync().replaceFirst('/stream', '/other'),
  );
  final login = copyPlugin(fixturePlugin('test_plugin'), root, 'b-login');
  final script = scriptOf(login);
  script.writeAsStringSync(
    script.readAsStringSync().replaceFirst(
      '"id": "fmp-test"',
      '"id": "fmp-dev-login"',
    ),
  );
  if (withBroken) {
    final broken = Directory(p.join(root.path, 'c-broken'))..createSync();
    File(p.join(broken.path, 'broken.js')).writeAsStringSync(
      pluginScript('fmp-dev-broken')
          .replaceFirst('export function search', 'export function search('),
    );
  }
  return root;
}

/// 開好環境：資料庫裡設好資料夾，等載入完成。[open] 為真時導到 Debug 頁的「插件開發」。
Future<PluginPageHarness> openPluginDev(
  WidgetTester tester, {
  // 高：ListView 只建出畫面裡的卡片，功能測試要全部都在畫面內。
  Size size = const Size(1000, 2600),
  Brightness brightness = Brightness.light,
  bool pluginDevTools = true,
  Directory? folder,
  FakeFileDialogs? dialogs,
  FutureOr<ResponseBody> Function(RequestOptions options)? upstream,

  /// 先裝進資料庫的插件（安裝檔原文）。
  List<String> installed = const [],
}) async {
  final adapter = FakeHttpAdapter(upstream ?? devUpstream);
  final h = await PluginPageHarness.create(
    tester,
    dialogs: dialogs ?? FakeFileDialogs(),
    pluginDevTools: pluginDevTools,
    overrides: [
      caseTransportsProvider.overrideWithValue(
        CaseTransports(network: () => adapter),
      ),
    ],
  );
  if (installed.isNotEmpty) {
    await tester.runAsync(() async {
      for (final source in installed) {
        await h.install(source);
      }
    });
  }
  if (folder != null) {
    await tester.runAsync(
      () =>
          DeveloperSettingsRepository(h.plugins.database)
              .write(developerMode: true, pluginDevFolder: folder.path),
    );
  }
  await h.shell.pumpShell(
    tester,
    size: size,
    brightness: brightness,
    collapsePanel: true,
  );
  await tester.tap(find.text('Settings').first);
  await h.shell.loadSettings(tester);
  await tester.tap(find.widgetWithText(ListTile, 'Debug'));
  await h.shell.loadSettings(tester);
  await tester.pumpAndSettle();
  if (pluginDevTools) {
    await tester.tap(find.widgetWithText(ListTile, 'Plugin development'));
    await h.shell.loadSettings(tester);
    // 套用中有不確定進度的進度條，pumpAndSettle 等不到停：由 settleDev 等。
    if (folder == null) await tester.pumpAndSettle();
    if (folder != null) await settleDev(tester, h);
  }
  return h;
}

/// 等開發資料夾套用完（掃描在 isolate，要真的事件迴圈）。
Future<void> settleDev(WidgetTester tester, PluginPageHarness h) async {
  for (var i = 0; i < 400; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 25)),
    );
    await tester.pump(const Duration(milliseconds: 25));
    final state = h.container(tester).read(pluginDevelopmentProvider);
    if (state != null && !state.busy) {
      await tester.pumpAndSettle();
      return;
    }
  }
  fail('the development folder was not applied');
}

/// 等跑案例結束。
Future<void> settleCases(WidgetTester tester, PluginPageHarness h) async {
  for (var i = 0; i < 400; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 25)),
    );
    await tester.pump(const Duration(milliseconds: 25));
    if (!h.container(tester).read(devCaseRunsProvider).busy) {
      await tester.pumpAndSettle();
      return;
    }
  }
  fail('the cases did not finish');
}
