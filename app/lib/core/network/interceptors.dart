part of 'source_http_client.dart';

// API client 的五個攔截器，順序照 ADR 0012 §決定 1：認證注入 → cookie 管理 →
// 錯誤對應 → 限流 → 網路紀錄。dio 對 onRequest、onResponse、onError 都依加入
// 的順序（FIFO）執行，不像 middleware 那樣回程反轉（dio `DioMixin.fetch`）；
// 所以網路紀錄在三條路上都是最後一個，記到的是前面處理過的結果。
//
// 攔截器 reject 一律帶 `callFollowingErrorInterceptor: true`：不帶的話 dio 會
// 跳過其後所有 onError，限流拿不回位置、網路紀錄也少一筆。

/// 一次送出（一跳的一次嘗試）的狀態。放在 `RequestOptions.extra`，五個攔截器
/// 與 [SourceHttpClient] 共用。
final class _Attempt {
  _Attempt({
    required this.recordId,
    required this.pluginId,
    required this.auth,
    required this.retry,
  });

  static const _key = 'fmp.attempt';

  static _Attempt of(RequestOptions options) =>
      options.extra[_key]! as _Attempt;

  final int recordId;
  final String pluginId;
  final AuthRequirement auth;

  /// 這是第幾次重試（原本那次為 0）。
  final int retry;

  bool credentialsAttached = false;
  DateTime? startedAt;
  ThrottleSlot? slot;

  Map<String, Object?> get extra => {_key: this};
}

DioException _rejection(
  RequestOptions options,
  AppError error, {
  Response<Object?>? response,
}) => DioException(
  requestOptions: options,
  response: response,
  error: error,
  message: error.typeName,
);

/// 認證注入：只依請求宣告的 [AuthRequirement] 與 [decideAuth] 的表決定。
final class _AuthInterceptor extends Interceptor {
  _AuthInterceptor(this._credentials);

  final CredentialSource _credentials;

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    final attempt = _Attempt.of(options);
    if (attempt.auth == AuthRequirement.never) return handler.next(options);
    final headers = await _credentials.credentialHeaders(attempt.pluginId);
    final decision = decideAuth(
      attempt.auth,
      loggedIn: headers != null,
      browseAsLoggedIn: await _credentials.browseAsLoggedIn(attempt.pluginId),
    );
    switch (decision) {
      case AuthDecision.attach:
        // 蓋掉插件自己給的同名 header；cookie 管理之後會把 jar 的 cookie
        // 併進 `Cookie`。
        options.headers.addAll(headers!);
        attempt.credentialsAttached = true;
        handler.next(options);
      case AuthDecision.omit:
        handler.next(options);
      case AuthDecision.refuse:
        handler.reject(
          _rejection(
            options,
            AuthRequired(
              pluginId: attempt.pluginId,
              networkRecordId: attempt.recordId,
            ),
          ),
          true,
        );
    }
  }
}

/// cookie 管理：`dio_cookie_manager`，只改一處。
///
/// 原版在 `followRedirects: false` 收到轉址時，會把這個回應的 `Set-Cookie`
/// 也存到 `Location` 的 host 底下（`CookieManager.saveCookies`），跨網域的
/// 下一跳就帶著上一個 host 設的 cookie。這裡只存到回應自己的網址（RFC 6265
/// §5.3 的 request-uri）。
final class _OwnHostCookieManager extends CookieManager {
  _OwnHostCookieManager(super.cookieJar);

  @override
  Future<void> saveCookies(Response<Object?> response) {
    final headers = {...response.headers.map}
      ..remove(HttpHeaders.locationHeader);
    return super.saveCookies(
      Response<Object?>(
        requestOptions: response.requestOptions,
        statusCode: response.statusCode,
        headers: Headers.fromMap(headers),
      ),
    );
  }
}

/// 每插件一個的記憶體 cookie jar。`cookie_jar` 的 `DefaultCookieJar` 照單收下
/// `Set-Cookie` 的 `Domain` 屬性，不檢查它是否涵蓋回應的 host（RFC 6265 §5.3
/// 第 6 步要求忽略這種 cookie），`example.test` 的回應就能替 `cdn.example` 設
/// cookie。這裡只收 `Domain` 涵蓋回應 host、而且本身在允許網域內的 cookie；
/// 後者代替 public suffix list，擋掉 `Domain=com`。
final class _OwnHostCookieJar extends DefaultCookieJar {
  _OwnHostCookieJar(this._allowedHosts);

  final AllowedHosts _allowedHosts;

  @override
  Future<void> saveFromResponse(Uri uri, List<Cookie> cookies) =>
      super.saveFromResponse(uri, [
        for (final cookie in cookies)
          if (_accepts(uri.host, cookie.domain)) cookie,
      ]);

