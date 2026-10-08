import 'dart:io';

import 'package:dio/dio.dart';

import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/core/errors/retry_policy.dart';
import 'package:fmp/core/network/allowed_hosts.dart';

// 兩種 client（`SourceHttpClient`、`MediaHttpClient`）共用的規則：網域、轉址、
// HTTP 通用的限流語意、傳輸錯誤的對應（ADR 0012 §決定 1、ADR 0013 §決定 2）。
// 規則只寫在這裡，兩種 client 不各寫一份。

/// 一次最多跟隨幾次轉址（ADR 0012 §決定 1；dio 的 `maxRedirects` 預設也是 5）。
const maxRedirects = 5;

/// 會轉址的狀態碼（RFC 9110 §15.4）。300 與 304 不自動跟隨。
const _redirectStatuses = {301, 302, 303, 307, 308};

/// [url] 不在 [allowedHosts] 或不是 `https`：丟 [Unsupported]，請求不發出。
void requireAllowedHost(
  AllowedHosts allowedHosts,
  Uri url, {
  required String? pluginId,
}) {
  if (allowedHosts.allows(url)) return;
  throw Unsupported(
    pluginId: pluginId,
    cause: StateError('Host not allowed: ${url.host}'),
    stackTrace: StackTrace.current,
  );
}

/// 回應要跟隨的 `Location`；不是轉址，或轉址卻沒有 `Location`，回 `null`
/// （回應原樣交出）。[headers] 的名稱小寫。
String? redirectLocation(int statusCode, Map<String, List<String>> headers) {
  if (!_redirectStatuses.contains(statusCode)) return null;
  final location = headers[HttpHeaders.locationHeader]?.first;
  return location == null || location.isEmpty ? null : location;
}

/// 從 [from] 轉到 [location] 的下一跳。[redirects] 是之前已經跟了幾次。
///
/// 已經跟了 [maxRedirects] 次、[location] 解析不了、下一跳不在
/// [allowedHosts] 或不是 `https`：丟 [Unsupported]，帶回了這個轉址的那筆
/// 網路紀錄 [networkRecordId]；下一跳不發出。
Uri redirectTarget({
  required Uri from,
  required String location,
  required int redirects,
  required AllowedHosts allowedHosts,
  required String? pluginId,
  required int networkRecordId,
}) {
  if (redirects >= maxRedirects) {
    throw Unsupported(
      pluginId: pluginId,
      networkRecordId: networkRecordId,
      cause: StateError('More than $maxRedirects redirects'),
      stackTrace: StackTrace.current,
    );
  }
  final Uri next;
  try {
    next = from.resolve(location);
  } on FormatException catch (error, stackTrace) {
    // 伺服器給的 `Location` 解析不了：跟不下去，同出網域一樣失敗。
    throw Unsupported(
      pluginId: pluginId,
      networkRecordId: networkRecordId,
      cause: error,
      stackTrace: stackTrace,
    );
  }
  if (!allowedHosts.allows(next)) {
    throw Unsupported(
      pluginId: pluginId,
      networkRecordId: networkRecordId,
      cause: StateError('Redirect to a host not allowed: ${next.host}'),
      stackTrace: StackTrace.current,
    );
  }
  return next;
}

/// HTTP 通用的限流語意；不是就回 `null`。
///
/// RFC 6585 §4：429 Too Many Requests，可以帶 `Retry-After`。
/// RFC 9110 §15.6.4：503 Service Unavailable 帶 `Retry-After` 表示暫時超載、
/// 多久後再試；沒帶的 503 不一定是限流。
RateLimited? rateLimitedResponse(
  int statusCode,
  Map<String, List<String>> headers, {
  required DateTime now,
  required String? pluginId,
  required int networkRecordId,
}) {
  if (statusCode != 429 && statusCode != 503) return null;
  final header = headers[HttpHeaders.retryAfterHeader]?.first;
  final retryAfter = header == null ? null : parseRetryAfter(header, now: now);
  if (statusCode == 503 && retryAfter == null) return null;
  return RateLimited(
    pluginId: pluginId,
    retryAfter: retryAfter,
    networkRecordId: networkRecordId,
    cause: 'HTTP $statusCode',
  );
}

/// dio 的傳輸錯誤轉成 [AppError]：連不上、逾時、TLS 失敗是 [NetworkError]，
/// 其他是 [UnexpectedError]。取消由呼叫端先處理。
AppError transportError(
  DioException error, {
  required String? pluginId,
  required int networkRecordId,
}) {
  NetworkError network({bool retryable = true}) => NetworkError(
    pluginId: pluginId,
    retryable: retryable,
    networkRecordId: networkRecordId,
    cause: error,
    stackTrace: error.stackTrace,
  );
  return switch (error.type) {
    DioExceptionType.connectionTimeout ||
    DioExceptionType.sendTimeout ||
    DioExceptionType.receiveTimeout ||
    DioExceptionType.connectionError => network(),
    // 憑證驗證不過，重送也一樣。
    DioExceptionType.badCertificate => network(retryable: false),
    // TLS 握手失敗（HandshakeException）、連線中斷（HttpException）等
    // dio 沒歸類的傳輸錯誤都是 IOException。
    DioExceptionType.unknown when error.error is IOException => network(),
    DioExceptionType.unknown ||
    DioExceptionType.badResponse ||
    DioExceptionType.transformTimeout ||
    DioExceptionType.cancel => UnexpectedError(
      pluginId: pluginId,
      networkRecordId: networkRecordId,
      cause: error,
      stackTrace: error.stackTrace,
    ),
  };
}
