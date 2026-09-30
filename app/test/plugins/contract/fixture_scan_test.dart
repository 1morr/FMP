import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/network/allowed_hosts.dart';
import 'package:fmp/core/redaction/redactor.dart';

import 'contract_runner.dart';
import 'credential_scan.dart';
import 'fixture.dart';
import 'fixture_adapters.dart';

// fixture 掃描（ADR 0015 §如何確認：掃描所有 fixture 不得有未遮蔽憑證）與重播
// 的網址比對。掃描的兩道檢查各自有會紅與不該紅的案例。

HttpFixture _fixture({
  String url = 'https://api.fmp.test/search?page=1',
  Map<String, String> requestHeaders = const {},
  Map<String, List<String>> responseHeaders = const {},
  String? body,
  Object? jsonBody,
}) => HttpFixture(
  request: FixtureRequest(method: 'GET', url: url, headers: requestHeaders),
  response: FixtureResponse(
    status: 200,
    headers: responseHeaders,
    body: body,
    jsonBody: jsonBody,
  ),
);

List<String> _scan(HttpFixture fixture) =>
    scanFixture('001.json', fixture, Redactor(), CredentialNames());

const _redactedAgain = '001.json: request.url changes when redacted again';

void main() {
  test('every fixture in app/ is redacted', () {
    var scanned = 0;
    for (final directory in pluginDirectories(
      Directory('test/fixtures/plugins'),
    )) {
      final plugin = PluginDirectory.read(directory);
      final redactor = redactorFor(plugin.manifest);
      final names = CredentialNames.of(plugin.manifest);
      for (final list in plugin.fixtures.values) {
        for (final (:name, :fixture) in list) {
          expect(scanFixture(name, fixture, redactor, names), isEmpty);
          scanned++;
        }
      }
    }
    // 至少掃到 fmp-test-http 的兩個：否則這個測試什麼也沒證明。
    expect(scanned, greaterThanOrEqualTo(2));
  });

  group('the scan reports', () {
    test('a credential in the query (both checks)', () {
      expect(_scan(_fixture(url: 'https://api.fmp.test/s?access_key=abc12')), [
        _redactedAgain,
        '001.json: request.url has an unredacted "access_key"',
      ]);
    });

    test('a signed media URL (only the redaction function knows it)', () {
      expect(
        _scan(
          _fixture(
            url:
                'https://upos-sz.bilivideo.com/a.m4s?upsig=0123abcd&deadline=1',
          ),
        ),
        [_redactedAgain],
      );
    });

    test('a credential header', () {
      expect(
        _scan(_fixture(requestHeaders: {'cookie': 'SESSDATA=abc12'})),
        containsAll([
          '001.json: request.headers changes when redacted again',
          '001.json: request.headers.cookie is not redacted',
        ]),
      );
    });

    test('a Set-Cookie value', () {
      expect(
        _scan(
          _fixture(
            responseHeaders: {
              'set-cookie': ['buvid3=abc12; Path=/'],
            },
          ),
        ),
        containsAll([
          '001.json: response.headers changes when redacted again',
          '001.json: response.headers.set-cookie is not redacted',
        ]),
      );
    });

    test('a credential in a JSON body, however deep', () {
      expect(
        _scan(
          _fixture(
            jsonBody: {
              'data': [
                {'access_token': 'abc12'},
              ],
            },
          ),
        ),
        [
          '001.json: response.jsonBody changes when redacted again',
          '001.json: response.jsonBody.data[0].access_token is not redacted',
        ],
      );
    });

    test('a credential in a text body', () {
      expect(
        _scan(_fixture(body: 'ok; MUSIC_U=abc12; x=1')),
        contains('001.json: response.body ("MUSIC_U") is not redacted'),
      );
    });

    test('a credential in a list value', () {
      expect(
        _scan(_fixture(body: 'token=[abc12]; cb({"MUSIC_U":["abc12"]})')),
        containsAll([
          '001.json: response.body ("token") is not redacted',
          '001.json: response.body ("MUSIC_U") is not redacted',
        ]),
      );
    });

    test('a credential the redaction function was not told about', () {
      // 名單比對不經 Redactor：Redactor 沒登記這個鍵名（例如插件的追加名單沒接
      // 上）時，只有依名單直接看的那一道抓得到。
      expect(
        scanFixture(
          '001.json',
          _fixture(body: 'demo_session=abc12'),
          Redactor(),
          CredentialNames(keyNames: ['demo_session']),
        ),
        ['001.json: response.body ("demo_session") is not redacted'],
      );
    });
  });

  group('the scan passes', () {
    test('redacted values', () {
      expect(
        _scan(
          _fixture(
            url: 'https://api.fmp.test/s?access_key=***',
            requestHeaders: {'cookie': '***'},
            responseHeaders: {
              'set-cookie': ['buvid3=***; Path=/'],
            },
            jsonBody: {'token': '***', 'list': <Object?>[]},
          ),
        ),
        isEmpty,
      );
    });

    test('list values the redaction function redacted', () {
      // Redactor 把 `[` 開頭的值遮成 `[***]`（多值的 header、JSON 陣列）。
      final body = Redactor().redact('cb({"token":["abc12"]}); Cookie: [a=1]');

      expect(body, 'cb({"token":[***]}); Cookie: [***]');
      expect(_scan(_fixture(body: body)), isEmpty);
    });

    test('names that only look like credentials', () {
      expect(
        _scan(
          _fixture(
            url: 'https://api.fmp.test/s?bvid=BV1xx&tokens_used=3',
            body: 'no token here; tokenizer: whitespace',
            jsonBody: null,
          ),
        ),
        isEmpty,
      );
      expect(
        _scan(_fixture(jsonBody: {'tokens_used': 3, 'bvid': 'BV1xx'})),
        isEmpty,
      );
    });

    test('a fixture reformatted and re-read', () {
      final fixture = _fixture(
        url: 'https://api.fmp.test/s?access_key=***',
        jsonBody: {'b': 1, 'a': '***'},
      );
      final reread = HttpFixture.fromJson(
        jsonDecode(
          const JsonEncoder.withIndent('\t').convert(fixture.toJson()),
        ),
      );

      expect(_scan(reread), isEmpty);
    });
  });

  group('replay matching', () {
    Future<ReplayAdapter> replay(String recorded, String actual) async {
      final redactor = Redactor();
      final url = Uri.parse(recorded);
      final adapter = ReplayAdapter(
        [
          (
            name: '001.json',
            fixture: HttpFixture(
              request: FixtureRequest(
                method: 'GET',
                url: redactor.redact(recorded),
              ),
              response: const FixtureResponse(status: 200),
            ),
          ),
        ],
        redactor,
        AllowedHosts([if (!url.host.contains('evil')) url.host]),
      );
      await adapter.fetch(RequestOptions(path: actual), null, null);
      return adapter;
    }

    test('redacts the actual URL before comparing', () async {
      // 錄製時遮蔽拿掉的簽名參數（媒體 CDN），實際的請求一定帶著：比對前要
      // 以同一個遮蔽函式遮過實際的網址，兩邊才一樣。
      const signed =
          'https://upos-sz.bilivideo.com/a.m4s?upsig=0123abcd&deadline=1&x=1';
      final adapter = await replay(signed, signed);

      expect(adapter.problems, isEmpty);
      expect(adapter.unused, isEmpty);
    });

    test('reports a request outside allowedHosts that got through', () async {
      // 網路層本來就擋；adapter 再看一次，擋不住時契約測試會說出來。
      const url = 'https://api.evil.test/p';
      final adapter = await replay(url, url);

      expect(adapter.problems, [
        'request #1 went to api.evil.test, outside allowedHosts',
      ]);
    });

    bool matches(String fixture, String actual) =>
        fixtureUrlMatches(Uri.parse(fixture), Uri.parse(actual));

    test('ignores the order of the query', () {
      expect(
        matches('https://a.test/p?x=1&y=2', 'https://a.test/p?y=2&x=1'),
        isTrue,
      );
    });

    test('skips redacted values but not their names', () {
      expect(
        matches('https://a.test/p?k=***&x=1', 'https://a.test/p?x=1&k=9'),
        isTrue,
      );
      expect(
        matches('https://a.test/***/f.m4a', 'https://a.test/abc/f.m4a'),
        isTrue,
      );
      expect(matches('https://a.test/p?k=***', 'https://a.test/p'), isFalse);
    });

    test('compares everything else', () {
      expect(matches('https://a.test/p?x=1', 'https://a.test/p?x=2'), isFalse);
      expect(
        matches('https://a.test/p?x=1', 'https://a.test/p?x=1&y=2'),
        isFalse,
      );
      expect(matches('https://a.test/p', 'https://b.test/p'), isFalse);
      expect(matches('https://a.test/p', 'https://a.test/q'), isFalse);
      expect(matches('https://a.test/p', 'https://a.test:8443/p'), isFalse);
    });
  });
}
