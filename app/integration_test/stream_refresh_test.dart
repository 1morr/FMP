import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/app/app.dart';
import 'package:fmp/app/i18n/strings.g.dart';
import 'package:fmp/core/log/log.dart';
import 'package:fmp/platform/audio_backend.dart';
import 'package:fmp/playback/playback.dart';
import 'package:fmp/plugins/plugins.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import '../test/support/fake_http.dart';
import '../test/support/local_audio_server.dart';
import '../test/support/no_network.dart';
import '../test/support/shell.dart';

/// 失敗處理（票 11）在這個平台真的音訊後端上：CDN 對第一次解析到的串流網址
/// 回 403（像過期或被拒的網址），App 重新解析一次、播第二次拿到的網址，
/// 不跳提示。原生播放器怎麼報 403 各平台不同（Android `code 0`、Apple
/// `-1102`、mpv 的 log），這裡證明它們都走到重新解析。
///
/// 零聯網：插件的請求重播假的回應，串流指向本機的 [LocalAudioServer]。
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  installNoNetworkGuard();

  Map<String, Object?> ok(Object? data) => {
    'code': 0,
    'message': '0',
    'data': data,
  };

  testWidgets('a stream the CDN refuses (403) is resolved again and plays', (
    tester,
  ) async {
    final logDir = Directory.systemTemp.createTempSync('fmp_it_refresh_');
    final log = await Log.open(logDir, minimumLevel: LogLevel.debug);
    final cdn = (await tester.runAsync(
      () => LocalAudioServer.start(
        requiredHeaders: {'Referer': 'https://www.bilibili.com'},
        requireBrowserUserAgent: true,
        refuse: (url) => url.queryParameters['upsig'] == 'REFUSED',
      ),
    ))!;
    // 第一次解析給被拒的網址，之後給好的。
    var resolves = 0;
    final http = FakeHttp(
      (request) => switch (request.uri.path) {
        '/x/web-interface/search/type' => FakeResponse.json(
          ok({
            'result': [
              {
                'type': 'video',
                'bvid': 'BV1it411c7mD',
                'title': '晴天 測試',
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
                  'baseUrl': cdn
                      .url(
                        query:
                            'deadline=4102444800&upsig='
                            '${resolves++ == 0 ? 'REFUSED' : 'FRESH'}',
                      )
                      .toString(),
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
    final backend = createAudioBackend(log);
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

    await openSearch(tester);
    await tester.enterText(find.byType(TextField), '晴天');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await waitFor(find.text('晴天 測試'));

    await playSearchResult(tester, find.text('晴天 測試'));
    await waitFor(find.text('播放中'));
    await waitFor(find.textContaining(RegExp(r'^0:0[1-9] / 0:30$')));

    final playurl = [
      for (final r in http.requests)
        if (r.uri.path == '/x/player/playurl') r,
    ];
    expect(playurl, hasLength(2));
    final refused = [
      for (final r in cdn.requests)
        if (r.query.contains('upsig=REFUSED')) r.status,
    ];
    expect(refused, isNotEmpty);
    expect(refused, everyElement(HttpStatus.forbidden));
    expect(
      cdn.requests.where((r) => r.query.contains('upsig=FRESH')),
      isNotEmpty,
    );
    // 重新解析成功就不提示。
    expect(find.textContaining('無法播放'), findsNothing);

    // log 每筆馬上寫進檔案（`Log.open`），不必先關。
    final text = File('${logDir.path}/${Log.fileName}').readAsStringSync();
    expect(text, contains('Playback failed: NetworkError'));
    expect(text, contains('from 127.0.0.1'));
    expect(text, contains('Resolving the stream again: bilibili/'));
  });
}
