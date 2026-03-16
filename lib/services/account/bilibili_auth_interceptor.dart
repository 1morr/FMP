import 'package:dio/dio.dart';

import '../../core/logger.dart';
import 'bilibili_account_service.dart';

/// Bilibili API 認證攔截器
///
/// 自動注入認證 Cookie 到請求，並檢測 -101/-111 認證錯誤。
/// Bilibili API 返回 HTTP 200 + JSON `{"code": -101}` 表示認證失敗，
/// 因此需要在 onResponse 中攔截（而非 onError）。
class BilibiliAuthInterceptor extends Interceptor with Logging {
  final BilibiliAccountService _accountService;
  bool _isRefreshing = false;

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
  Future<void> onResponse(
    Response response,
    ResponseInterceptorHandler handler,
  ) async {
    if (_isAuthError(response) && !_isRefreshing) {
      _isRefreshing = true;
      try {
        logWarning('Detected auth error in response, attempting credential refresh');
        final refreshed = await _accountService.refreshCredentials();
        if (refreshed) {
          try {
            // 用新 cookie 重試原始請求
            final retryResponse =
                await _accountService.dio.fetch(response.requestOptions);
            return handler.resolve(retryResponse);
          } catch (e) {
            logError('Retry after refresh failed', e);
          }
        }
      } finally {
        _isRefreshing = false;
      }
    }
    handler.next(response);
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    // HTTP 錯誤級別的認證失敗（較少見，但作為兜底）
    if (_isAuthError(err.response) && !_isRefreshing) {
      _isRefreshing = true;
      try {
        logWarning('Detected auth error in HTTP error, attempting credential refresh');
        final refreshed = await _accountService.refreshCredentials();
        if (refreshed) {
          try {
            final retryResponse =
                await _accountService.dio.fetch(err.requestOptions);
            return handler.resolve(retryResponse);
          } catch (e) {
            logError('Retry after refresh failed', e);
          }
        }
      } finally {
        _isRefreshing = false;
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
