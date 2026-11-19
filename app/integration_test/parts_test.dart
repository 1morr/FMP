import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/app/app.dart';
import 'package:fmp/app/i18n/strings.g.dart';
import 'package:fmp/core/log/log.dart';
import 'package:fmp/platform/audio_backend.dart';
import 'package:fmp/playback/playback.dart';
import 'package:fmp/playback/queue_controller.dart';
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

/// M1 的主要流程（票 15）：搜尋、從選單把一首加入佇列並開始播，臨時播放
/// 一支兩個分 P 的影片（點父列，整組當成一首），兩個分 P 在這個平台真的
/// 音訊後端上依序播完，才回到佇列原本那首、倒退 10 秒接著播。
///
/// 零聯網：插件的請求重播假的回應；佇列那首的串流指向 60 秒的
/// [LocalAudioServer]，分 P 的指向 3 秒的，等得到播完。
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  installNoNetworkGuard();

  Map<String, Object?> ok(Object? data) => {
    'code': 0,
    'message': '0',
    'data': data,
  };

  testWidgets('search, queue a track, play a group of parts temporarily; '
      'after the whole group it goes back to the queue track', (tester) async {
    final logDir = Directory.systemTemp.createTempSync('fmp_it_parts_');
    final log = await Log.open(logDir, minimumLevel: LogLevel.debug);
    final servers = (await tester.runAsync(
      () => Future.wait([
        for (final seconds in [60, 3])
          LocalAudioServer.start(
            length: Duration(seconds: seconds),
            requiredHeaders: {'Referer': 'https://www.bilibili.com'},
            requireBrowserUserAgent: true,
          ),
      ]),
    ))!;
    final (long, short) = (servers[0], servers[1]);
    Map<String, Object?> video(int aid, String bvid, String title, String d) =>
        {
          'type': 'video',
          'aid': aid,
          'bvid': bvid,
          'title': title,
          'author': '測試作者',
          'duration': d,
        };
    const single = 'BV1it411c7mD';
    const group = 'BV1it411c7mG';
    final http = FakeHttp(
      (request) => switch (request.uri.path) {
        '/x/web-interface/search/type' => FakeResponse.json(
          ok({
            'numPages': 1,
            'result': [
              video(11, single, '佇列那首', '1:00'),
              video(12, group, '分 P 合集', '0:06'),
            ],
          }),
        ),
        // 一頁一次的分 P 數（事實 F27）。
        '/x/v3/fav/resource/infos' => FakeResponse.json(
          ok([
            {'bvid': single, 'page': 1},
            {'bvid': group, 'page': 2},
          ]),
        ),
        '/x/player/pagelist' => FakeResponse.json(
          ok(
            request.uri.queryParameters['bvid'] == group
                ? [
                    {'cid': 21, 'page': 1, 'part': '第一段', 'duration': 3},
                    {'cid': 22, 'page': 2, 'part': '第二段', 'duration': 3},
                  ]
                : [
                    {'cid': 11, 'page': 1, 'part': '佇列那首', 'duration': 60},
                  ],
          ),
        ),
        '/x/player/playurl' => FakeResponse.json(
          ok({
            'dash': {
              'audio': [
                {
                  // 每段的網址不同，像真的 B 站。
                  'baseUrl':
                      (request.uri.queryParameters['cid'] == '11'
                              ? long
                              : short)
                          .url(
                            query: 'cid=${request.uri.queryParameters['cid']}',
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
        for (final server in servers) {
          await server.close();
        }
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
    final container = ProviderScope.containerOf(
      tester.element(find.byType(MaterialApp).first),
    );

    Future<void> waitUntil(
      bool Function() condition, {
      int seconds = 30,
      String? reason,
    }) async {
      final deadline = DateTime.now().add(Duration(seconds: seconds));
      while (!condition() && DateTime.now().isBefore(deadline)) {
        await tester.pump();
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
      }
      expect(condition(), isTrue, reason: reason);
    }

    Future<void> waitFor(Finder finder) =>
        waitUntil(() => finder.evaluate().isNotEmpty, reason: '$finder');

    // 不用 pumpAndSettle：正在播的那一列有跳動的等化器。
    Future<void> pumpFor(Duration duration) async {
      for (var i = 0; i * 50 < duration.inMilliseconds; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    PlaybackState? playback() => container.read(playbackProvider);
    bool playing(String title) =>
        playback()?.track.title == title &&
        playback()?.status == PlaybackStatus.playing;

    final controls = find.byWidgetPredicate(
      (w) => w is MiniPlayer || w is TransportBar,
    );

    await openSearch(tester);
    await tester.enterText(find.byType(TextField), '合集');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await waitFor(find.text('分 P 合集'));
    // 多 P 影片標分 P 數，可以展開。
    expect(find.text('2P'), findsOneWidget);
    expect(find.byTooltip('展開分 P'), findsOneWidget);

    // 佇列是空的：從選單加入就開始播（票 07）。
    await tester.tap(find.byTooltip('更多').first);
    await pumpFor(const Duration(milliseconds: 400));
    await tester.tap(find.text('加入佇列'));
    await pumpFor(const Duration(milliseconds: 400));
    await waitUntil(() => playing('佇列那首'), reason: 'queue track plays');
    // 播到 30 秒再離開，回來時從 20 秒接著播。
    await tester.runAsync(
      () => container
          .read(playbackProvider.notifier)
          .seek(const Duration(seconds: 30)),
    );
    await waitUntil(
      () => playback()!.position >= const Duration(seconds: 30),
      reason: 'seeked to 0:30',
    );

    // 點父列：整組當成一首臨時播放，從第一個分 P 開始。
    await playSearchResult(tester, find.text('分 P 合集'));
    await waitUntil(() => playing('第一段'), reason: 'part 1 plays');
    expect(
      find.descendant(of: controls, matching: find.text('臨時')),
      findsOneWidget,
    );
    expect(container.read(temporaryPlayProvider)!.group, hasLength(2));

    // 第一段播完接第二段，佇列還停在原本那首。
    await waitUntil(() => playing('第二段'), seconds: 45, reason: 'part 2 plays');
    expect(container.read(temporaryPlayProvider), isNotNull);
    expect(container.read(queueProvider).current!.track.title, '佇列那首');

    // 整組播完才回佇列原本那首，倒退 10 秒。
    await waitUntil(
      () => playing('佇列那首'),
      seconds: 45,
      reason: 'back to the queue track',
    );
    expect(container.read(temporaryPlayProvider), isNull);
    // 幾秒內要落在 20 秒附近（從頭播的話 5 秒內到不了 19 秒）。第二段是
    // 自己接過去的，回佇列也是，這時馬上 seek 曾讓 AVPlayer 停在 0:00（事實
    // K34）。
    await waitUntil(
      () {
        final at = playback()!.position;
        return at >= const Duration(seconds: 19) &&
            at < const Duration(seconds: 28);
      },
      seconds: 5,
      reason: 'resumed 10 s before 0:30, at ${playback()!.position}',
    );

    // 佇列頁：臨時播放沒有動佇列，只有原本那首。
    GoRouter.of(tester.element(find.byType(AppShell)))
        .go(Destination.queue.path);
    await waitFor(find.byType(QueuePage));
    final page = find.byType(QueuePage);
    expect(
      find.descendant(of: page, matching: find.text('佇列那首')),
      findsOneWidget,
    );
    expect(find.descendant(of: page, matching: find.text('第一段')), findsNothing);
    expect(container.read(queueProvider).entries, hasLength(1));
    expect(
      http.requests.where((r) => r.uri.path == '/x/v3/fav/resource/infos'),
      hasLength(1),
    );
  });
}
