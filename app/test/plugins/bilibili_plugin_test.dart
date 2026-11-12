import 'dart:io';

import 'package:dio/dio.dart' show DioException;
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/core/log/log.dart';
import 'package:fmp/domain/audio_stream.dart';
import 'package:fmp/domain/track.dart';
import 'package:fmp/plugins/plugins.dart';

import '../support/fake_http.dart';
import '../support/fjs.dart';

/// bilibili 插件提交的打包產物（`app/plugins/bilibili/dist/plugin.js`）在
/// 真的引擎裡跑，網路換成手寫的假回應（零聯網），測錯誤代碼與轉換的細節。
/// 錄下來的真實回應由 `plugin_contract_test.dart` 重播。
void main() {
  late Directory logDir;
  late Log log;
  late PluginHost host;
  late FakeHttp http;
  late FakeResponse Function(Uri url) respond;

  setUpAll(loadFjsForTests);
  setUp(() async {
    logDir = Directory.systemTemp.createTempSync('fmp_bilibili_');
    log = await Log.open(logDir, minimumLevel: LogLevel.debug);
    http = FakeHttp((request) => respond(request.uri));
    host = PluginHost(
      bundles: [
        PluginBundle(
          manifest: File('plugins/bilibili/manifest.json').readAsStringSync(),
          code: File('plugins/bilibili/dist/plugin.js').readAsStringSync(),
        ),
      ],
      log: log,
      httpAdapter: http,
    );
  });
  tearDown(() async {
    await host.close();
    await log.close();
    logDir.deleteSync(recursive: true);
  });

  Plugin bilibili() => host.plugins.single;

  Map<String, Object?> ok(Object? data) => {
    'code': 0,
    'message': '0',
    'data': data,
  };

  test('the manifest declares search and resolveStream on the API host', () {
    expect(bilibili().manifest.id, 'bilibili');
    expect(bilibili().manifest.capabilities, {
      PluginCapability.search,
      PluginCapability.resolveStream,
    });
    expect(bilibili().manifest.allowsHost('api.bilibili.com'), isTrue);
  });

  test('search turns video results into tracks', () async {
    respond = (_) => FakeResponse.json(
      ok({
        'result': [
          {
            'type': 'video',
            'bvid': 'BV1xx411c7mD',
            'title': '<em class="keyword">晴天</em> 翻唱 &amp; 練習 &quot;1&quot;',
            'author': '某 UP 主',
            'duration': '4:05',
          },
          {
            'type': 'video',
            'bvid': 'BV1yy411c7mE',
            'title': '長影片',
            'author': '另一位',
            'duration': '1:02:03',
          },
          {
            'type': 'video',
            'bvid': 'BV1zz411c7mF',
            'title': '時長不明',
            'author': '第三位',
            'duration': '',
          },
        ],
      }),
    );

    expect(await bilibili().search('晴天 翻唱'), const [
      Track(
        source: 'bilibili',
        id: 'BV1xx411c7mD',
        title: '晴天 翻唱 & 練習 "1"',
        author: '某 UP 主',
        duration: Duration(minutes: 4, seconds: 5),
      ),
      Track(
        source: 'bilibili',
        id: 'BV1yy411c7mE',
        title: '長影片',
        author: '另一位',
        duration: Duration(hours: 1, minutes: 2, seconds: 3),
      ),
      Track(
        source: 'bilibili',
        id: 'BV1zz411c7mF',
        title: '時長不明',
        author: '第三位',
      ),
    ]);
  });

  test('search asks the video search API like a browser', () async {
    respond = (_) => FakeResponse.json(ok({'result': <Object>[]}));
    await bilibili().search('晴天 翻唱');

    final request = http.requests.single;
    expect(request.uri.host, 'api.bilibili.com');
    expect(request.uri.path, '/x/web-interface/search/type');
    expect(request.uri.queryParameters, {
      'search_type': 'video',
      'page': '1',
      'keyword': '晴天 翻唱',
    });
    expect(request.headers['User-Agent'], startsWith('Mozilla/5.0'));
    expect(request.headers['Referer'], 'https://search.bilibili.com/');
    expect(request.headers['Origin'], 'https://search.bilibili.com');
    expect(
      request.headers['Cookie'],
      matches(RegExp(r'^buvid3=[0-9A-F-]+infoc;')),
    );
  });

  test('no results is an empty list', () async {
    respond = (_) => FakeResponse.json(ok({'numResults': 0}));
    expect(await bilibili().search('zzzz'), isEmpty);
  });

  group('rate limiting becomes RateLimited', () {
    for (final code in [-352, -412, -509, -799]) {
      test('risk-control code $code', () async {
        respond = (_) => FakeResponse.json({'code': code, 'message': 'x'});
        await expectLater(bilibili().search('q'), throwsA(isA<RateLimited>()));
      });
    }
    for (final status in [412, 429]) {
      test('HTTP $status', () async {
        respond = (_) => FakeResponse(status, 'banned');
        await expectLater(bilibili().search('q'), throwsA(isA<RateLimited>()));
      });
    }
  });

  test('another API code is a ParseFailure', () async {
    respond = (_) => FakeResponse.json({'code': -400, 'message': '請求錯誤'});
    await expectLater(bilibili().search('q'), throwsA(isA<ParseFailure>()));
  });

  test('search maps the known API codes too', () async {
    respond = (_) => FakeResponse.json({'code': -10403, 'message': 'x'});
    await expectLater(
      bilibili().search('q'),
      throwsA(
        isA<Unavailable>().having(
          (e) => e.reason,
          'reason',
          UnavailableReason.region,
        ),
      ),
    );
  });

  test('a response that is not JSON is a ParseFailure', () async {
    respond = (_) => const FakeResponse(200, '<html>');
    await expectLater(bilibili().search('q'), throwsA(isA<ParseFailure>()));
  });

  test('a result without a bvid is a ParseFailure', () async {
    respond = (_) => FakeResponse.json(
      ok({
        'result': [
          {'title': 'x'},
        ],
      }),
    );
    await expectLater(bilibili().search('q'), throwsA(isA<ParseFailure>()));
  });

  test('a server error is a NetworkError', () async {
    respond = (_) => const FakeResponse(503, 'busy');
    await expectLater(bilibili().search('q'), throwsA(isA<NetworkError>()));
  });

  test('no connection is a NetworkError', () async {
    respond = (url) => throw DioException.connectionError(
      requestOptions: http.requests.last,
      reason: 'offline',
    );
    await expectLater(bilibili().search('q'), throwsA(isA<NetworkError>()));
  });
  group('resolveStream', () {
    // 2026-01-01 00:00:00 UTC。
    const deadline = 1767225600;
    String cdnUrl(int cid, {String deadlineParam = '$deadline'}) =>
        'https://upos-sz-mirror.bilivideo.com/upgcxcode/$cid-1-30280.m4s'
        '?e=ig8e&deadline=$deadlineParam&gen=playurlv2&upsig=abc123';

    /// 一支三個分 P 的影片：cid 是 101、102、103。
    FakeResponse pages(Uri url) => FakeResponse.json(
      ok([
        {'cid': 101, 'page': 1, 'part': '第一段', 'duration': 60},
        {'cid': 102, 'page': 2, 'part': '第二段', 'duration': 61},
        {'cid': 103, 'page': 3, 'part': '第三段', 'duration': 62},
      ]),
    );

    /// playurl 的 DASH 回應：兩條音訊軌，頻寬高的那條排在後面。
    FakeResponse playurl(Uri url, {String deadlineParam = '$deadline'}) {
      final cid = int.parse(url.queryParameters['cid']!);
      return FakeResponse.json(
        ok({
          'dash': {
            'audio': [
              {
                'id': 30216,
                'baseUrl': cdnUrl(cid + 9000, deadlineParam: deadlineParam),
                'bandwidth': 67000,
                'codecs': 'mp4a.40.2',
              },
              {
                'id': 30280,
                'baseUrl': cdnUrl(cid, deadlineParam: deadlineParam),
                'bandwidth': 132000,
                'codecs': 'mp4a.40.2',
              },
            ],
          },
        }),
      );
    }

    FakeResponse video(Uri url) => switch (url.path) {
      '/x/player/pagelist' => pages(url),
      '/x/player/playurl' => playurl(url),
      _ => const FakeResponse(404),
    };

    test('resolves the first part to its best DASH audio track', () async {
      respond = video;

      final stream = await bilibili().resolveStream('BV1xx411c7mD');
      // 媒體請求帶不含結尾斜線的 Referer 與瀏覽器的 User-Agent，不帶憑證：
      // 部分串流網址會拒絕播放器自己的 User-Agent（brief 事實 F4、F22）。
      expect(stream.headers, {
        'Referer': 'https://www.bilibili.com',
        'User-Agent': startsWith('Mozilla/5.0 '),
      });
      expect(
        stream,
        AudioStream(
          url: Uri.parse(cdnUrl(101)),
          headers: stream.headers,
          // 有效期讀自網址的 deadline（brief 事實 F5）。
          expiresAt: DateTime.utc(2026),
          codec: 'mp4a.40.2',
          bitrate: 132000,
        ),
      );
    });

    test('asks pagelist for the cid, then playurl for DASH audio', () async {
      respond = video;
      await bilibili().resolveStream('BV1xx411c7mD');

      final [pagelist, play] = http.requests;
      expect(pagelist.uri.host, 'api.bilibili.com');
      expect(pagelist.uri.path, '/x/player/pagelist');
      expect(pagelist.uri.queryParameters, {'bvid': 'BV1xx411c7mD'});
      expect(play.uri.path, '/x/player/playurl');
      // fnval=16 是 DASH，音訊是 m4a/AAC（brief 事實 F6）。
      expect(play.uri.queryParameters, {
        'bvid': 'BV1xx411c7mD',
        'cid': '101',
        'fnval': '16',
      });
      for (final request in http.requests) {
        expect(request.headers['User-Agent'], startsWith('Mozilla/5.0'));
        // API 要帶斜線的 Referer 加 Origin（brief 事實 F4）。
        expect(request.headers['Referer'], 'https://www.bilibili.com/');
        expect(request.headers['Origin'], 'https://www.bilibili.com');
        expect(
          request.headers['Cookie'],
          matches(RegExp(r'^buvid3=[0-9A-F-]+infoc;')),
        );
      }
    });

    test('each part of a video resolves to its own stream', () async {
      respond = video;

      final first = await bilibili().resolveStream('BV1xx411c7mD');
      final second = await bilibili().resolveStream('BV1xx411c7mD?p=2');
      final third = await bilibili().resolveStream('BV1xx411c7mD?p=3');

      expect(first.url, Uri.parse(cdnUrl(101)));
      expect(second.url, Uri.parse(cdnUrl(102)));
      expect(third.url, Uri.parse(cdnUrl(103)));
      expect(
        http.requests
            .where((r) => r.uri.path == '/x/player/playurl')
            .map((r) => r.uri.queryParameters['cid']),
        ['101', '102', '103'],
      );
    });

    test('a url without a readable deadline has no expiry', () async {
      // 例如 fixture 裡被遮蔽成 *** 的 deadline。
      respond = (url) => url.path == '/x/player/pagelist'
          ? pages(url)
          : playurl(url, deadlineParam: '***');
      final stream = await bilibili().resolveStream('BV1xx411c7mD');
      expect(stream.expiresAt, isNull);
      expect(stream.bitrate, 132000);
    });

    group('failures', () {
      Future<void> expectError(String trackId, Matcher matcher) =>
          expectLater(bilibili().resolveStream(trackId), throwsA(matcher));
      Matcher unavailable(UnavailableReason reason) =>
          isA<Unavailable>().having((e) => e.reason, 'reason', reason);

      test('a part the video does not have is NotFound', () async {
        respond = video;
        await expectError('BV1xx411c7mD?p=4', isA<NotFound>());
      });

      // ?p=1 不收：第一個分 P 的 id 是裸 bvid，一首曲目只有一個 id。
      for (final id in [
        '',
        'av170001',
        'BV1xx411c7mD?p=0',
        'BV1xx411c7mD?p=1',
        'BV1xx411c7mD#2',
      ]) {
        test(
          'a track id that is not a bvid part ("$id") is NotFound',
          () async {
            respond = video;
            await expectError(id, isA<NotFound>());
            expect(http.requests, isEmpty);
          },
        );
      }

      for (final (code, matcher) in [
        (-404, isA<NotFound>()),
        (62002, unavailable(UnavailableReason.copyright)),
        (62012, isA<ParseFailure>()),
        (-10403, unavailable(UnavailableReason.region)),
        (-352, isA<RateLimited>()),
        (-400, isA<ParseFailure>()),
      ]) {
        test('API code $code on pagelist', () async {
          respond = (url) => url.path == '/x/player/pagelist'
              ? FakeResponse.json({'code': code, 'message': 'x'})
              : video(url);
          await expectError('BV1xx411c7mD', matcher);
        });
        test('API code $code on playurl', () async {
          respond = (url) => url.path == '/x/player/playurl'
              ? FakeResponse.json({'code': code, 'message': 'x'})
              : video(url);
          await expectError('BV1xx411c7mD', matcher);
        });
      }

      test('HTTP 412 on playurl is RateLimited', () async {
        respond = (url) => url.path == '/x/player/playurl'
            ? const FakeResponse(412, 'banned')
            : video(url);
        await expectError('BV1xx411c7mD', isA<RateLimited>());
      });

      test('a playurl response without DASH audio is a ParseFailure', () async {
        respond = (url) => url.path == '/x/player/playurl'
            ? FakeResponse.json(
                ok({
                  'durl': [
                    {'url': 'https://example.com/a.flv'},
                  ],
                }),
              )
            : video(url);
        await expectError('BV1xx411c7mD', isA<ParseFailure>());
      });

      test('a pagelist entry without a cid is a ParseFailure', () async {
        respond = (url) => url.path == '/x/player/pagelist'
            ? FakeResponse.json(
                ok([
                  {'page': 1},
                ]),
              )
            : video(url);
        await expectError('BV1xx411c7mD', isA<ParseFailure>());
      });
    });
  });
}
