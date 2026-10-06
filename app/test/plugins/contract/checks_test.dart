import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/domain/stream_preferences.dart';
import 'package:fmp/plugins/source_dto.dart';

import 'checks.dart';

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
