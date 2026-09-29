import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/core/errors/retry_policy.dart';

const _policy = RetryPolicy();

void main() {
  test('the defaults are the ones in ADR 0013', () {
    expect(_policy.maxRetries, 2);
    expect(_policy.baseDelay, const Duration(milliseconds: 500));
    expect(_policy.maxDelay, const Duration(seconds: 8));
    expect(_policy.maxRetryAfter, const Duration(seconds: 60));
  });

  test('idempotent methods follow RFC 9110 §9.2.2', () {
    const table = {
      'GET': true,
      'HEAD': true,
      'OPTIONS': true,
      'TRACE': true,
      'PUT': true,
      'DELETE': true,
      'POST': false,
      'PATCH': false,
      'CONNECT': false,
      // 方法名稱分大小寫（RFC 9110 §9.1）。
      'get': false,
      '': false,
    };
    for (final MapEntry(key: method, value: idempotent) in table.entries) {
      expect(isIdempotent(method), idempotent, reason: method);
    }
  });

  group('shouldRetry', () {
    bool retry(
      AppError error, {
      int attempt = 0,
      String method = 'GET',
      RetryPolicy policy = _policy,
    }) => shouldRetry(error, attempt: attempt, method: method, policy: policy);

    test('retries a retryable error of an idempotent request', () {
      expect(retry(NetworkError()), isTrue);
      expect(retry(RateLimited(), method: 'DELETE'), isTrue);
    });

    test('never retries a non-idempotent request', () {
      expect(retry(NetworkError(), method: 'POST'), isFalse);
      expect(retry(RateLimited(), method: 'PATCH'), isFalse);
    });

    test('follows retryable, including a source override', () {
      expect(retry(NotFound()), isFalse);
      expect(retry(ParseError()), isFalse);
      expect(retry(NotFound(retryable: true)), isTrue);
      expect(retry(NetworkError(retryable: false)), isFalse);
    });

    test('stops at the retry limit', () {
      expect(retry(NetworkError(), attempt: 1), isTrue);
      expect(retry(NetworkError(), attempt: 2), isFalse);
      expect(
        retry(
          NetworkError(),
          attempt: 2,
          policy: const RetryPolicy(maxRetries: 3),
        ),
        isTrue,
      );
      expect(
        retry(NetworkError(), policy: const RetryPolicy(maxRetries: 0)),
        isFalse,
      );
    });

    test('gives up when Retry-After is beyond the limit', () {
      expect(
        retry(RateLimited(retryAfter: const Duration(seconds: 60))),
        isTrue,
      );
      expect(
        retry(RateLimited(retryAfter: const Duration(seconds: 61))),
        isFalse,
      );
    });

    test('rejects a negative attempt', () {
      expect(() => retry(NetworkError(), attempt: -1), throwsRangeError);
    });
  });

  group('delayFor', () {
    Duration? delay(AppError error, int attempt, Random random) =>
        delayFor(error, attempt: attempt, policy: _policy, random: random);

    test('full jitter: random(0, min(cap, base * 2^attempt))', () {
      // 抖動取區間中點時，延遲正好是上限的一半。
      final half = _FixedRandom(0.5);
      expect(delay(NetworkError(), 0, half), const Duration(milliseconds: 250));
      expect(delay(NetworkError(), 1, half), const Duration(milliseconds: 500));
      expect(delay(NetworkError(), 3, half), const Duration(seconds: 2));
      // 500ms × 2^4 = 8s 到頂；再大也是 8s。
      expect(delay(NetworkError(), 4, half), const Duration(seconds: 4));
      expect(delay(NetworkError(), 40, half), const Duration(seconds: 4));
      expect(delay(NetworkError(), 0, _FixedRandom(0)), Duration.zero);
    });

    test('stays within the bounds for a seeded random', () {
      final random = Random(20260929);
      for (var attempt = 0; attempt <= 6; attempt++) {
        final ceiling = Duration(
          milliseconds: min(8000, 500 * pow(2, attempt).toInt()),
        );
        final samples = [
          for (var i = 0; i < 500; i++) delay(NetworkError(), attempt, random)!,
        ];
        expect(samples.every((d) => d >= Duration.zero && d < ceiling), isTrue);
        // 真的用了整個區間，不是只在底部。
        expect(samples.any((d) => d > ceiling * 0.9), isTrue);
        expect(samples.any((d) => d < ceiling * 0.1), isTrue);
      }
    });

    test('uses Retry-After when present, without jitter', () {
      final error = RateLimited(retryAfter: const Duration(seconds: 42));

      expect(delay(error, 0, Random(1)), const Duration(seconds: 42));
      expect(delay(error, 1, Random(2)), const Duration(seconds: 42));
    });

    test('returns null when Retry-After is beyond the limit', () {
      final error = RateLimited(retryAfter: const Duration(minutes: 5));

      expect(delay(error, 0, Random(1)), isNull);
      expect(
        delayFor(
          error,
          attempt: 0,
          policy: const RetryPolicy(maxRetryAfter: Duration(minutes: 5)),
          random: Random(1),
        ),
        const Duration(minutes: 5),
      );
    });
  });

  group('parseRetryAfter (RFC 9110 §10.2.3)', () {
    final now = DateTime.utc(2026, 9, 29, 12);
    Duration? parse(String value) => parseRetryAfter(value, now: now);

    test('delay-seconds', () {
      expect(parse('120'), const Duration(minutes: 2));
      expect(parse('0'), Duration.zero);
      expect(parse(' 5 '), const Duration(seconds: 5));
    });

    test('a huge delay-seconds is valid and beyond every limit', () {
      final delay = parse('99999999999999999999999');

      expect(delay, isNotNull);
      expect(delay! > const Duration(days: 365 * 50), isTrue);
    });

    test('all three HTTP-date formats (§5.6.7)', () {
      const later = Duration(minutes: 1, seconds: 30);
      expect(parse('Tue, 29 Sep 2026 12:01:30 GMT'), later);
      expect(parse('Tuesday, 29-Sep-26 12:01:30 GMT'), later);
      expect(parse('Tue Sep 29 12:01:30 2026'), later);
      expect(
        parse('Thu Oct  1 12:00:00 2026'),
        const Duration(days: 2),
        reason: 'asctime pads a one-digit day with a space',
      );
    });

    test('a two-digit year more than 50 years ahead is in the past', () {
      // 2094 超過 2026 + 50，算成 1994；已過的日期不用等。
      expect(parse('Sunday, 06-Nov-94 08:49:37 GMT'), Duration.zero);
      final nearFuture = parseRetryAfter(
        'Monday, 01-Jan-76 00:00:00 GMT',
        now: DateTime.utc(2026),
      );
      expect(nearFuture! > const Duration(days: 365 * 49), isTrue);
    });

    test('the 50-year rule compares the timestamp, not only the year', () {
      // now 是 2026-09-29：2076-01-01 在 50 年內，2076-12-01 超過。
      expect(parse('Wednesday, 01-Jan-76 00:00:00 GMT'), isNot(Duration.zero));
      expect(parse('Tuesday, 01-Dec-76 00:00:00 GMT'), Duration.zero);
    });

    test('a four-digit year is taken as written', () {
      // 只有 rfc850-date 是兩位數年份；IMF-fixdate 與 asctime 的 0030 是西元 30
      // 年，不補成 2030。
      expect(parse('Sun, 06 Nov 0030 08:49:37 GMT'), Duration.zero);
      expect(parse('Sun Nov  6 08:49:37 0030'), Duration.zero);
    });

    test('a date in the past means no wait', () {
      expect(parse('Fri, 31 Dec 1999 23:59:59 GMT'), Duration.zero);
    });

    test('invalid values are null', () {
      for (final value in [
        '',
        '-1',
        '1.5',
        '+5',
        '5s',
        'soon',
        'tue, 29 Sep 2026 12:01:30 GMT',
        'Tue, 29 Sep 2026 12:01:30 UTC',
        'Tue, 29 Sep 2026 12:01:30',
        'Tue, 29 Sep 2026 12:01:30 GMT extra',
        'Tue Sep ',
        'Tue Sep  ',
        '2026-09-29T12:01:30Z',
      ]) {
        expect(parse(value), isNull, reason: value);
      }
    });
  });
}

/// `nextDouble` 固定回傳同一個值的 [Random]。
final class _FixedRandom implements Random {
  _FixedRandom(this.value);

  final double value;

  @override
  double nextDouble() => value;

  @override
  bool nextBool() => throw UnimplementedError();

  @override
  int nextInt(int max) => throw UnimplementedError();
}
