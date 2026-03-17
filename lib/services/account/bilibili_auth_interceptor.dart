import 'dart:async';

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
  Completer<bool>? _refreshCompleter;

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
    if (_isAuthError(response)) {
      final retryResponse = await _refreshAndRetry(response.requestOptions);
      if (retryResponse != null) {
        return handler.resolve(retryResponse);
      }
    }
    handler.next(response);
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    if (_isAuthError(err.response)) {
      final retryResponse = await _refreshAndRetry(err.requestOptions);
      if (retryResponse != null) {
        return handler.resolve(retryResponse);
      }
    }
    handler.next(err);
  }

  /// 刷新憑據並重試請求。
  ///
  /// 使用 Completer 確保併發請求只觸發一次刷新，其他請求等待結果。
  Future<Response?> _refreshAndRetry(RequestOptions requestOptions) async {
    final refreshed = await _ensureRefreshed();
    if (!refreshed) return null;

    try {
      return await _accountService.dio.fetch(requestOptions);
    } catch (e) {
      logError('Retry after refresh failed', e);
      return null;
    }
  }

  /// 確保只有一次刷新操作在進行中，併發調用共享同一個結果。
  Future<bool> _ensureRefreshed() async {
    if (_refreshCompleter != null) {
      return _refreshCompleter!.future;
    }

    final completer = Completer<bool>();
    _refreshCompleter = completer;
    try {
      logWarning('Detected auth error, attempting credential refresh');
      final result = await _accountService.refreshCredentials();
      completer.complete(result);
      return result;
    } catch (e) {
      logError('Credential refresh failed', e);
      completer.complete(false);
      return false;
    } finally {
      // 只清除自己創建的 completer，避免清除併發請求創建的新 completer
      if (_refreshCompleter == completer) {
        _refreshCompleter = null;
      }
    }
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
