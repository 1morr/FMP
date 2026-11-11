import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/redaction/redact.dart';

void main() {
  group('masks', () {
    test('a Cookie header line', () {
      expect(
        redact('Cookie: SESSDATA=FAKE_SESS_123; bili_jct=FAKE_JCT_456'),
        'Cookie: ***',
      );
    });

    test('Authorization-type headers inside a printed header map', () {
      expect(
        redact(
          '{authorization: Bearer FAKE_TOKEN_1, user-agent: Mozilla/5.0, '
          'Proxy-Authorization: Basic RkFLRTpGQUtF, set-cookie: a=FAKE; Path=/}',
        ),
        '{authorization: ***, user-agent: Mozilla/5.0, '
        'Proxy-Authorization: ***, set-cookie: ***}',
      );
    });

    test(
      'sensitive key=value pairs in a query, a form body or a cookie string',
      () {
        expect(
          redact(
            'GET /x?access_token=FAKE_AT_1&keyword=lo-fi&csrf=FAKE_CSRF&ps=20',
          ),
          'GET /x?access_token=***&keyword=lo-fi&csrf=***&ps=20',
        );
        expect(
          redact('password=FAKE_PW&remember=1'),
          'password=***&remember=1',
        );
        expect(
          redact('jar SAPISID=FAKE_SID_1; PREF=hl=en; client_secret=FAKE'),
          'jar SAPISID=***; PREF=hl=en; client_secret=***',
        );
      },
    );

    test('sensitive JSON members, string or not, with escaped quotes', () {
      expect(
        redact(
          r'{"access_token":"FAKE_\"AT\"_1","expires_in":7200,'
          r'"Cookie": "SESSDATA=FAKE_S", "csrf" : 123456, "title":"token"}',
        ),
        r'{"access_token":"***","expires_in":7200,'
        r'"Cookie": "***", "csrf" : ***, "title":"token"}',
      );
    });

    test('every query value of a URL that carries a signature parameter', () {
      expect(
        redact(
          'play https://cdn.example.com/v/1.m4s?e=FAKE_E&oi=FAKE_IP'
          '&mid=FAKE_UID&deadline=1762000000&upsig=FAKE_SIG&bvc=vod ok',
        ),
        'play https://cdn.example.com/v/1.m4s?e=***&oi=***'
        '&mid=***&deadline=***&upsig=***&bvc=*** ok',
      );
      expect(
        redact('https://media.example.net/play?ip=FAKE_IP&sig=FAKE_SIG#t=3'),
        'https://media.example.net/play?ip=***&sig=***#t=3',
      );
    });

    test('a signed URL written JSON-escaped', () {
      expect(
        redact(
          r'{"baseUrl":"https:\/\/cdn.example.com\/v\/1.m4s'
          r'?e=FAKE_E\u0026upsig=FAKE_SIG\u0026os=FAKE"}',
        ),
        r'{"baseUrl":"https:\/\/cdn.example.com\/v\/1.m4s'
        r'?e=***\u0026upsig=***\u0026os=***"}',
      );
    });

    test('other headers whose name marks a secret', () {
      expect(
        redact('X-Csrf-Token: FAKE_CSRF\nX-Api-Key: FAKE_KEY\nAccept: */*'),
        'X-Csrf-Token: ***\nX-Api-Key: ***\nAccept: */*',
      );
      expect(
        redact('{x-auth-token: FAKE_T, accept: application/json}'),
        '{x-auth-token: ***, accept: application/json}',
      );
    });

    test('a bearer token without its header name', () {
      expect(
        redact('retrying with Bearer FAKE.JWT_1-x after 401'),
        'retrying with Bearer *** after 401',
      );
    });
  });

  group('leaves alone', () {
    // 名稱只是含有敏感字、但不是以它結尾的，也照原樣留著。
    const untouched = [
      'Search returned 20 results for "lo-fi beats" in 830ms',
      'https://api.example.com/x/search?keyword=token%20song&page=1'
          '&w_rid=abc123&wts=1762000000',
      'https://cdn.example.com/cover.jpg',
      'time 12:30:05 status: 412 retry-after: 3',
      '{"title":"Cookie Monster","author":"auth0r","duration":245}',
      'tokens_left=3&signal=5&session_count=2&sid_hint',
      'the bearer of bad news',
      '{user-agent: Mozilla/5.0, accept: */*}',
      '',
    ];
    for (final text in untouched) {
      test('"$text"', () => expect(redact(text), text));
    }
  });

  test('redacting twice gives the same text', () {
    const sample =
        'Cookie: a=FAKE\n'
        'GET https://cdn.example.com/1.m4s?e=FAKE&upsig=FAKE&x=1 token=FAKE\n'
        '{"refresh_token":"FAKE","n":1} Bearer FAKE_TOKEN_123';
    final once = redact(sample);
    expect(once, isNot(contains('FAKE')));
    expect(redact(once), once);
  });

  test('a megabyte-long secret does not overflow the regex stack', () {
    final long = 'a' * (1 << 20);
    expect(redact('token=$long&x=1'), 'token=***&x=1');
    final escaped = r'\"' * (1 << 18);
    expect(redact('{"token":"$escaped","x":1}'), '{"token":"***","x":1}');
    expect(redact('Cookie: $long'), 'Cookie: ***');
  });
}
