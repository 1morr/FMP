import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/app/app.dart';
import 'package:fmp/app/i18n/strings.g.dart';
import 'package:fmp/core/log/log.dart';
import 'package:fmp/domain/audio_stream.dart';
import 'package:fmp/domain/track.dart';
import 'package:fmp/platform/audio_backend.dart';
import 'package:fmp/playback/audio_backend.dart';
import 'package:fmp/playback/playback.dart';
import 'package:fmp/playback/queue_controller.dart';
import 'package:fmp/plugins/plugins.dart';
import 'package:fmp/ui/home/home_page.dart';
import 'package:integration_test/integration_test.dart';

import '../test/support/fake_http.dart';
import '../test/support/fragmented_mp4.dart';
import '../test/support/local_audio_server.dart';
import '../test/support/no_network.dart';

/// 預載下一首（票 12）在這個平台真的音訊後端上：第一首出聲後預載第二首，
/// 第一首播完時原生播放器自己接過去、不再解析；預載的網址被 CDN 拒絕（403）
/// 時，換過去才報錯（AVPlayer 預載時不報，事實 I4），重新解析一次照樣播。
///
/// 零聯網：插件的請求重播假的回應，串流指向本機的 [LocalAudioServer]，兩首
/// 都是 6 秒的無聲 WAV。另有一支直接對後端：兩條帶索引的 fragmented MP4，
/// Apple 平台走 HLS 包裝（ADR 0040），像真的 B 站串流。
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  installNoNetworkGuard();

  const first = Track(
    ref: TrackRef(pluginId: 'bilibili', trackId: 'BV1it411c7mD'),
    title: '第一首',
    author: '測試作者',
    duration: Duration(seconds: 6),
  );
  const second = Track(
    ref: TrackRef(pluginId: 'bilibili', trackId: 'BV1xx411c7XY'),
    title: '第二首',
    author: '測試作者',
    duration: Duration(seconds: 6),
  );

  Map<String, Object?> ok(Object? data) => {
    'code': 0,
    'message': '0',
    'data': data,
  };

  /// 開 App、把兩首加進佇列（開始播第一首），等第二首出聲。[refuseFirst]
  /// 時 CDN 拒絕第二首第一次解析到的網址。回傳 playurl 的請求依 bvid 數、
  /// CDN 的請求與 log。
  Future<({Map<String, int> resolves, LocalAudioServer cdn, String log})>
  playBoth(WidgetTester tester, {required bool refuseFirst}) async {
    final logDir = Directory.systemTemp.createTempSync('fmp_it_preload_');
    final log = await Log.open(logDir, minimumLevel: LogLevel.debug);
    final cdn = (await tester.runAsync(
      () => LocalAudioServer.start(
        length: const Duration(seconds: 6),
        requiredHeaders: {'Referer': 'https://www.bilibili.com'},
        requireBrowserUserAgent: true,
        refuse: (url) => url.queryParameters['upsig'] == 'REFUSED',
      ),
    ))!;
    final resolves = <String, int>{};
    final http = FakeHttp((request) {
      final bvid = request.uri.queryParameters['bvid'] ?? '';
      return switch (request.uri.path) {
        '/x/player/pagelist' => FakeResponse.json(
          ok([
            {'cid': bvid.hashCode.abs(), 'page': 1},
          ]),
        ),
        '/x/player/playurl' => () {
          final n = resolves[bvid] = (resolves[bvid] ?? 0) + 1;
          final refused = refuseFirst && bvid == second.ref.trackId && n == 1;
          return FakeResponse.json(
            ok({
              'dash': {
                'audio': [
                  {
                    'baseUrl': cdn
                        .url(
                          query:
                              'track=$bvid&deadline=4102444800&upsig='
                              '${refused ? 'REFUSED' : 'FRESH$n'}',
                        )
                        .toString(),
                    'bandwidth': 134695,
                    'codecs': 'mp4a.40.2',
                  },
                ],
              },
            }),
          );
        }(),
        _ => const FakeResponse(404),
      };
    });
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
          // AVPlayer 把壞掉的預載報成 ready、長度 0 時（事實 I4）由看門狗
          // 接手；縮短門檻免得測試等 20 秒。
          stallTimeoutsProvider.overrideWithValue(
            const StallTimeouts(
              starting: Duration(seconds: 8),
              playing: Duration(seconds: 8),
            ),
          ),
        ],
      ),
    );
    await tester.pump();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(HomePage)),
    );

    String logText() =>
        File('${logDir.path}/${Log.fileName}').readAsStringSync();

    Future<void> until(bool Function() condition, {int seconds = 40}) async {
      final deadline = DateTime.now().add(Duration(seconds: seconds));
      while (!condition() && DateTime.now().isBefore(deadline)) {
        await tester.pump();
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
      }
      if (!condition()) {
        // ignore: avoid_print -- 等不到時把 App 的 log 留在輸出裡查原因。
        print('[preload log]\n${logText()}');
      }
      expect(condition(), isTrue);
    }

    bool playing(Track track) {
      final s = container.read(playbackProvider);
      return s?.track == track && s?.status == PlaybackStatus.playing;
    }

    await tester.runAsync(
      () => container.read(queueProvider.notifier).add([first, second]),
    );
    await until(() => playing(first));
    await until(
      () => logText().contains('Preloaded the next track: bilibili/BV1xx'),
    );
    await until(() => playing(second));
    // 第二首照著播下去。
    await until(
      () =>
          playing(second) &&
          container.read(playbackProvider)!.position >=
              const Duration(seconds: 2),
    );
    return (resolves: resolves, cdn: cdn, log: logText());
  }

  testWidgets('the next track is preloaded and played on without resolving '
      'it again', (tester) async {
    final result = await playBoth(tester, refuseFirst: false);

    expect(result.resolves, {first.ref.trackId: 1, second.ref.trackId: 1});
    expect(
      result.log,
      contains('Playing the preloaded stream: bilibili/BV1xx411c7XY'),
    );
    expect(result.log, isNot(contains('Playback failed')));
  });

  testWidgets('a preloaded stream the CDN refuses (403) is resolved again '
      'when its turn comes, and plays', (tester) async {
    final result = await playBoth(tester, refuseFirst: true);

    expect(result.resolves, {first.ref.trackId: 1, second.ref.trackId: 2});
    final refused = [
      for (final r in result.cdn.requests)
        if (r.query.contains('upsig=REFUSED')) r.status,
    ];
    expect(refused, everyElement(HttpStatus.forbidden));
    expect(
      result.log,
      contains('Resolving the stream again: bilibili/BV1xx411c7XY'),
    );
    // 這個平台怎麼報壞掉的預載（後端的錯誤或看門狗），重驗事實 I4 用。
    // ignore: avoid_print -- 記在閘門的輸出裡。
    print(
      '[preload 403] ${RegExp(r'(Playback failed: .*|Playback stalled: .*)').allMatches(result.log).map((m) => m[0]).join(' | ')}',
    );
  });

  testWidgets('streams played through HLS on Apple: the preloaded one takes '
      'over at the end and its position moves on', (tester) async {
    await tester.runAsync(() async {
      final logDir = Directory.systemTemp.createTempSync('fmp_it_preload_');
      final log = await Log.open(logDir, minimumLevel: LogLevel.debug);
      // 兩段各約 5 秒：第一條 10 秒、第二條 20 秒。
      final files = [FragmentedMp4(fragments: 2), FragmentedMp4(fragments: 4)];
      final servers = [
        for (final (i, file) in files.indexed)
          await LocalAudioServer.start(
            body: file.bytes,
            contentType: ContentType('video', 'mp4'),
            name: 'audio$i.m4s',
          ),
      ];
      // 索引那一小段由測試直接給（Dart 的連線在測試裡被擋）；片段照樣由
      // 原生播放器向假 CDN 要。
      final backend = createAudioBackend(
        log,
        fetchRange: (url, headers, range) async {
          final file = files[servers.indexWhere((s) => s.url() == url)];
          return Uint8List.sublistView(file.bytes, range.first, range.last + 1);
        },
      );
      addTearDown(() async {
        await tester.runAsync(() async {
          await backend.dispose();
          for (final server in servers) {
            await server.close();
          }
          await log.close();
        });
        logDir.deleteSync(recursive: true);
      });
      final streams = [
        for (final (i, server) in servers.indexed)
          AudioStream(url: server.url(), segmentBase: files[i].segmentBase),
      ];

      Future<AudioBackendState> until(bool Function(AudioBackendState) done) {
        if (done(backend.state)) return Future.value(backend.state);
        return backend.states
            .firstWhere(done)
            .timeout(
              const Duration(seconds: 30),
              onTimeout: () => fail('timed out at ${backend.state}'),
            );
      }

      await backend.load(streams[0]);
      await backend.play();
      await until((s) => s.status == AudioBackendStatus.ready && s.playing);
      await backend.preload(streams[1]);
      // 實跑量「播完接下一首」時先跳到結尾前幾秒；跳過再播完也要接得上。
      await backend.seek(files[0].duration - const Duration(seconds: 3));

      final completed = await until(
        (s) => s.status == AudioBackendStatus.completed,
      );
      expect(identical(completed.stream, streams[0]), isTrue);
      final moving = await until(
        (s) =>
            identical(s.stream, streams[1]) &&
            s.status == AudioBackendStatus.ready &&
            s.position > const Duration(seconds: 2),
      );
      expect(moving.playing, isTrue);
      expect(
        (moving.duration! - files[1].duration).abs(),
        lessThan(const Duration(seconds: 2)),
      );
    });
  });
}
