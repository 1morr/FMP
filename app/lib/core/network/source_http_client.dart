import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';

import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/core/errors/retry_policy.dart';
import 'package:fmp/core/logging/log.dart';
import 'package:fmp/core/logging/log_record.dart';
import 'package:fmp/core/network/allowed_hosts.dart';
import 'package:fmp/core/network/auth.dart';
import 'package:fmp/core/network/request_throttle.dart';

part 'interceptors.dart';

/// 網路紀錄的 log tag。
const networkLogTag = 'network';

/// 一次最多跟隨幾次轉址（ADR 0012 §決定 1；dio 的 `maxRedirects` 預設也是 5）。
const maxRedirects = 5;

/// 沿用舊版 `AppConstants.networkConnectTimeout`／`networkReceiveTimeout`。
/// receive 是兩次收到資料之間的上限，不是整個回應（dio `receiveTimeout`）。
const _connectTimeout = Duration(seconds: 10);
const _receiveTimeout = Duration(seconds: 30);

/// 會轉址的狀態碼（RFC 9110 §15.4）。300 與 304 不自動跟隨。
const _redirectStatuses = {301, 302, 303, 307, 308};

/// 跨網域轉址時從原請求拿掉的 header（名稱小寫）。
const _crossHostStrippedHeaders = {
  'cookie',
  'authorization',
  'proxy-authorization',
};

/// 插件給的一個 API 請求。
final class SourceRequest {
  const SourceRequest(
    this.url, {
    this.method = 'GET',
    this.headers = const {},
    this.body,
    this.auth = AuthRequirement.never,
  });

  final Uri url;

  /// HTTP 方法，照 RFC 9110 分大小寫（`GET`，不是 `get`）。重試只看它判斷
  /// 冪等（`isIdempotent`）。
  final String method;

  final Map<String, String> headers;
  final String? body;

  /// 帶不帶憑證（ADR 0012 §決定 2）。
  final AuthRequirement auth;
}

/// 請求的結果。狀態碼不在網路層判斷：429 與帶 `Retry-After` 的 503 以外，
/// 原樣交給插件對應（ADR 0013 §決定 2）。
final class SourceResponse {
  const SourceResponse({
    required this.url,
    required this.statusCode,
    required this.headers,
    required this.body,
  });

  /// 跟隨轉址後的最終網址。
  final Uri url;
  final int statusCode;

  /// 名稱小寫。
  final Map<String, List<String>> headers;
  final Uint8List body;
}

/// 呼叫端以 `abortTrigger` 取消了請求。只有取消的一方會收到，不是
/// [AppError]，不重試、不 report。
final class RequestCancelled implements Exception {
  const RequestCancelled();

  @override
  String toString() => 'RequestCancelled';
}

/// 依插件建立 [SourceHttpClient]（ADR 0012 §決定 1：每個音源一個 API
/// client）。App 共用的東西（log、認證來源、時鐘）在這裡給一次。
///
/// [createAdapter] 是 dio 最底層的 `HttpClientAdapter`，每個 client 各建一個；
/// fixture 的錄製與重播（ADR 0015 §決定 5）換掉它。[now]、[wait]、[random]
/// 給重試、限流與網路紀錄用，測試注入假的。
final class SourceHttpClientFactory {
  SourceHttpClientFactory({
    required this._log,
    this._credentials = const NoCredentials(),
    this._createAdapter = IOHttpClientAdapter.new,
    this._now = DateTime.now,
    this._wait = _delay,
    math.Random? random,
  }) : _random = random ?? math.Random();

  final Log _log;
  final CredentialSource _credentials;
  final HttpClientAdapter Function() _createAdapter;
  final DateTime Function() _now;
  final Future<void> Function(Duration) _wait;
  final math.Random _random;

  /// 網路紀錄的 id，整個 App 執行期間遞增。
  int _lastRecordId = 0;

