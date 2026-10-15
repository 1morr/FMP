import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/network/fixture/fixture.dart';
import 'package:fmp/plugins/dev/account_scrub.dart';
import 'package:fmp/plugins/source_dto.dart';

// 帳號值都是明顯的假值。

HttpFixture _fixture({
  String url = 'https://api.example.test/nav',
  Object? jsonBody,
  String? body,
}) => HttpFixture(
  request: FixtureRequest(method: 'GET', url: url),
  response: FixtureResponse(
    status: 200,
    body: body,
    jsonBody: jsonBody,
    headers: const {
      'content-type': ['application/json'],
    },
  ),
);

LoginAccount _account({
  String userId = '12345678',
  String displayName = 'FAKE_Tester',
  List<String> avatar = const ['https://img.example.test/face/tester.jpg'],
}) => LoginAccount(
  userId: userId,
  displayName: displayName,
  avatar: [for (final url in avatar) Artwork(url: Uri.parse(url))],
);

Object? _jsonBody(List<HttpFixture> fixtures) =>
    fixtures.single.response.jsonBody;

void main() {
  group('scrubAccount', () {
    test('replaces the id, the name and the avatar wherever they appear', () {
      final scrubbed = scrubAccount([
        _fixture(
          url: 'https://api.example.test/space/12345678/info?mid=12345678',
          jsonBody: {
            'data': {
              'mid': 12345678,
              'uname': 'FAKE_Tester',
              'face': 'http://img.example.test/face/tester.jpg?w=1',
              'greeting': 'hi FAKE_Tester!',
            },
          },
        ),
      ], _account());

      expect(
        scrubbed.single.request.url,
        'https://api.example.test/space/***/info?mid=***',
      );
      expect(_jsonBody(scrubbed), {
        'data': {
          'mid': '***',
          'uname': '***',
          // 不看 scheme 與 query；留下主機，插件重播時仍認得。
          'face': 'http://img.example.test/***',
          'greeting': 'hi ***!',
        },
      });
      expect(accountLeaks(scrubbed, _account()), isEmpty);
    });

    test('keeps other people: another avatar, another id, longer numbers', () {
      final json = {
        'owner': {
          'mid': 99999999,
          'face': 'https://img.example.test/face/someone-else.jpg',
        },
        'aid': 9123456780,
        'cid': '9123456780',
      };

      final scrubbed = scrubAccount([_fixture(jsonBody: json)], _account());

      expect(_jsonBody(scrubbed), json);
    });

    test('a short value only matches the whole value', () {
      final account = _account(userId: '42', displayName: 'ab');
      final json = {
        'mid': 42,
        'name': 'ab',
        'other': 'about 42 abc',
        'status': 42,
      };

      final scrubbed = scrubAccount([
        HttpFixture(
          request: const FixtureRequest(method: 'GET', url: 'https://a.test/'),
          response: FixtureResponse(status: 200, jsonBody: json),
        ),
      ], account);

      expect(_jsonBody(scrubbed), {
        'mid': '***',
        'name': '***',
        'other': 'about 42 abc',
        'status': '***',
      });
      expect(scrubbed.single.response.status, 200);
    });

    test('scrubs text bodies and header values', () {
      final scrubbed = scrubAccount([
        HttpFixture(
          request: const FixtureRequest(
            method: 'POST',
            url: 'https://a.test/x',
            body: 'uid=12345678&n=FAKE_Tester',
          ),
          response: const FixtureResponse(
            status: 200,
            body: 'FAKE_Tester https://img.example.test/face/tester.jpg',
            headers: {
              'x-user': ['12345678'],
            },
          ),
        ),
      ], _account());

      expect(scrubbed.single.request.body, 'uid=***&n=***');
      expect(scrubbed.single.response.body, '*** https://img.example.test/***');
      expect(scrubbed.single.response.headers['x-user'], ['***']);
    });
  });

  group('accountLeaks', () {
    test('finds an avatar written with another scheme and a query', () {
      // 網易雲：回應是 http://…jpg，插件回傳 https://…jpg?param=…
      final leaks = accountLeaks(
        [
          _fixture(
            jsonBody: {'face': 'http://img.example.test/face/tester.jpg'},
          ),
        ],
        _account(
          avatar: ['https://img.example.test/face/tester.jpg?param=1y1'],
        ),
      );

      expect(leaks, ['avatar']);
    });

    test('reports each field that is still visible', () {
      final leaks = accountLeaks([
        _fixture(jsonBody: {'mid': 12345678, 'note': 'FAKE_Tester was here'}),
      ], _account());

      expect(leaks, ['userId', 'displayName']);
    });

    test('does not report other people or numbers that contain the id', () {
      final leaks = accountLeaks([
        _fixture(
          jsonBody: {
            'owner': {
              'mid': 99999999,
              'face': 'https://img.example.test/face/someone-else.jpg',
            },
            'aid': 9123456780,
          },
        ),
      ], _account());

      expect(leaks, isEmpty);
    });
  });
}
