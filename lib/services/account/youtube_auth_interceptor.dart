import 'package:dio/dio.dart';

import '../../core/logger.dart';
import 'youtube_account_service.dart';

/// YouTube API 認證攔截器
///
/// 自動注入 Cookie + SAPISIDHASH Authorization header。
/// YouTube Cookie 有效期 ~2 年，無需刷新邏輯。
/// 認證失敗直接透傳（不重試）。
class YouTubeAuthInterceptor extends Interceptor with Logging {
  final YouTubeAccountService _accountService;

  YouTubeAuthInterceptor(this._accountService);

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    final headers = await _accountService.getAuthHeaders();
    if (headers != null) {
      options.headers['Cookie'] = headers['Cookie'];
      options.headers['Authorization'] = headers['Authorization'];
    }
    handler.next(options);
  }

  @override
  Future<void> onResponse(
    Response response,
    ResponseInterceptorHandler handler,
  ) async {
    if (_isAuthError(response)) {
      logWarning('YouTube auth error detected in response');
    }
    handler.next(response);
  }

  /// 檢測 YouTube InnerTube 認證錯誤
  ///
  /// InnerTube 認證失敗的特徵：
  /// - 響應中缺少 `contents` key（未認證的 browse 請求）
  /// - 包含 `UNAUTHENTICATED` 錯誤碼
  bool _isAuthError(Response? response) {
    try {
      final data = response?.data;
      if (data is! Map) return false;

      // 檢查 error 字段
      final error = data['error'];
      if (error is Map) {
        final status = error['status'] as String?;
        if (status == 'UNAUTHENTICATED') return true;
      }

      return false;
    } catch (_) {
      return false;
    }
  }
}
