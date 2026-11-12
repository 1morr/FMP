import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/app/app.dart';
import 'package:fmp/app/i18n/strings.g.dart';
import 'package:fmp/core/log/log.dart';
import 'package:fmp/plugins/plugins.dart';
import 'package:integration_test/integration_test.dart';

import '../test/support/fake_http.dart';
import '../test/support/no_network.dart';

/// 在真的平台上，用 App 打包的插件（資產裡的 manifest 與 `dist/plugin.js`）
/// 跑佔位畫面的搜尋（票 08）與點一首解析串流（票 10）：證明四個平台都載得到
/// 插件、fjs 引擎跑得動插件。網路換成假的回應，零聯網；真的打 B 站是手動
/// 實跑（票的驗收）。
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  installNoNetworkGuard();

  Map<String, Object?> ok(Object? data) => {
    'code': 0,
    'message': '0',
    'data': data,
  };

  testWidgets('the placeholder page searches and resolves a stream through '
      'the bundled plugins', (tester) async {
    final logDir = Directory.systemTemp.createTempSync('fmp_it_search_');
    final log = await Log.open(logDir, minimumLevel: LogLevel.debug);
    final http = FakeHttp(
      (request) => switch (request.uri.path) {
        '/x/web-interface/search/type' => FakeResponse.json(
          ok({
            'result': [
              {
                'type': 'video',
                'bvid': 'BV1it411c7mD',
                'title': '<em class="keyword">晴天</em> 測試',
                'author': '測試作者',
                'duration': '4:05',
              },
            ],
          }),
        ),
        '/x/player/pagelist' => FakeResponse.json(
          ok([
            {'cid': 4242, 'page': 1},
          ]),
        ),
        '/x/player/playurl' => FakeResponse.json(
          ok({
            'dash': {
              'audio': [
                {
                  'baseUrl':
                      'https://cdn.example.com/4242-1-30280.m4s'
                      '?deadline=1767225600&upsig=FAKE_SIG',
                  'bandwidth': 134695,
                  'codecs': 'mp4a.40.2',
                },
              ],
            },
          }),
        ),
        _ => const FakeResponse(404),
      },
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

    // 斷言用 zh-TW 的字串，不跟裝置語言走。
    LocaleSettings.setLocaleSync(AppLocale.zhTw);
    addTearDown(
      () => LocaleSettings.setLocaleSync(AppLocaleUtils.instance.baseLocale),
    );
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

    Future<void> waitFor(Finder finder) async {
      final deadline = DateTime.now().add(const Duration(seconds: 20));
      while (finder.evaluate().isEmpty && DateTime.now().isBefore(deadline)) {
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    }

    await waitFor(find.text('晴天 測試'));

    expect(find.text('Bilibili'), findsOneWidget);
    expect(find.text('晴天 測試'), findsOneWidget);
    expect(find.text('測試作者 · 4:05'), findsOneWidget);
    expect(http.requests.single.uri.queryParameters['keyword'], '晴天');

    // 點一首：解析串流，顯示音質與遮蔽過的網址（票 10）。
    await tester.tap(find.text('晴天 測試'));
    await waitFor(find.textContaining('kbps'));
    expect(find.text('音質：mp4a.40.2 · 135 kbps'), findsOneWidget);
    expect(
      find.text(
        '網址：https://cdn.example.com/4242-1-30280.m4s?deadline=1767225600&upsig=***',
      ),
      findsOneWidget,
    );
    expect(http.requests.last.uri.queryParameters['cid'], '4242');
  });
}
