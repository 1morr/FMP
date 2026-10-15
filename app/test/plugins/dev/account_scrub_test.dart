import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/network/fixture/fixture.dart';
import 'package:fmp/data/repositories/account_repository.dart';
import 'package:fmp/domain/account.dart';
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

  // 非 login 的 requiresLogin 案例以 accounts 列換值（M4 PR 12）。
  group('loginAccountOf', () {
    Account row(String? avatarJson) => Account(
      pluginId: 'p',
      userId: '12345678',
      displayName: 'FAKE_Tester',
      avatarJson: avatarJson,
      status: AccountStatus.active,
      loggedInAt: DateTime.utc(2026),
    );

    test('reads the avatar AccountService writes', () {
      // 格式同 account_service.dart 的 `avatarJson`：`[{url, width?}]`。
      final account = loginAccountOf(
        row(
          '[{"url": "https://img.example.test/face/tester.jpg", "width": 96}, '
          '{"url": "https://img.example.test/face/tester_s.jpg"}]',
        ),
      )!;

      expect(account.userId, '12345678');
      expect(account.displayName, 'FAKE_Tester');
      expect(
        [for (final image in account.avatar) image.url.path],
        ['/face/tester.jpg', '/face/tester_s.jpg'],
      );
      expect(account.avatar.first.width, 96);
      // 讀到的頭像就是換值認得的頭像。
      expect(
        accountLeaks([
          _fixture(
            jsonBody: {'face': 'https://img.example.test/face/tester.jpg'},
          ),
        ], account),
        ['avatar'],
      );
      expect(loginAccountOf(row(null))!.avatar, isEmpty);
    });

    // 讀不懂的頭像不能當成沒有頭像：那樣換值認不得它，錄到的頭像會原樣寫進 fixture。
    for (final (name, json) in [
      ('not JSON', '{'),
      ('not a list', '{"url": "https://img.example.test/a.jpg"}'),
      ('an item without a url', '[{"width": 96}]'),
      ('an item that is not an object', '["https://img.example.test/a.jpg"]'),
      (
        'a width that is not an integer',
        '[{"url": "https://a.test/b.jpg", "width": "96"}]',
      ),
    ]) {
      test('is null when the avatar is $name', () {
        expect(loginAccountOf(row(json)), isNull);
      });
    }
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