  /// [pluginId] 的 client。[allowedHosts] 是 manifest 的允許網域；
  /// [retryPolicy]、[rateLimitPolicy] 是 manifest 宣告的策略，沒宣告限流就
  /// 不限。
  SourceHttpClient create({
    required String pluginId,
    required Iterable<String> allowedHosts,
    RetryPolicy retryPolicy = const RetryPolicy(),
    RateLimitPolicy? rateLimitPolicy,
  }) {
    final hosts = AllowedHosts(allowedHosts);
    // 唯一建立 Dio 的地方（fmp_http_client_owner）。
    final dio =
        Dio(
            BaseOptions(
              connectTimeout: _connectTimeout,
              receiveTimeout: _receiveTimeout,
            ),
          )
          ..httpClientAdapter = _createAdapter()
          ..interceptors.addAll([
            _AuthInterceptor(_credentials),
            // 每插件一個記憶體 cookie jar；要跨重啟的匿名 cookie 由插件自己
            // 存（app/AGENTS.md § 網路）。
            _OwnHostCookieManager(_OwnHostCookieJar(hosts)),
            _ErrorMappingInterceptor(_now),
            _ThrottleInterceptor(switch (rateLimitPolicy) {
              null => null,
              final policy => RequestThrottle(policy, now: _now, wait: _wait),
            }),
            _NetworkLogInterceptor(_log, _now),
          ]);
    return SourceHttpClient._(
      pluginId: pluginId,
      allowedHosts: hosts,
      retryPolicy: retryPolicy,
      dio: dio,
      nextRecordId: () => ++_lastRecordId,
      wait: _wait,
      random: _random,
    );
  }
}

Future<void> _delay(Duration duration) => Future<void>.delayed(duration);

/// 一個插件的 API client：該插件所有請求共用（ADR 0012 §決定 1）。
///
/// [send] 依序做：網域檢查 → 送出（經五個攔截器）→ 可重試的錯誤依
/// [RetryPolicy] 退避重送 → 轉址就檢查網域後跟隨下一跳。丟出的錯誤都是
/// [AppError]，取消例外（[RequestCancelled]）。
final class SourceHttpClient {
  SourceHttpClient._({
    required this.pluginId,
    required this._allowedHosts,
    required this._retryPolicy,
    required this._dio,
    required this._nextRecordId,
    required this._wait,
    required this._random,
  });

  final String pluginId;
  final AllowedHosts _allowedHosts;
  final RetryPolicy _retryPolicy;
  final Dio _dio;
  final int Function() _nextRecordId;
  final Future<void> Function(Duration) _wait;
  final math.Random _random;

  /// 送出 [request]。[abortTrigger] 完成時取消（`package:http` 的
  /// `Abortable.abortTrigger` 同樣的寫法），丟 [RequestCancelled]。
  ///
  /// 網址不在允許網域或不是 `https` 時不發請求，丟 [Unsupported]；轉址出網域、
  /// `Location` 解析不了或超過 [maxRedirects] 次也是。
  Future<SourceResponse> send(
    SourceRequest request, {
    Future<void>? abortTrigger,
  }) async {
    final cancelToken = CancelToken();
    // 觸發的 Future 以錯誤結束也算取消。
    abortTrigger?.whenComplete(cancelToken.cancel).ignore();
    var hop = request;
    for (var redirects = 0; ; redirects++) {
      if (!_allowedHosts.allows(hop.url)) {
        throw Unsupported(
          pluginId: pluginId,
          cause: StateError('Host not allowed: ${hop.url.host}'),
          stackTrace: StackTrace.current,
        );
      }
      final (:response, :recordId) = await _sendWithRetry(hop, cancelToken);
      final location = _redirectLocation(response);
      if (location == null) return response;
      if (redirects == maxRedirects) {
        throw Unsupported(
          pluginId: pluginId,
          networkRecordId: recordId,
          cause: StateError('More than $maxRedirects redirects'),
          stackTrace: StackTrace.current,
        );
      }
      final Uri next;
      try {
        next = hop.url.resolve(location);
      } on FormatException catch (error, stackTrace) {
        // 伺服器給的 `Location` 解析不了：跟不下去，同出網域一樣失敗。
        throw Unsupported(
          pluginId: pluginId,
          networkRecordId: recordId,
          cause: error,
          stackTrace: stackTrace,
        );
      }
      if (!_allowedHosts.allows(next)) {
        throw Unsupported(
          pluginId: pluginId,
          networkRecordId: recordId,
          cause: StateError('Redirect to a host not allowed: ${next.host}'),
          stackTrace: StackTrace.current,
        );
      }
      hop = _redirected(hop, next, response.statusCode);
    }
  }

