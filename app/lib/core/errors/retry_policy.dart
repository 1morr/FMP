import 'dart:io' show HttpDate;
import 'dart:math' as math;

import 'package:fmp/core/errors/app_error.dart';

/// 音源宣告的重試策略（ADR 0013 §決定 4）。預設值就是 ADR 的預設。
///
/// 重試只有網路層這一層：Riverpod 的自動重試全域關閉（`app_scope.dart`）。
/// 憑證刷新後重送（ADR 0012）另計，不佔這裡的次數。
final class RetryPolicy {
  const RetryPolicy({
    this.maxRetries = 2,
    this.baseDelay = const Duration(milliseconds: 500),
    this.maxDelay = const Duration(seconds: 8),
    this.maxRetryAfter = const Duration(seconds: 60),
  });

  /// 原本那次以外最多再送幾次。
  final int maxRetries;

  /// 指數退避的底數：第 `attempt` 次重試的上限是 `baseDelay × 2^attempt`。
  final Duration baseDelay;

  /// 指數退避的上限（AWS 文中的 `cap`）。
  final Duration maxDelay;

  /// 願意照 `Retry-After` 等多久；伺服器要求更久就不重試，把錯誤交出去。
  final Duration maxRetryAfter;
}

/// 音源宣告的限流策略：事先避開限流（ADR 0013 §決定 4）。網路層的排程在
/// PR 8 依它限制請求；這裡只定欄位。
final class RateLimitPolicy {
  const RateLimitPolicy({
    required this.maxConcurrentRequests,
    required this.minRequestInterval,
  });

  /// 同一個音源同時進行中的請求上限。
  final int maxConcurrentRequests;

  /// 同一個音源兩次請求開始之間的最短間隔。
  final Duration minRequestInterval;
}

/// RFC 9110 §9.2.2 定義的冪等方法：PUT、DELETE 與安全方法（§9.2.1 的 GET、
/// HEAD、OPTIONS、TRACE）。
const _idempotentMethods = {'GET', 'HEAD', 'OPTIONS', 'TRACE', 'PUT', 'DELETE'};

/// [method] 是不是冪等方法（RFC 9110 §9.2.2）；POST、PATCH 與不認得的方法都
/// 不是。
///
/// 方法名稱分大小寫（RFC 9110 §9.1），`get` 不等於 `GET`；比對不上時往「不
/// 重試」的方向錯。
bool isIdempotent(String method) => _idempotentMethods.contains(method);

/// 網路層要不要重試這次失敗。
///
/// [attempt] 是已經重試過的次數（原本那次失敗後為 0）。四個條件都成立才重試：
/// - 請求冪等（[isIdempotent]；RFC 9110 §9.2.2：非冪等請求不該自動重試）；
/// - [AppError.retryable] 為真；
/// - [attempt] 還沒到 [RetryPolicy.maxRetries]；
/// - 沒有 `Retry-After`，或它沒超過 [RetryPolicy.maxRetryAfter]。
bool shouldRetry(
  AppError error, {
  required int attempt,
  required String method,
  required RetryPolicy policy,
}) {
  RangeError.checkNotNegative(attempt, 'attempt');
  return isIdempotent(method) &&
      error.retryable &&
      attempt < policy.maxRetries &&
      _withinRetryAfterLimit(error, policy);
}

/// 第 [attempt] 次重試前要等多久（[attempt] 的意思同 [shouldRetry]）。
///
/// - 有 `Retry-After`（[AppError.retryAfter]）就照它等；超過
///   [RetryPolicy.maxRetryAfter] 回 `null`，表示不重試。
/// - 沒有就用指數退避加全抖動，也就是 AWS〈Exponential Backoff And Jitter〉
///   （Marc Brooker，2015）的 Full Jitter：
///   `random_between(0, min(cap, base * 2 ** attempt))`。[random] 由呼叫端
///   傳入，測試固定種子。
Duration? delayFor(
  AppError error, {
  required int attempt,
  required RetryPolicy policy,
  required math.Random random,
}) {
  RangeError.checkNotNegative(attempt, 'attempt');
  if (error.retryAfter case final retryAfter?) {
    return _withinRetryAfterLimit(error, policy) ? retryAfter : null;
  }
  final ceiling = math.min(
    policy.maxDelay.inMicroseconds.toDouble(),
    policy.baseDelay.inMicroseconds * math.pow(2, attempt),
  );
  return Duration(microseconds: (random.nextDouble() * ceiling).floor());
}

