import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/domain/stream_preferences.dart';
import 'package:fmp/plugins/accounts/login_credentials.dart';
import 'package:fmp/plugins/manifest/plugin_manifest.dart';
import 'package:fmp/plugins/source_dto.dart';

import 'package:fmp/plugins/health/checks.dart';

String _check(String capability, String input, String expect) =>
    '{"$capability": {"input": $input, "expect": $expect}}';

const _search = '{"keyword": "k", "page": 1}';
const _stream =
    '{"sourceId": "a", "purpose": "playback", '
    '"formats": [{"container": "mp4", "codec": "aac"}]}';

/// resolveStream 的案例，成功的期望加上 [pattern]（JSON 字串的內容）。
String _withPattern(String pattern, {String expect = '{"minItems": 1}'}) =>
    '{"resolveStream": {"input": $_stream, "expect": $expect, '
    '"expiresAtPattern": "$pattern"}}';

void main() {
  test('the item fields cover the DTO shapes', () {
    // nonEmpty 以 d.ts 的欄位名稱檢查：DTO 多了欄位，這兩張表也要多。
    expect(
      trackFields(
        const TrackSummary(sourceTypeId: 'p', sourceId: 's', title: 't'),
      ).keys.toSet(),
      sourceDtoShapes['TrackSummary']!.keys.toSet(),
    );
    expect(
      candidateFields(StreamCandidate(url: Uri.parse('https://a.test/'))).keys
          .toSet(),
      sourceDtoShapes['StreamCandidate']!.keys.toSet(),
    );
    expect(
      accountFields(const LoginAccount(userId: 'u', displayName: 'd')).keys
          .toSet(),
      sourceDtoShapes['LoginAccount']!.keys.toSet(),
    );
    expect(
      liveRoomFields(
        const LiveRoom(roomId: 'r', title: 't', status: LiveRoomStatus.live),
      ).keys.toSet(),
      sourceDtoShapes['LiveRoom']!.keys.toSet(),
    );
  });

  group('the live check', () {
    const input = '{"roomId": "r1"}';

    test('runs liveStatus on the room and reads the LiveRoom fields', () {
      final check = parseChecks(
        _check(
          'live',
          input,
          '{"minItems": 1, "nonEmpty": ["roomId", "online"]}',
        ),
      ).single;

      expect(check.capability, PluginCapability.live);
      expect(check.input, isA<LiveRoomQuery>());
      expect((check.input as LiveRoomQuery).roomId, 'r1');
      expect(check.requiresLogin, isFalse);
      expect(
        check.expectation.evaluate(
          result: const LiveRoom(
            roomId: 'r1',
            title: 't',
            status: LiveRoomStatus.live,
          ),
          describe: (_) => '',
        ),
        ['item 0: "online" is empty'],
      );
    });

    test('is read in the order search, resolveStream, live', () {
      final checks = parseChecks(
        '{"live": {"input": $input, "expect": {}}, '
        '"search": {"input": $_search, "expect": {}}}',
      );

      expect(checks.map((check) => check.capability.wireName), [
        'search',
        'live',
      ]);
    });

    for (final (name, text, message) in [
      (
        'an empty room id',
        _check('live', '{"roomId": " "}', '{}'),
        'checks.live.input: must not be empty',
      ),
      (
        'an input with a keyword',
        _check('live', '{"roomId": "r1", "keyword": "k"}', '{}'),
        'unknown field "keyword"',
      ),
      (
        'a field LiveRoom does not have',
        _check('live', input, '{"nonEmpty": ["viewers"]}'),
        'LiveRoom has no field "viewers"',
      ),
    ]) {
      test('rejects $name', () {
        expect(
          () => parseChecks(text),
          throwsA(
            isA<FormatException>().having(
              (e) => e.message,
              'message',
              contains(message),
            ),
          ),
        );
      });
    }
  });

  group('the mix check', () {
    const input = '{"seed": {"sourceId": "a", "cid": 2}}';

    test('starts a mix by seed and reads the tracks of the batch', () {
      final check = parseChecks(
        _check(
          'mix',
          input,
          '{"minItems": 2, "nonEmpty": ["sourceId", "uploader"]}',
        ),
      ).single;

      expect(check.capability, PluginCapability.mix);
      expect(check.input, isA<MixSeedQuery>());
      expect((check.input as MixSeedQuery).sourceId, 'a');
      expect((check.input as MixSeedQuery).cid, 2);
      expect(check.requiresLogin, isFalse);
      final batch = MixBatch(
        mixId: 'm',
        title: 'Mix',
        tracks: const [
          TrackSummary(sourceTypeId: 'p', sourceId: 'a', title: 't'),
        ],
      );
      expect(check.expectation.evaluate(result: batch, describe: (_) => ''), [
        'expected at least 2 items, got 1',
        'item 0: "uploader" is empty',
      ]);
    });

    test('is read in the order search, resolveStream, live, mix', () {
      final checks = parseChecks(
        '{"mix": {"input": $input, "expect": {}}, '
        '"live": {"input": {"roomId": "r"}, "expect": {}}, '
        '"search": {"input": $_search, "expect": {}}}',
      );

      expect(checks.map((check) => check.capability.wireName), [
        'search',
        'live',
        'mix',
      ]);
    });

    for (final (name, text, message) in [
      (
        'an empty source id',
        _check('mix', '{"seed": {"sourceId": " "}}', '{}'),
        'checks.mix.input: must not be empty',
      ),
      (
        'a continuation instead of a seed',
        _check('mix', '{"mixId": "m", "cursor": "c"}', '{}'),
        'unknown field "mixId"',
      ),
      (
        'a seed without a source id',
        _check('mix', '{"seed": {"cid": 1}}', '{}'),
        'missing required field "sourceId"',
      ),
      (
        'a field TrackSummary does not have',
        _check('mix', input, '{"nonEmpty": ["mixId"]}'),
        'TrackSummary has no field "mixId"',
      ),
    ]) {
      test('rejects $name', () {
        expect(
          () => parseChecks(text),
          throwsA(
            isA<FormatException>().having(
              (e) => e.message,
              'message',
              contains(message),
            ),
          ),
        );
      });
    }
  });

  group('the login check', () {
    const credentials = '{"cookies": {"SESSDATA": "***"}}';

    test('runs loginVerify with the credentials and requires a login', () {
      final check = parseChecks(
        '{"login": {"input": $credentials, "expect": {"minItems": 1, '
        '"nonEmpty": ["userId", "displayName"]}, "requiresLogin": true}}',
      ).single;

      expect(check.capability, PluginCapability.login);
      expect(check.input, const LoginCredentials(cookies: {'SESSDATA': '***'}));
      expect(check.requiresLogin, isTrue);
      expect(
        check.expectation.evaluate(
          result: const LoginAccount(userId: 'u', displayName: ''),
          describe: (_) => '',
        ),
        ['item 0: "displayName" is empty'],
      );
    });

    test('the other cases do not require a login', () {
      expect(
        parseChecks('{"search": {"input": $_search, "expect": {}}}')
            .single
            .requiresLogin,
        isFalse,
      );
    });

    for (final (name, text, message) in [
      (
        'requiresLogin is missing',
        '{"login": {"input": $credentials, "expect": {}}}',
        'missing required field "requiresLogin"',
      ),
      (
        'requiresLogin is false',
        '{"login": {"input": $credentials, "expect": {}, '
            '"requiresLogin": false}}',
        'checks.login.requiresLogin: must be true',
      ),
      (
        'the input is not credentials',
        '{"login": {"input": {"SESSDATA": "***"}, "expect": {}, '
            '"requiresLogin": true}}',
        'checks.login.input',
      ),
      (
        'a field LoginAccount does not have',
        '{"login": {"input": $credentials, "expect": {"nonEmpty": '
            '["vip"]}, "requiresLogin": true}}',
        'LoginAccount has no field "vip"',
      ),
    ]) {
      test('rejects when $name', () {
        expect(
          () => parseChecks(text),
          throwsA(
            isA<FormatException>().having(
              (e) => e.message,
              'message',
              contains(message),
            ),
          ),
        );
      });
    }
  });

  group('parseChecks', () {
    test('reads both kinds of expectation', () {
      final checks = parseChecks(
        '{"search": {"input": $_search, "expect": {"minItems": 1}}, '
        '"resolveStream": {"input": {"sourceId": "a", "purpose": "playback", '
        '"formats": [{"container": "mp4", "codec": "aac"}]}, '
        '"expect": {"error": "Unavailable", "reason": "region"}}}',
      );

      expect(checks.map((check) => check.capability.wireName), [
        'search',
        'resolveStream',
      ]);
      expect(checks.first.input, isA<SearchQuery>());
      expect(
        checks.last.expectation,
        isA<ExpectError>()
            .having((e) => e.error, 'error', 'Unavailable')
            .having((e) => e.reason, 'reason', UnavailableReason.region),
      );
    });

    test('reads the quality and the expiresAtPattern', () {
      final check = parseChecks(
        '{"resolveStream": {"input": {"sourceId": "a", "purpose": '
        '"playback", "formats": [{"container": "mp4", "codec": "aac"}], '
        '"quality": "low"}, "expect": {"minItems": 1}, '
        r'"expiresAtPattern": "[?&]deadline=(\\d+)"}}',
      ).single;

      expect((check.input as StreamRequest).quality, AudioQuality.low);
      expect(check.expiresAtPattern?.pattern, r'[?&]deadline=(\d+)');
    });

    test('the quality and the expiresAtPattern are optional', () {
      final check = parseChecks(
        '{"resolveStream": {"input": $_stream, "expect": {}}}',
      ).single;

      expect((check.input as StreamRequest).quality, isNull);
      expect(check.expiresAtPattern, isNull);
    });

    for (final (name, text, message) in [
      (
        'an unknown quality',
        '{"resolveStream": {"input": {"sourceId": "a", "purpose": '
            '"playback", "formats": [{"container": "mp4", "codec": "aac"}], '
            '"quality": "lossless"}, "expect": {}}}',
        'checks.resolveStream.input.quality: unknown "lossless"',
      ),
      (
        'an expiresAtPattern that is not a regular expression',
        _withPattern('(unclosed'),
        'checks.resolveStream.expiresAtPattern: not a regular expression',
      ),
      (
        'an expiresAtPattern without a capture group',
        _withPattern(r'deadline=\\d+'),
        'needs exactly one capture group, has 0',
      ),
      (
        'an expiresAtPattern with two capture groups',
        _withPattern(r'(deadline)=(\\d+)'),
        'needs exactly one capture group, has 2',
      ),
      (
        'an expiresAtPattern with an error expect',
        _withPattern(r'deadline=(\\d+)', expect: '{"error": "NotFound"}'),
        'only a successful expect has candidates',
      ),
      (
        'an expiresAtPattern on search',
        '{"search": {"input": $_search, "expect": {}, '
            r'"expiresAtPattern": "deadline=(\\d+)"}}',
        'unknown field "expiresAtPattern"',
      ),
      (
        'a capability the host cannot call yet',
        _check('charts', '{}', '{}'),
        'unknown field "charts"',
      ),
      (
        'an unknown error name',
        _check('search', _search, '{"error": "Timeout"}'),
        'unknown error "Timeout"',
      ),
      (
        'a reason on another error',
        _check('search', _search, '{"error": "NotFound", "reason": "age"}'),
        'only Unavailable has a reason',
      ),
      (
        'a nonEmpty field the item does not have',
        _check('search', _search, '{"nonEmpty": ["name"]}'),
        'TrackSummary has no field "name"',
      ),
      (
        'an input the DTO rejects',
        _check('search', '{"keyword": " ", "page": 1}', '{}'),
        'checks.search.input: must not be empty',
      ),
    ]) {
      test('rejects $name', () {
        expect(
          () => parseChecks(text),
          throwsA(
            isA<FormatException>().having(
              (e) => e.message,
              'message',
              contains(message),
            ),
          ),
        );
      });
    }
  });
}
