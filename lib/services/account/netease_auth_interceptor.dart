import 'package:dio/dio.dart';

import '../../core/logger.dart';
import 'netease_account_service.dart';

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
      if (code is int && code != 200 && code != 801 && code != 802 && code != 803) {
        logWarning('Netease response returned non-success code: $code');
      }
    }
    handler.next(response);
  }
}