bool _withinRetryAfterLimit(AppError error, RetryPolicy policy) =>
    switch (error.retryAfter) {
      null => true,
      final retryAfter => retryAfter <= policy.maxRetryAfter,
    };

/// `Retry-After` 的值再大也不超過這個；任何重試上限都遠小於它。
const _longestRetryAfter = Duration(days: 36500);

/// `delay-seconds = 1*DIGIT`（RFC 9110 §10.2.3）。
final _delaySeconds = RegExp(r'^[0-9]+$');

/// RFC 9110 §5.6.7 的三種 HTTP-date，照 ABNF 逐字比對（分大小寫）。
///
/// [HttpDate.parse] 比 ABNF 寬鬆，而且截斷的 asctime 會拋 [RangeError] 而不是
/// `HttpException`，所以先以這些樣式擋掉，通過的才交給它。
///
/// IMF-fixdate：Sun, 06 Nov 1994 08:49:37 GMT
final _imfFixdate = RegExp(
  '^$_dayName, [0-9]{2} $_month [0-9]{4} $_time GMT\$',
);

/// rfc850-date：Sunday, 06-Nov-94 08:49:37 GMT。只有它是兩位數年份。
final _rfc850Date = RegExp(
  '^(Monday|Tuesday|Wednesday|Thursday|Friday|Saturday|Sunday), '
  '[0-9]{2}-$_month-[0-9]{2} $_time GMT\$',
);

/// asctime-date：Sun Nov  6 08:49:37 1994
final _asctimeDate = RegExp(
  '^$_dayName $_month ([0-9]{2}| [0-9]) $_time [0-9]{4}\$',
);
const _dayName = '(Mon|Tue|Wed|Thu|Fri|Sat|Sun)';
const _month = '(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)';
const _time = '[0-9]{2}:[0-9]{2}:[0-9]{2}';

/// 解析 `Retry-After` 標頭（RFC 9110 §10.2.3）：`delay-seconds`（非負整數秒）
/// 或 HTTP-date。無效值回 `null`。
///
/// HTTP-date 接受 §5.6.7 要求收方都接受的三種格式（IMF-fixdate、RFC 850、
/// asctime）；RFC 850 的兩位數年份照 §5.6.7 解讀：看起來超過 50 年後的，算成
/// 過去最近的同尾數年份。四位數年份照字面，`0094` 就是西元 94 年。日期已過回
/// [Duration.zero]。[now] 由呼叫端傳入（收到回應的時間）。
Duration? parseRetryAfter(String value, {required DateTime now}) {
  final text = value.trim();
  if (_delaySeconds.hasMatch(text)) {
    // 位數多到 int 放不下仍是合法值，只是遠超任何上限。
    final seconds = int.tryParse(text);
    return seconds == null || seconds > _longestRetryAfter.inSeconds
        ? _longestRetryAfter
        : Duration(seconds: seconds);
  }
  final DateTime date;
  if (_rfc850Date.hasMatch(text)) {
    date = _withFullYear(HttpDate.parse(text), now);
  } else if (_imfFixdate.hasMatch(text) || _asctimeDate.hasMatch(text)) {
    date = HttpDate.parse(text);
  } else {
    return null;
  }
  final delay = date.difference(now);
  return delay.isNegative ? Duration.zero : delay;
}

/// RFC 9110 §5.6.7：兩位數年份先放進現在這個世紀；那個時間點超過現在 50 年
/// 後，就算成上一個世紀。比的是時間點，不只是年份。
DateTime _withFullYear(DateTime twoDigitYear, DateTime now) {
  final utcNow = now.toUtc();
  DateTime inYear(int year) => DateTime.utc(
    year,
    twoDigitYear.month,
    twoDigitYear.day,
    twoDigitYear.hour,
    twoDigitYear.minute,
    twoDigitYear.second,
  );
  final candidate = inYear(utcNow.year - utcNow.year % 100 + twoDigitYear.year);
  final fiftyYearsAhead = DateTime.utc(
    utcNow.year + 50,
    utcNow.month,
    utcNow.day,
    utcNow.hour,
    utcNow.minute,
    utcNow.second,
  );
  return candidate.isAfter(fiftyYearsAhead)
      ? inYear(candidate.year - 100)
      : candidate;
}
