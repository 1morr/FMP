import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/app/app.dart';
import 'package:fmp/app/i18n/strings.g.dart';
import 'package:fmp/core/log/log.dart';
import 'package:fmp/platform/audio_backend.dart';
import 'package:fmp/playback/playback.dart';
import 'package:fmp/plugins/plugins.dart';
import 'package:integration_test/integration_test.dart';

import '../test/support/fake_http.dart';
import '../test/support/local_audio_server.dart';
import '../test/support/no_network.dart';

/// M0 的主要流程（plan〈測試策略〉）：在佔位畫面搜尋、點一首、播放、暫停、繼續。
/// 在真的平台上跑 App 打包的 bilibili 插件（fjs 引擎）與這個平台的音訊後端
/// （`platform/audio_backend.dart` 挑的原生播放器）。
///
/// 零聯網：插件的請求重播假的回應；串流網址指向本機的 [LocalAudioServer]，
/// 它像 B 站 CDN 一樣只在帶了 Referer 與瀏覽器的 User-Agent 時才回音訊
/// （brief 事實 F4、F22），所以播得起來就證明插件給的 header 帶到了原生
/// 播放器的請求上。真的打 B 站是手動實跑（票的驗收）。
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  installNoNetworkGuard();

  Map<String, Object?> ok(Object? data) => {
    'code': 0,
    'message': '0',
    'data': data,
  };

  testWidgets('search, tap a track, and it plays, pauses and resumes on this '
      "platform's audio backend", (tester) async {
    final logDir = Directory.systemTemp.createTempSync('fmp_it_play_');
    final log = await Log.open(logDir, minimumLevel: LogLevel.debug);
    // 插件的 resolveStream 給的 header（brief 事實 F4、F22）。
    final cdn = (await tester.runAsync(
      () => LocalAudioServer.start(
        requiredHeaders: {'Referer': 'https://www.bilibili.com'},
        requireBrowserUserAgent: true,
      ),
    ))!;
    final streamUrl = cdn.url(query: 'deadline=1767225600&upsig=FAKE_SIG');
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
                'duration': '0:30',
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
                  'baseUrl': streamUrl.toString(),
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
    final backend = createAudioBackend();
    addTearDown(() async {
      // 先停播放器再關伺服器；只有這一個播放器（事實 W5）。
      await tester.runAsync(() async {
        await backend.dispose();
        await cdn.close();
        await host.close();
        await log.close();
      });
      logDir.deleteSync(recursive: true);
    });

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
          audioBackendProvider.overrideWithValue(backend),
        ],
      ),
    );

    Future<void> waitFor(Finder finder, {int seconds = 30}) async {
      final deadline = DateTime.now().add(Duration(seconds: seconds));
      while (finder.evaluate().isEmpty && DateTime.now().isBefore(deadline)) {
        await tester.pump();
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
      }
      expect(finder, findsWidgets);
    }

    await tester.enterText(find.byType(TextField), '晴天');
    await tester.tap(find.byIcon(Icons.search));
    await waitFor(find.text('晴天 測試'));
    expect(find.text('Bilibili'), findsOneWidget);
    expect(find.text('測試作者 · 0:30'), findsOneWidget);
    expect(http.requests.single.uri.queryParameters['keyword'], '晴天');

    // 點一首：解析串流（票 10），交給原生播放器播放（票 11）。
    await tester.tap(find.text('晴天 測試'));
    await waitFor(find.textContaining('kbps'));
    expect(find.text('音質：mp4a.40.2 · 135 kbps'), findsOneWidget);
    expect(
      find.text(
        '網址：${streamUrl.replace(query: 'deadline=1767225600&upsig=***')}',
      ),
      findsOneWidget,
    );
    expect(http.requests.last.uri.queryParameters['cid'], '4242');

    await waitFor(find.text('播放中'));
    // 進度在走：位置過了 1 秒（長度是假 CDN 的 30 秒）。
    await waitFor(find.textContaining(RegExp(r'^0:0[1-9] / 0:30$')));
    expect(cdn.requests, isNotEmpty);
    for (final request in cdn.requests) {
      expect(request.headers['referer'], 'https://www.bilibili.com');
      expect(request.headers['user-agent'], startsWith('Mozilla/'));
    }

    await tester.tap(find.byTooltip('暫停'));
    await waitFor(find.text('已暫停'));
    await tester.tap(find.byTooltip('播放'));
    await waitFor(find.text('播放中'));
  });
}
