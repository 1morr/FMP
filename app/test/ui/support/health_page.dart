import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/repositories/plugin_repository.dart';
import 'package:fmp/plugins/manifest/plugin_file.dart';
import 'package:material_ui/material_ui.dart';

import '../../plugins/plugin_harness.dart';
import 'plugin_page_harness.dart';

// Debug 頁「音源健康檢查」區塊的測試環境：四個插件（有案例、沒有案例、停用、案例會失敗）。

const _script = '''
export async function search({ keyword }) {
const response = await fmp.http.request({ url: 'https://example.test/s' });
if (response.status !== 200) throw { fmpError: 'ParseError' };
return { items: [{ sourceId: 'a', title: 'Song' }], hasMore: false };
}
export async function loginVerify(credentials) {
return { userId: '42', displayName: 'Tester' };
}
''';

const _failing = '''
export async function search({ keyword }) {
throw { fmpError: 'RateLimited' };
}
export async function loginVerify(credentials) {
return { userId: '42', displayName: 'Tester' };
}
''';

const _checks =
    '{"search": {"input": {"keyword": "k", "page": 1}, '
    '"expect": {"minItems": 1, "nonEmpty": ["title"]}}, '
    '"login": {"input": {"cookies": {"SESSDATA": "***"}}, '
    '"expect": {"minItems": 1, "nonEmpty": ["userId"]}, "requiresLogin": true}}';

/// 開到 Debug 頁的健康檢查區塊。
Future<void> openHealth(
  WidgetTester tester, {
  Size size = const Size(1000, 900),
  Brightness brightness = Brightness.light,
  bool unreadable = false,
}) async {
  final p = await PluginPageHarness.create(tester);
  Future<void> install(
    String id, {
    String script = _script,
    String? checks = _checks,
    bool enabled = true,
  }) async {
    final source = pluginSource(
      script,
      id: id,
      capabilities: ['search', 'login'],
      login: '{"methods": ["cookie"]}',
    );
    final file = PluginFile.parse(source);
    await p.plugins.plugins.install(
      InstalledPlugin(
        id: id,
        version: '1.0.0',
        manifestJson: file.manifestJson,
        script: source,
        installedAt: DateTime.utc(2026, 10, 14),
        checksJson: checks,
      ),
    );
    if (!enabled) await p.plugins.plugins.setEnabled(id, enabled: false);
  }

  await tester.runAsync(() async {
    await install('plugin-a');
    await install('plugin-b', checks: null);
    await install('plugin-c', enabled: false);
    await install('plugin-d', script: _failing);
    // checks_json 讀不懂的插件（只在要它的測試裡裝）。
    if (unreadable) await install('plugin-e', checks: '{"search": 1}');
  });
  final h = p.shell;
  await h.pumpShell(
    tester,
    size: size,
    brightness: brightness,
    collapsePanel: true,
  );
  await tester.tap(find.text('Settings').first);
  await h.loadSettings(tester);
  await tester.tap(find.widgetWithText(ListTile, 'Debug'));
  await h.loadSettings(tester);
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(ListTile, 'Source health check'));
  await h.loadSettings(tester);
  await tester.pumpAndSettle();
}

/// 等這一輪跑完（插件在背景 isolate，要真的事件迴圈）。
Future<void> settleHealth(WidgetTester tester) async {
  for (var i = 0; i < 400; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 25)),
    );
    // 假時間也要往前走：網路層的限流與重試用 Timer 等待。
    await tester.pump(const Duration(milliseconds: 25));
    final all = find.widgetWithText(FilledButton, 'Check all');
    if (tester.widget<FilledButton>(all).onPressed != null) {
      // 按鈕從停用回到啟用有色彩動畫：等它結束，對比的量測才是穩定的顏色。
      await tester.pumpAndSettle();
      return;
    }
  }
  fail('the health check did not finish');
}
