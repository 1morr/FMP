import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/app/app.dart';
import 'package:fmp/app/i18n/strings.g.dart';
import 'package:fmp/core/log/log.dart';
import 'package:fmp/platform/audio_backend.dart';
import 'package:fmp/playback/playback.dart';
import 'package:fmp/plugins/plugins.dart';
import 'package:fmp/ui/now_playing/mini_player.dart';
import 'package:fmp/ui/now_playing/transport_bar.dart';
import 'package:fmp/ui/queue/queue_page.dart';
import 'package:fmp/ui/shell/app_shell.dart';
import 'package:fmp/ui/shell/destination.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import '../test/support/fake_http.dart';
import '../test/support/local_audio_server.dart';
import '../test/support/no_network.dart';
import '../test/support/shell.dart';

/// M1 佇列的主要流程（票 07）：搜尋、從選單把兩首加入佇列，第一首在這個
/// 平台真的音訊後端上播完後自動接第二首，佇列頁讀回播放順序。
///
/// 零聯網：插件的請求重播假的回應；兩首的串流都指向本機的
/// [LocalAudioServer]，長度只有幾秒，等得到播完。
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  installNoNetworkGuard();

  Map<String, Object?> ok(Object? data) => {
    'code': 0,
    'message': '0',
    'data': data,
  };

  testWidgets('two tracks added to the queue play one after the other on '
      "this platform's audio backend", (tester) async {
    final logDir = Directory.systemTemp.createTempSync('fmp_it_queue_');
    final log = await Log.open(logDir, minimumLevel: LogLevel.debug);
    final cdn = (await tester.runAsync(
      () => LocalAudioServer.start(
        length: const Duration(seconds: 3),
        requiredHeaders: {'Referer': 'https://www.bilibili.com'},
        requireBrowserUserAgent: true,
      ),
    ))!;
    Map<String, Object?> video(String bvid, String title) => {
      'type': 'video',
      'bvid': bvid,
      'title': title,
      'author': '測試作者',
      'duration': '0:03',
    };
    final http = FakeHttp(
      (request) => switch (request.uri.path) {
        '/x/web-interface/search/type' => FakeResponse.json(
          ok({
            'result': [
              video('BV1it411c7mD', '第一首'),
              video('BV1it411c7mE', '第二首'),
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
                  'baseUrl': cdn.url().toString(),
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

    final controls = find.byWidgetPredicate(
      (w) => w is MiniPlayer || w is TransportBar,
    );
    Finder inControls(Finder f) => find.descendant(of: controls, matching: f);

    Future<void> addToQueue(int row) async {
      await tester.tap(find.byTooltip('更多').at(row));
      await tester.pumpAndSettle();
      await tester.tap(find.text('加入佇列'));
      await tester.pumpAndSettle();
    }

    await openSearch(tester);
    await tester.enterText(find.byType(TextField), '晴天');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await waitFor(find.text('第二首'));

    // 佇列是空的：加入第一首就開始播（票 07 的決定）；第二首排在後面。
    await addToQueue(0);
    await waitFor(inControls(find.text('第一首')));
    await addToQueue(1);
    await waitFor(find.text('播放中'));

    // 第一首（3 秒）播完，自動接第二首。
    await waitFor(inControls(find.text('第二首')), seconds: 45);
    await waitFor(find.text('播放中'));

    // 佇列頁：第一首播過了，正在播第二首。
    GoRouter.of(tester.element(find.byType(AppShell)))
        .go(Destination.queue.path);
    await waitFor(find.byType(QueuePage));
    final page = find.byType(QueuePage);
    expect(
      find.descendant(of: page, matching: find.text('第一首')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: page, matching: find.text('第二首')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: page, matching: find.text('已播放 1 首')),
      findsOneWidget,
    );
    expect(
      http.requests.where((r) => r.uri.path == '/x/player/playurl'),
      hasLength(2),
    );
  });
}
