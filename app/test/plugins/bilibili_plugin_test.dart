import 'dart:io';

import 'package:dio/dio.dart' show DioException;
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/core/log/log.dart';
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

  test('the manifest declares search on the API host', () {
    expect(bilibili().manifest.id, 'bilibili');
    expect(bilibili().manifest.capabilities, {PluginCapability.search});
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
}
