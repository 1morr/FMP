import 'package:dio/dio.dart';

import '../../core/logger.dart';
import 'netease_account_service.dart';

/// 網易雲音樂 API 認證攔截器
///
/// 自動注入 Cookie header 到請求。
/// 比 Bilibili 簡單 — MUSIC_U 有效期長，不需要自動刷新邏輯。
class NeteaseAuthInterceptor extends Interceptor with Logging {
  final NeteaseAccountService _accountService;

  NeteaseAuthInterceptor(this._accountService);

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
}
