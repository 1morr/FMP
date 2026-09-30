import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/redaction/redaction_lists.dart';
import 'package:fmp/core/redaction/redactor.dart';

// 所有憑證都是明顯的假值（FAKE_…），不得換成真實值。
void main() {
  late Redactor redactor;
  setUp(() => redactor = Redactor());

  group('header list', () {
    test('replaces the whole value of a listed header', () {
      expect(
        redactor.redact('Cookie: SESSDATA=FAKE_SESSDATA_123; theme=dark'),
        'Cookie: ***',
      );
      expect(
        redactor.redact('{"Authorization":"FAKE_AUTH_123","Accept":"*/*"}'),
        '{"Authorization":"***","Accept":"*/*"}',
      );
      expect(
        redactor.redact('set-cookie: FAKE_COOKIE_123\nnext line'),
        'set-cookie: ***\nnext line',
      );
    });

    test('replaces a bare authorization value', () {
      expect(
        redactor.redact('sent Bearer FAKE_BEARER_123 upstream'),
        'sent Bearer *** upstream',
      );
      expect(
        redactor.redact('SAPISIDHASH 1_FAKEHASH123 was rejected'),
        'SAPISIDHASH *** was rejected',
      );
    });

    test('a bare Bearer or Basic value is replaced in any case', () {
      expect(
        redactor.redact(
          'bearer FAKE.JWT_123-abc, BEARER FAKEbearer9 and Basic RkFLRTpGQUtF==',
        ),
        'bearer ***, BEARER *** and Basic ***',
      );
      expect(redactor.redact('basic FAKEONLYLETTERSTOKENXYZ;'), 'basic ***;');
    });

    test('leaves words that only look like a header alone', () {
      for (final text in [
        'cookies are disabled; the bearer of news',
        'the bearer of bad news',
        'Basic information about the Bearer protocol',
        'basic 1234567 is too short',
      ]) {
        expect(redactor.redact(text), text);
      }
    });
  });

  group('key list', () {
    test('replaces values in queries, cookies and JSON bodies', () {
      expect(
        redactor.redact('/x/player?access_key=FAKE_ACCESS_KEY_123&bvid=BV1'),
        '/x/player?access_key=***&bvid=BV1',
      );
      expect(
        redactor.redact('SESSDATA=FAKE_SESSDATA_123; bili_jct=FAKE_JCT_123'),
        'SESSDATA=***; bili_jct=***',
      );
      expect(
        redactor.redact('{"csrf": "FAKE_CSRF_123", "id": 1}'),
        '{"csrf": "***", "id": 1}',
      );
    });

    test('a listed name also covers names that end with it', () {
      expect(
        redactor.redact('refresh_token=FAKE_REFRESH_123 x-csrf-token=FAKE_X'),
        'refresh_token=*** x-csrf-token=***',
      );
    });

    test('keeps commas inside a value together', () {
      expect(
        redactor.redact('SESSDATA=FAKE_A,1700000000,FAKE_B*11 rest'),
        'SESSDATA=*** rest',
      );
    });

    test('a quoted value is replaced up to its closing quote', () {
      expect(
        redactor.redact(r'{"password": "FAKE PASS \"PHRASE\" 123", "id": 1}'),
        '{"password": "***", "id": 1}',
      );
      expect(
        redactor.redact("{'token': 'FAKE TOKEN 123', 'id': 1}"),
        "{'token': '***', 'id': 1}",
      );
    });

    test('JSON escaped inside another JSON string', () {
      expect(
        redactor.redact(
          r'{"body":"{\"SESSDATA\":\"FAKE_SESSDATA_123\",\"x\":1}"}',
        ),
        r'{"body":"{\"SESSDATA\":\"***\",\"x\":1}"}',
      );
    });

    test('a URL-encoded query inside another query', () {
      expect(
        redactor.redact(
          'redirect=https%3A%2F%2Fexample.com%2F%3Faccess_key%3DFAKE_KEY_123'
          ' and double%253Faccess_key%253DFAKE_KEY_456',
        ),
        'redirect=https%3A%2F%2Fexample.com%2F%3Faccess_key%3D***'
        ' and double%253Faccess_key%253D***',
      );
    });

    test('names that only end like a listed name without a value stay', () {
      const text = 'tokens are refreshed; the csrf check passed';
      expect(redactor.redact(text), text);
    });
  });

  group('header values in lists', () {
    test('a JSON or Dart list of cookies is replaced whole', () {
      expect(
        redactor.redact(
          '{"set-cookie":["fake_auth=FAKE_ONE_123","other=FAKE_TWO_123"],'
          '"accept":["*/*"]}',
        ),
        '{"set-cookie":[***],"accept":["*/*"]}',
      );
      expect(
        redactor.redact('{set-cookie: [fake_auth=FAKE_ONE_123, x=FAKE_TWO]}'),
        '{set-cookie: [***]}',
      );
    });
  });

  group('URLs', () {
    test('userinfo is replaced for any host', () {
      expect(
        redactor.redact('proxy https://fake_user:FAKE_PASS_123@example.com/a'),
        'proxy https://***@example.com/a',
      );
      const noUserInfo =
          'mail fake@example.com via https://example.com/a?b=c@d';
      expect(redactor.redact(noUserInfo), noUserInfo);
    });

    test('a CDN URL is found with any scheme case', () {
      expect(
        redactor.redact('HTTPS://cn-fake.bilivideo.com/a.m4s?upsig=FAKE_UP_1'),
        'https://cn-fake.bilivideo.com/a.m4s',
      );
    });

    test('a CDN URL with JSON-escaped slashes', () {
      expect(
        redactor.redact(
          r'{\"url\":\"https:\/\/cn-fake.bilivideo.com\/a.m4s'
          r'?upsig=FAKE_UP_1&platform=pc\"}',
        ),
        r'{\"url\":\"https://cn-fake.bilivideo.com/a.m4s?platform=pc\"}',
      );
      const otherHost = r'\"https:\/\/example.com\/a?sig=1\"';
      expect(redactor.redact(otherHost), otherHost);
    });

    test('a percent-encoded CDN URL inside another URL', () {
      expect(
        redactor.redact(
          'http://127.0.0.1:1/?url=https%3A%2F%2Fcn-fake.bilivideo.com%2F'
          'a.m4s%3Fupsig%3DFAKE_UP_1%26platform%3Dpc',
        ),
        'http://127.0.0.1:1/?url=https%3A%2F%2Fcn-fake.bilivideo.com%2F'
        'a.m4s%3Fplatform%3Dpc',
      );
      const otherHost = 'u=https%3A%2F%2Fexample.com%2Fa%3Fsig%3D1';
      expect(redactor.redact(otherHost), otherHost);
      // 不合法的 UTF-8 與百分比編碼不會讓整段放棄遮蔽。
      expect(
        redactor.redact(
          'https%3A%2F%2Fcn-fake.bilivideo.com%2F%FF%zz.m4s%3Fupsig%3DFAKE_UP_2',
        ),
        isNot(contains('FAKE_UP_2')),
      );
    });
  });

  test('very long input finishes without overflowing the regex stack', () {
    // 「分組 + `+`」的寫法在 1MB 的值上會 Stack Overflow。
    final inputs = [
      'SESSDATA=${'x' * 1000000}',
      '"token": "${'x' * 1000000}"',
      '"token": "${r'\"' * 300000}"',
      '\\"token\\":\\"${'x' * 1000000}',
      'Cookie: [${'x' * 1000000}',
      'Cookie: ${'x' * 1000000}',
      'https://cn-fake.bilivideo.com/${r'\/' * 500000}',
      'https%3A%2F%2F${'a' * 1000000}',
      'bearer ${'a' * 1000000}',
    ];
    for (final input in inputs) {
      expect(() => redactor.redact(input), returnsNormally);
    }
  });

  group('media CDN', () {
    test('strips signed parameters and keeps the others', () {
      expect(
        redactor.redact(
          'GET https://upos-sz-mirrorcos.bilivideo.com/upgcxcode/1/2/x.m4s'
          '?e=FAKE_E_PAYLOAD&deadline=1700000000&upsig=FAKE_UPSIG_123'
          '&platform=pc failed',
        ),
        'GET https://upos-sz-mirrorcos.bilivideo.com/upgcxcode/1/2/x.m4s'
        '?platform=pc failed',
      );
      expect(
        redactor.redact(
          'https://rr1---sn-fake.googlevideo.com/videoplayback'
          '?expire=1700000000&ip=203.0.113.9&itag=251&sig=FAKE_SIG_123',
        ),
        'https://rr1---sn-fake.googlevideo.com/videoplayback?itag=251',
      );
    });

    test('replaces a signed path except the file name', () {
      expect(
        redactor.redact(
          'http://m701.music.126.net/20260929120000/FAKEHASH0123456789/'
          'jdymusic/obj/a.mp3?authSecret=FAKE_SECRET_123',
        ),
        'http://m701.music.126.net/***/***/***/***/a.mp3',
      );
    });

    test('leaves URLs of other hosts alone', () {
      const text = 'https://example.com/a?e=1&sig=2&deadline=3';
      expect(redactor.redact(text), text);
    });

    test('a plugin can add its own CDN', () {
      const url = 'https://cdn.fake-source.test/a.mp3?token2=FAKE_T&q=1';
      expect(redactor.redact(url), url);

      redactor.addRules(
        mediaCdns: [
          const MediaCdn(
            host: 'fake-source.test',
            signedQueryParameters: {'token2'},
          ),
        ],
      );

      expect(redactor.redact(url), 'https://cdn.fake-source.test/a.mp3?q=1');
    });

    test('Bilibili stream URLs lose the device id and the Akamai token', () {
      expect(
        redactor.redact(
          'https://upos-hz-mirrorakam.akamaized.net/x.m4s?gen=playurlv3'
          '&hdnts=exp=1~hmac=FAKE_HMAC_1&bw=1&buvid=FAKE_BUVID_1',
        ),
        'https://upos-hz-mirrorakam.akamaized.net/x.m4s?gen=playurlv3&bw=1',
      );
    });

    test('a plugin rule adds to a built-in rule for the same host', () {
      const url =
          'https://upos-fake.bilivideo.com/a.m4s?upsig=FAKE_UP_3&fake_sig=FAKE_S&q=1';

      redactor.addRules(
        mediaCdns: [
          const MediaCdn(
            host: 'upos-fake.bilivideo.com',
            signedQueryParameters: {'fake_sig'},
          ),
        ],
      );

      expect(redactor.redact(url), 'https://upos-fake.bilivideo.com/a.m4s?q=1');
    });

    test('a signed path from any matching rule applies', () {
      const url = 'https://m1.fake-source.test/111/222/a.mp3?q=1';

      redactor.addRules(
        mediaCdns: [
          const MediaCdn(
            host: 'fake-source.test',
            signedQueryParameters: {'x'},
          ),
          const MediaCdn(host: 'm1.fake-source.test', signedPath: true),
        ],
      );

      expect(
        redactor.redact(url),
        'https://m1.fake-source.test/***/***/a.mp3?q=1',
      );
    });
  });

  group('plugin lists', () {
    test('added header and key names apply from then on', () {
      const text = 'X-Fake-Auth: FAKE_H_123 fake_ticket=FAKE_K_123';
      expect(redactor.redact(text), text);

      redactor.addRules(
        headerNames: ['X-Fake-Auth'],
        keyNames: ['fake_ticket'],
      );

      expect(redactor.redact(text), 'X-Fake-Auth: ***');
      expect(
        redactor.redact('fake_ticket=FAKE_K_123 done'),
        'fake_ticket=*** done',
      );
    });
  });

  group('known credential values', () {
    test('are replaced verbatim, raw and URL-encoded, until unregistered', () {
      redactor.registerSecret('FAKE,SECRET/123');

      expect(
        redactor.redact('a FAKE,SECRET/123 b FAKE%2CSECRET%2F123 c'),
        'a *** b *** c',
      );

      redactor.unregisterSecret('FAKE,SECRET/123');
      expect(redactor.redact('a FAKE,SECRET/123'), 'a FAKE,SECRET/123');
    });

    test('lower-case percent escapes of a registered value', () {
      redactor.registerSecret('FAKE,SECRET/123');

      expect(
        redactor.redact('a FAKE%2csecret%2f123 b'),
        isNot(contains('***')),
      );
      expect(redactor.redact('a FAKE%2cSECRET%2f123 b'), 'a *** b');
    });

    test('values too short to replace safely are rejected', () {
      expect(() => redactor.registerSecret('abc'), throwsArgumentError);
    });
  });

  group('redactValue', () {
    test('recurses into maps and lists and returns JSON-safe values', () {
      redactor.registerSecret('FAKE_REGISTERED_123');
      final result = redactor.redactValue({
        'request': {
          'headers': {'cookie': 'anything', 'Accept': 'text/plain'},
          'items': [
            'note FAKE_REGISTERED_123',
            {'access_token': 'FAKE_TOKEN_123'},
            3,
            true,
            null,
            double.nan,
            Uri.parse('https://example.com/?SESSDATA=FAKE_SESSDATA_123'),
          ],
        },
      });

      expect(result, {
        'request': {
          'headers': {'cookie': '***', 'Accept': 'text/plain'},
          'items': [
            'note ***',
            {'access_token': '***'},
            3,
            true,
            null,
            'NaN',
            'https://example.com/?SESSDATA=***',
          ],
        },
      });
    });

    test('a toString that throws does not break redaction', () {
      expect(redactor.redactObject(_Throws()), contains('_Throws'));
    });
  });
}

final class _Throws {
  @override
  String toString() => throw StateError('no');
}
