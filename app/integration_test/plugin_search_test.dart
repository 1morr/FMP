import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/app/app.dart';
import 'package:fmp/core/log/log.dart';
import 'package:fmp/plugins/plugins.dart';
import 'package:integration_test/integration_test.dart';

import '../test/support/fake_http.dart';
import '../test/support/no_network.dart';

/// 在真的平台上，用 App 打包的插件（資產裡的 manifest 與 `dist/plugin.js`）
/// 跑佔位畫面的搜尋（票 08）：證明四個平台都載得到插件、fjs 引擎跑得動
/// 插件。網路換成假的回應，零聯網；真的打 B 站是手動實跑（票的驗收）。
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  installNoNetworkGuard();

  testWidgets('the placeholder page searches through the bundled plugins', (
    tester,
  ) async {
    final logDir = Directory.systemTemp.createTempSync('fmp_it_search_');
    final log = await Log.open(logDir, minimumLevel: LogLevel.debug);
    final http = FakeHttp(
      (request) => request.uri.host == 'api.bilibili.com'
          ? FakeResponse.json({
              'code': 0,
              'message': '0',
              'data': {
                'result': [
                  {
                    'type': 'video',
                    'bvid': 'BV1it411c7mD',
                    'title': '<em class="keyword">晴天</em> 測試',
                    'author': '測試作者',
                    'duration': '4:05',
                  },
                ],
              },
            })
          : const FakeResponse(404),
    );
    final host = PluginHost(
      bundles: await loadBundledPlugins(rootBundle),
      log: log,
      httpAdapter: http,
    );
    addTearDown(() async {
      await host.close();
      await log.close();
      logDir.deleteSync(recursive: true);
    });
    expect(host.plugins.map((p) => p.manifest.id), contains('bilibili'));

    await tester.pumpWidget(
      buildRoot(
        overrides: [
          logProvider.overrideWithValue(log),
          pluginHostProvider.overrideWith((_) => host),
        ],
      ),
    );
    await tester.enterText(find.byType(TextField), '晴天');
    await tester.tap(find.byIcon(Icons.search));

    final deadline = DateTime.now().add(const Duration(seconds: 20));
    while (find.text('晴天 測試').evaluate().isEmpty &&
        DateTime.now().isBefore(deadline)) {
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }

    expect(find.text('Bilibili'), findsOneWidget);
    expect(find.text('晴天 測試'), findsOneWidget);
    expect(find.text('測試作者 · 4:05'), findsOneWidget);
    expect(http.requests.single.uri.queryParameters['keyword'], '晴天');
  });
}
