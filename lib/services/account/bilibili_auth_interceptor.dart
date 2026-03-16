import 'package:dio/dio.dart';

import '../../core/logger.dart';
import 'bilibili_account_service.dart';

/// Bilibili API 認證攔截器
///
/// 自動注入認證 Cookie 到請求，並檢測 -101/-111 認證錯誤。
class BilibiliAuthInterceptor extends Interceptor with Logging {
  final BilibiliAccountService _accountService;

  BilibiliAuthInterceptor(this._accountService);

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    final authCookies = await _accountService.getAuthCookieString();
    if (authCookies != null) {
      final existing = options.headers['Cookie'] as String? ?? '';
      options.headers['Cookie'] =
          existing.isEmpty ? authCookies : '$existing; $authCookies';
    }
    handler.next(options);
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    if (_isAuthError(err.response)) {
      logWarning('Detected auth error, attempting credential refresh');
      final refreshed = await _accountService.refreshCredentials();
      if (refreshed) {
        try {
          // 重試原始請求
          final retryResponse =
              await _accountService.dio.fetch(err.requestOptions);
          return handler.resolve(retryResponse);
        } catch (e) {
          logError('Retry after refresh failed', e);
        }
      }
    }
    handler.next(err);
  }

  bool _isAuthError(Response? response) {
    try {
      final code = response?.data?['code'];
      return code == -101 || code == -111;
    } catch (_) {
      return false;
    }
  }
}