  bool _accepts(String host, String? domainAttribute) {
    if (domainAttribute == null) return true;
    // `Domain=.example.test` 開頭的點不算（RFC 6265 §5.2.3）。
    final domain = domainAttribute.startsWith('.')
        ? domainAttribute.substring(1)
        : domainAttribute;
    return AllowedHosts.isSameOrSubdomain(host, domain) &&
        _allowedHosts.allowsHost(domain);
  }
}

/// 錯誤對應：傳輸錯誤轉 [NetworkError]，HTTP 通用的限流語意轉 [RateLimited]
/// （ADR 0013 §決定 2）。其他狀態碼原樣交給插件，由插件在自己的邊界對應。
final class _ErrorMappingInterceptor extends Interceptor {
  _ErrorMappingInterceptor(this._now);

  final DateTime Function() _now;

  @override
  void onResponse(
    Response<Object?> response,
    ResponseInterceptorHandler handler,
  ) {
    final rateLimited = _rateLimited(response);
    if (rateLimited == null) return handler.next(response);
    handler.reject(
      _rejection(response.requestOptions, rateLimited, response: response),
      true,
    );
  }

  RateLimited? _rateLimited(Response<Object?> response) {
    final attempt = _Attempt.of(response.requestOptions);
    return rateLimitedResponse(
      response.statusCode ?? 0,
      response.headers.map,
      now: _now(),
      pluginId: attempt.pluginId,
      networkRecordId: attempt.recordId,
    );
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    if (err.type == DioExceptionType.cancel || err.error is AppError) {
      return handler.next(err);
    }
    final attempt = _Attempt.of(err.requestOptions);
    handler.next(
      err.copyWith(
        error: transportError(
          err,
          pluginId: attempt.pluginId,
          networkRecordId: attempt.recordId,
        ),
      ),
    );
  }
}

/// 限流：插件宣告了 [RateLimitPolicy] 才有作用。等位置的時間不算進網路紀錄的
/// 耗時，因為網路紀錄排在它後面。
final class _ThrottleInterceptor extends Interceptor {
  _ThrottleInterceptor(this._throttle);

  final RequestThrottle? _throttle;

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    final throttle = _throttle;
    if (throttle == null) return handler.next(options);
    // 先記下位置再等：等的時候被取消，dio 直接走 onError，要在那裡讓出。
    final slot = _Attempt.of(options).slot = throttle.enqueue();
    await slot.granted;
    handler.next(options);
  }

  @override
  void onResponse(
    Response<Object?> response,
    ResponseInterceptorHandler handler,
  ) {
    _Attempt.of(response.requestOptions).slot?.release();
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    _Attempt.of(err.requestOptions).slot?.release();
    handler.next(err);
  }
}

/// 網路紀錄（ADR 0011 §決定 4）：每次送出一筆摘要，經 log 門面寫入，不記
/// body。query 原樣交給門面，由遮蔽函式處理。
final class _NetworkLogInterceptor extends Interceptor {
  _NetworkLogInterceptor(this._log, this._now);

  final Log _log;
  final DateTime Function() _now;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    _Attempt.of(options).startedAt = _now();
    handler.next(options);
  }

  @override
  void onResponse(
    Response<Object?> response,
    ResponseInterceptorHandler handler,
  ) {
    _write(
      response.requestOptions,
      response: response,
      failed: (response.statusCode ?? 0) >= 400,
    );
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final cancelled = err.type == DioExceptionType.cancel;
    _write(
      err.requestOptions,
      response: err.response,
      error: switch (err.error) {
        _ when cancelled => 'Cancelled',
        final AppError error => error.typeName,
        _ => 'UnexpectedError',
      },
      // 取消是呼叫端自己要的，不算失敗。
      failed: !cancelled,
    );
    handler.next(err);
  }

  void _write(
    RequestOptions options, {
    required bool failed,
    Response<Object?>? response,
    String? error,
  }) {
    final attempt = _Attempt.of(options);
    writeNetworkRecord(
      _log,
      client: NetworkClient.source,
      id: attempt.recordId,
      pluginId: attempt.pluginId,
      method: options.method,
      uri: options.uri,
      failed: failed,
      credentials: attempt.credentialsAttached,
      retry: attempt.retry,
      status: response?.statusCode,
      ms: switch (attempt.startedAt) {
        final started? => _now().difference(started).inMilliseconds,
        null => null,
      },
      bytes: switch (response?.data) {
        final List<int> body => body.length,
        _ => null,
      },
      error: error,
    );
  }
}
