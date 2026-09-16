import 'package:dio/dio.dart';

import 'package:fmp/core/logger.dart';
import 'package:fmp/services/account/netease_account_service.dart';

/// 網易雲 API 認證攔截器
///
/// 自動注入認證 header，並在 `code == 301`（未登入）時把帳號標成失效
/// （`markSessionExpired()`）。攔截器是在服務內部建構的，拿不到
/// Riverpod，所以這裡只寫狀態 —— 提示由 `accountSessionExpiryWatcherProvider`
/// 看著 `Account` 列補上。
class NeteaseAuthInterceptor extends Interceptor with Logging {
  final NeteaseAccountService _accountService;

  NeteaseAuthInterceptor(this._accountService);

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    final headers = await _accountService.getAuthHeaders();
    if (headers != null) {
      for (final entry in headers.entries) {
        // Skip if the header is already explicitly set (e.g. _postLinuxApi sets its own Cookie)
        if (entry.key.toLowerCase() == 'cookie' &&
            options.headers.containsKey('Cookie')) {
          continue;
        }
        options.headers[entry.key] = entry.value;
      }
    }
    handler.next(options);
  }

  @override
  Future<void> onResponse(
    Response response,
    ResponseInterceptorHandler handler,
  ) async {
    final data = response.data;
    if (data is Map<String, dynamic>) {
      final code = data['code'];
      if (code is int &&
          code != 200 &&
          code != 801 &&
          code != 802 &&
          code != 803) {
        logWarning('Netease response returned non-success code: $code');
      }
      // 301 = 未登入。帶著憑證發出去卻拿到它，就是憑證失效；沒登入的請求本來
      // 就會拿到 301，那個不算，所以先問帳號狀態。標記後 isLoggedIn 就是 false，
      // 接下來的 301 不會重複寫。
      if (code == 301 && await _accountService.isLoggedIn()) {
        await _accountService.markSessionExpired();
      }
    }
    handler.next(response);
  }
}