  /// 關閉底層的連線。
  void close() => _dio.close(force: true);

  Future<({SourceResponse response, int recordId})> _sendWithRetry(
    SourceRequest request,
    CancelToken cancelToken,
  ) async {
    for (var retry = 0; ; retry++) {
      if (cancelToken.isCancelled) throw const RequestCancelled();
      final attempt = _Attempt(
        recordId: _nextRecordId(),
        pluginId: pluginId,
        auth: request.auth,
        retry: retry,
      );
      final AppError error;
      try {
        final response = await _dio.requestUri<List<int>>(
          request.url,
          data: request.body,
          cancelToken: cancelToken,
          options: Options(
            method: request.method,
            headers: {...request.headers},
            extra: attempt.extra,
            responseType: ResponseType.bytes,
            followRedirects: false,
            validateStatus: (_) => true,
          ),
        );
        return (
          response: SourceResponse(
            url: request.url,
            statusCode: response.statusCode!,
            headers: response.headers.map,
            body: switch (response.data) {
              null => Uint8List(0),
              final Uint8List bytes => bytes,
              final List<int> bytes => Uint8List.fromList(bytes),
            },
          ),
          recordId: attempt.recordId,
        );
      } on DioException catch (failure) {
        if (failure.type == DioExceptionType.cancel) {
          throw const RequestCancelled();
        }
        error = switch (failure.error) {
          final AppError mapped => mapped,
          // 錯誤對應攔截器已經轉好；走到這裡代表它之後的攔截器出錯。
          _ => UnexpectedError(
            pluginId: pluginId,
            networkRecordId: attempt.recordId,
            cause: failure,
            stackTrace: failure.stackTrace,
          ),
        };
      }
      final delay =
          shouldRetry(
            error,
            attempt: retry,
            method: request.method,
            policy: _retryPolicy,
          )
          ? delayFor(
              error,
              attempt: retry,
              policy: _retryPolicy,
              random: _random,
            )
          : null;
      if (delay == null) throw error;
      await Future.any([_wait(delay), cancelToken.whenCancel]);
    }
  }

  /// [response] 要跟隨的 `Location`；不是轉址回 `null`。
  static String? _redirectLocation(SourceResponse response) {
    if (!_redirectStatuses.contains(response.statusCode)) return null;
    final location = response.headers[HttpHeaders.locationHeader]?.first;
    return location == null || location.isEmpty ? null : location;
  }

  /// 往 [next] 的下一跳。
  ///
  /// - 303，以及 POST 收到 301／302：改用 GET、不帶 body（RFC 9110 §15.4.2–4；
  ///   瀏覽器的 fetch 也這樣做）。307／308 保留方法與 body。
  /// - 跨 host：拿掉原請求的 `Cookie`、`Authorization`，而且不再帶憑證
  ///   （[AuthRequirement.never]）。jar 裡的 cookie 由 cookie 管理照網域決定。
  static SourceRequest _redirected(
    SourceRequest hop,
    Uri next,
    int statusCode,
  ) {
    final toGet =
        statusCode == 303 ||
        ((statusCode == 301 || statusCode == 302) && hop.method == 'POST');
    final crossHost = !AllowedHosts.sameHost(hop.url, next);
    return SourceRequest(
      next,
      method: toGet && hop.method != 'HEAD' ? 'GET' : hop.method,
      headers: {
        for (final MapEntry(:key, :value) in hop.headers.entries)
          if (!(crossHost &&
                  _crossHostStrippedHeaders.contains(key.toLowerCase())) &&
              !(toGet && key.toLowerCase() == 'content-type'))
            key: value,
      },
      body: toGet ? null : hop.body,
      auth: crossHost ? AuthRequirement.never : hop.auth,
    );
  }
}
