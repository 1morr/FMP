import 'package:flutter_test/flutter_test.dart';

import 'credential_scan.dart';
import 'fixture.dart';
import 'ip_scrub.dart';

import 'package:fmp/core/redaction/redactor.dart';

// 錄製者的公網 IP 不得進 fixture：scrubIpAddresses 的雙向案例，以及掃描。
// 測試裡的「公網」位址都是隨手寫的，不是任何人的位址。

void main() {
  group('scrubIpAddresses replaces', () {
    test('an IPv4 in a JSON string value', () {
      expect(
        scrubIpAddresses('{"remoteHost":"93.184.216.34","hl":"en"}'),
        '{"remoteHost":"$scrubbedIpv4","hl":"en"}',
      );
    });

    test('an IPv4 in a positional array element', () {
      expect(
        scrubIpAddresses('[[null,"x","8.8.4.4",1],[2,3]]'),
        '[[null,"x","$scrubbedIpv4",1],[2,3]]',
      );
    });

    test('an IPv4 in a URL path segment', () {
      expect(
        scrubIpAddresses('https://m.example.test/api/ip/151.101.1.69/id/abc'),
        'https://m.example.test/api/ip/$scrubbedIpv4/id/abc',
      );
    });

    test('a Chrome UA version (`N.0.0.0`) stays', () {
      expect(
        scrubIpAddresses('Chrome/156.0.0.0 Safari'),
        'Chrome/156.0.0.0 Safari',
      );
    });

    test('a version-like address that is not `N.0.0.0` is still replaced', () {
      expect(scrubIpAddresses('Chrome/156.1.2.3'), 'Chrome/$scrubbedIpv4');
    });

    test('a global IPv6 address, compressed or not', () {
      expect(
        scrubIpAddresses('a 2a00:1450:4001:81b::200e b'),
        'a $scrubbedIpv6 b',
      );
      expect(
        scrubIpAddresses('"2606:4700:4700:0:0:0:0:1111"'),
        '"$scrubbedIpv6"',
      );
    });

    test('every occurrence', () {
      expect(
        scrubIpAddresses('8.8.8.8,1.1.1.1'),
        '$scrubbedIpv4,$scrubbedIpv4',
      );
    });
  });

  group('scrubIpAddresses leaves alone', () {
    for (final text in [
      '2.20260128.05.00',
      '12:34:56',
      '2026-10-08T12:34:56.789Z',
      '203.0.113.77',
      '198.51.100.7',
      '192.0.2.9',
      '127.0.0.1',
      '0.0.0.0',
      '2001:db8::5',
      '2001:0DB8:0:0:0:0:0:5',
      '[1,2,3,4,5]',
      '1.2.3',
      '1.2.3.4.5',
      '256.1.1.1',
      'abcd:ef01:2345',
      '2026:10:08:12',
    ]) {
      test(text, () => expect(scrubIpAddresses(text), text));
    }
  });

  group('the scan', () {
    HttpFixture fixture({String? body, Object? jsonBody, String? url}) =>
        HttpFixture(
          request: FixtureRequest(
            method: 'POST',
            url: url ?? 'https://api.fmp.test/search',
            body: '{"remoteHost":"93.184.216.34"}',
          ),
          response: FixtureResponse(
            status: 200,
            body: body,
            jsonBody: jsonBody,
          ),
        );

    test('names the file and the place of an IP address', () {
      expect(ipProblems('001.json', fixture(body: 'ok')), [
        '001.json: fixture.request.body has an IP address',
      ]);
      expect(
        ipProblems(
          '002.json',
          fixture(
            url: 'https://a.fmp.test/ip/8.8.8.8/x',
            jsonBody: {
              'list': [
                null,
                ['151.101.1.69'],
              ],
            },
          ),
        ),
        [
          '002.json: fixture.request.url has an IP address',
          '002.json: fixture.request.body has an IP address',
          '002.json: fixture.response.jsonBody.list[1][0] has an IP address',
        ],
      );
    });

    test('scanFixture reports it, and the scrubbed fixture passes', () {
      final names = CredentialNames();
      final dirty = fixture(jsonBody: ['151.101.1.69']);
      expect(
        scanFixture('001.json', dirty, Redactor(), names),
        contains('001.json: fixture.response.jsonBody[0] has an IP address'),
      );
      final clean = scrubFixtureIps(dirty);
      expect(scanFixture('001.json', clean, Redactor(), names), isEmpty);
      expect(clean.response.jsonBody, [scrubbedIpv4]);
      expect(clean.request.body, '{"remoteHost":"$scrubbedIpv4"}');
    });

    test('a fixture with only documentation addresses passes', () {
      final clean = HttpFixture(
        request: const FixtureRequest(
          method: 'GET',
          url: 'https://a.fmp.test/ip/203.0.113.77/x',
        ),
        response: const FixtureResponse(status: 200, body: '2001:db8::5'),
      );
      expect(ipProblems('001.json', clean), isEmpty);
    });
  });
}
